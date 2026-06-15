import Foundation
import EventKit
import Observation
import os

// MARK: - CalendarKitService
//
// Local-first, read-only bridge into the system calendar via EventKit.
// Avenor never writes to the user's calendars — it only mirrors EKEvents
// into the daily timeline so the user sees their meetings next to their
// tasks. One persistent EKEventStore lives for the whole app session; the
// fetch itself runs off the main actor so 120Hz scrolling is never blocked.
//
// A per-session in-memory cache (keyed by start-of-day) makes adjacent-day
// navigation instant after the first scan — toggling Mon→Tue→Mon re-reads
// the cache instead of re-scanning EventKit.

@MainActor
@Observable
final class CalendarKitService {

    /// Single app-wide instance so the EKEventStore + cache survive tab
    /// switches and view re-creation for the lifetime of the session.
    static let shared = CalendarKitService()

    /// Whether the user has granted full calendar read access. Drives the
    /// permission prompt / event rendering in the timeline.
    private(set) var isCalendarAccessGranted = false

    /// The single persistent store. Reused for every predicate + fetch.
    private let store = EKEventStore()

    /// Per-session day cache: startOfDay → sorted events.
    private var cache: [Date: [EKEvent]] = [:]

    private let calendar = Calendar.autoupdatingCurrent
    private let logger = Logger(subsystem: "com.remyavipindas.avenor", category: "calendar")

    private init() {
        // Reflect any access already granted in a prior session so the first
        // fetch doesn't need to wait on a redundant prompt.
        let status = EKEventStore.authorizationStatus(for: .event)
        isCalendarAccessGranted = (status == .fullAccess)
    }

    // MARK: Authorization

    /// Requests full read access (iOS 17+ API). Idempotent — returns the
    /// current grant state without re-prompting once decided.
    @discardableResult
    func requestAccessIfNeeded() async -> Bool {
        if isCalendarAccessGranted { return true }
        do {
            let granted = try await store.requestFullAccessToEvents()
            isCalendarAccessGranted = granted
            if !granted { logger.notice("Calendar access denied by user.") }
            return granted
        } catch {
            logger.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
            isCalendarAccessGranted = false
            return false
        }
    }

    // MARK: Fetch

    /// Returns the events occurring on `date`, sorted chronologically by
    /// start time. Reads the session cache first; otherwise scans EventKit
    /// off the main actor and memoizes the result. Never throws — a failure
    /// or denied permission yields an empty timeline.
    func fetchEvents(for date: Date) async -> [EKEvent] {
        guard isCalendarAccessGranted else { return [] }

        let dayStart = calendar.startOfDay(for: date)
        if let cached = cache[dayStart] { return cached }

        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        // 23:59:59 of the target day — an inclusive upper bound.
        let dayEnd = nextDay.addingTimeInterval(-1)

        let store = self.store
        let events = await Task.detached(priority: .userInitiated) {
            // nil calendars → scan every visible account (iCloud, Google, etc.).
            let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
            return store.events(matching: predicate).sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }      // all-day floats to top
                return lhs.startDate < rhs.startDate
            }
        }.value

        cache[dayStart] = events
        return events
    }

    /// Drops the cache so the next fetch re-scans EventKit. Call when the
    /// app returns to the foreground (external calendar edits may have landed).
    func invalidateCache() {
        cache.removeAll()
    }
}
