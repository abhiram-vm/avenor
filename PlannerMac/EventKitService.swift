import Foundation
import EventKit
import SwiftData
import Observation
import AppKit
import os

// MARK: - EventKitService
//
// macOS-native bridge into the system calendars via EventKit. Unlike the iOS
// `CalendarKitService` (read-only timeline mirror), the Mac knowledge-layer
// needs read AND create: the capture bar books events, the Calendar pane reads
// the week. Editing stays in Calendar.app — we deep-link out rather than build
// an in-app editor.
//
// One persistent `EKEventStore` lives for the whole session (calendar access is
// a system-wide grant, so a single store is sufficient and cheapest). Exposed
// as a `.shared` singleton so the capture bar (in `Mac_ContentView`) and the
// Calendar pane observe the same authorization state and write to the same
// store — mirroring `CalendarKitService.shared`.
//
// Permission uses the macOS 13+ `requestFullAccessToEvents()` API (NOT the
// deprecated completion-handler form). Full access is required: the pane reads
// every visible calendar and the capture bar writes to the default one.

@MainActor
@Observable
final class EventKitService {

    /// Single app-wide instance: shared store + authorization state across the
    /// capture bar and the Calendar pane for the session's lifetime.
    static let shared = EventKitService()

    /// Live EventKit authorization. Drives the pane's permission gating.
    private(set) var authorizationStatus: EKAuthorizationStatus

    /// `true` when access is denied/restricted (or a request came back not
    /// granted). The pane reads this to show its System-Settings explainer.
    var accessDenied: Bool = false

    private let store = EKEventStore()
    private let calendar = Calendar.autoupdatingCurrent
    private let logger = Logger(subsystem: "com.avenor.planner", category: "eventkit.mac")

    init() {
        let status = EKEventStore.authorizationStatus(for: .event)
        authorizationStatus = status
        accessDenied = (status == .denied || status == .restricted)
    }

    // MARK: Authorization

    /// Request full calendar access once. Idempotent: if access is already
    /// granted this just refreshes the cached status and returns without
    /// re-prompting (the system itself never re-prompts after a decision).
    func requestAccess() async {
        if authorizationStatus == .fullAccess {
            accessDenied = false
            return
        }
        do {
            let granted = try await store.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            accessDenied = !granted
            if !granted { logger.notice("Calendar access not granted by user.") }
        } catch {
            logger.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            accessDenied = true
        }
    }

    // MARK: Fetch

    /// Events from `startingFrom` (start-of-day) through 7 days out — the full
    /// week. Scans every calendar (`calendars: nil`), drops events the user has
    /// declined, and returns them sorted by start time. All-day events are
    /// retained (the view separates them via `isAllDay`). Never throws: no
    /// access or a fetch miss yields an empty week.
    func fetchWeekEvents(startingFrom: Date) -> [EKEvent] {
        guard authorizationStatus == .fullAccess else { return [] }

        let start = calendar.startOfDay(for: startingFrom)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !isDeclined($0) }
            .sorted { $0.startDate < $1.startDate }
    }

    /// An event counts as declined only when the current user is an attendee
    /// whose participation status is `.declined`. Personal events (no
    /// attendees, or no current-user attendee) are never treated as declined.
    private func isDeclined(_ event: EKEvent) -> Bool {
        guard let me = event.attendees?.first(where: { $0.isCurrentUser }) else { return false }
        return me.participantStatus == .declined
    }

    // MARK: Create

    /// Create an event on the user's default calendar and commit it. Returns
    /// `true` on success, `false` on any failure (logged, never thrown).
    ///
    /// `context` is accepted for call-site symmetry with the SwiftData mutators
    /// but is unused: an EKEvent save never touches the SwiftData store.
    @discardableResult
    func createEvent(title: String,
                     startDate: Date,
                     duration: TimeInterval = 3600,
                     context: ModelContext) -> Bool {
        guard let defaultCalendar = store.defaultCalendarForNewEvents else {
            logger.error("No default calendar available for new events.")
            print("EventKitService.createEvent: no default calendar (access not granted?)")
            return false
        }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(duration)
        event.calendar = defaultCalendar
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return true
        } catch {
            logger.error("Failed to save event: \(error.localizedDescription, privacy: .public)")
            print("EventKitService.createEvent failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: Open in Calendar.app

    /// Deep-link an event into Calendar.app. Falls back to opening Calendar.app
    /// at its root if the event has no identifier or the URL can't be formed.
    func openInCalendarApp(event: EKEvent) {
        if let id = event.eventIdentifier,
           !id.isEmpty,
           let url = URL(string: "x-apple-calevent://\(id)") {
            NSWorkspace.shared.open(url)
        } else if let fallback = URL(string: "x-apple-cal://") {
            NSWorkspace.shared.open(fallback)
        }
    }
}
