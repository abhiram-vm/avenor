import Foundation
import UserNotifications
import os

// MARK: - NotificationManager
//
// Single source of truth for local notifications. Phase 3 foundation —
// wired into task lifecycle (create / update deadline / complete / delete)
// from the UI layer. No remote push, no APNs.
//
// Design notes:
//   • Uses `UNCalendarNotificationTrigger` with the current calendar so
//     scheduled fire times follow the user across timezone changes.
//   • Identifier shape is `task.<UUID>` — one-to-one with `PersistedTask.id`
//     so we can cancel without bookkeeping.
//   • `requestAuthorization` is idempotent and safe to call on every launch;
//     iOS returns the cached decision after the first prompt.
//   • All paths are fail-soft: a failure here must never surface as a user
//     error. We log via `os.Logger` and move on.

@MainActor
final class NotificationManager {

    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "com.remyavipindas.avenor", category: "notifications")

    private init() {}

    // MARK: Authorization

    /// Requests `.alert .sound .badge`. Returns the granted state so callers
    /// can update UI affordances ("Enable notifications…" prompts) — but
    /// callers may also ignore the result entirely.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("Authorization request resolved. granted=\(granted, privacy: .public)")
            return granted
        } catch {
            logger.error("Authorization request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Cached current status. Use to gate UI affordances without prompting.
    func currentStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: Scheduling

    /// Schedules (or re-schedules) a local notification for the given task.
    /// No-op for tasks without a `dueDate`, completed tasks, or ideas.
    func schedule(for task: PersistedTask) {
        let id = identifier(for: task.id)

        // Guard: user has disabled Smart Notifications in Settings. We
        // proactively cancel any previously-scheduled fire so the flip is
        // observable immediately, not on the next mutation.
        guard Preferences.notificationsEnabled else {
            cancel(id: id)
            return
        }

        // Guard: no deadline, nothing to schedule.
        guard let due = task.dueDate else {
            cancel(id: id)
            return
        }

        // Guard: completed tasks shouldn't fire.
        if task.isDone == true {
            cancel(id: id)
            return
        }

        // Guard: ideas don't get notifications in Phase 3.
        if task.type == .idea {
            cancel(id: id)
            return
        }

        // Guard: don't schedule in the past.
        if due <= Date.now {
            cancel(id: id)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = task.title.isEmpty ? task.type.displayName : task.title
        content.body = task.details
        content.sound = .default
        content.userInfo = ["taskID": task.id.uuidString, "type": task.type.rawValue]

        // Calendar-based trigger lets iOS recompute the fire date when the
        // user crosses timezones — preferable to an interval trigger.
        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: due
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        // Replace any existing request with the same id.
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.add(request) { [logger] error in
            if let error {
                logger.error("Schedule failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            } else {
                logger.debug("Scheduled \(id, privacy: .public) for \(due, privacy: .public)")
            }
        }
    }

    // MARK: Cancellation

    /// Cancels the scheduled notification (if any) for the given task id.
    func cancel(for taskID: UUID) {
        cancel(id: identifier(for: taskID))
    }

    /// Convenience overload — caller passes the model directly.
    func cancel(for task: PersistedTask) {
        cancel(for: task.id)
    }

    private func cancel(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
        logger.debug("Cancelled \(id, privacy: .public)")
    }

    // MARK: Bulk reconcile
    //
    // Optional helper for app-launch reconciliation: walks the current task
    // set and re-asserts the schedule, dropping orphans for deleted tasks.

    func reconcile(against tasks: [PersistedTask]) async {
        let pending = await center.pendingNotificationRequests()
        let liveIDs = Set(tasks.map { identifier(for: $0.id) })
        let orphanIDs = pending.map(\.identifier).filter { !liveIDs.contains($0) }
        if !orphanIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: orphanIDs)
            logger.info("Reconcile pruned \(orphanIDs.count, privacy: .public) orphan(s).")
        }
        for task in tasks { schedule(for: task) }
    }

    // MARK: Identifier shape

    private func identifier(for taskID: UUID) -> String {
        "task.\(taskID.uuidString)"
    }
}
