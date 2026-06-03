import Foundation
import SwiftData
import SwiftUI

// MARK: - LifecycleAutomation
//
// Temporal hygiene. Runs on app activation and whenever the scene flips
// back to `.active`. Currently has two responsibilities:
//
//   1. Auto-archive dead reminders. A `.reminder` whose `dueDate` is more
//      than 48 hours in the past is flagged `isDone = true` and stamped
//      `completedAt = .now`. The user never sees expired alerts
//      cluttering the active stream — they slide into the archive drawer
//      silently.
//
//   2. Expose a pure helper `isIdeaStale(_:)` that the Tasks page reads to
//      bucket ageing ideas into a "Marinating" sub-section. Decay is
//      computed off `updatedAt`, which `TaskMutator.markInteracted(_:)`
//      bumps on expand / status flip / tag edit.
//
// No side effects beyond SwiftData mutations + notification cancellation.

@MainActor
enum LifecycleAutomation {

    /// 48 hours expressed in seconds. Dead reminders past this window get
    /// silently archived on the next maintenance pass.
    static let reminderDeathInterval: TimeInterval = 48 * 60 * 60

    /// 7 days. Past this without interaction an idea visually decays and
    /// gets sorted to the "Marinating" sub-section.
    static let ideaStaleInterval: TimeInterval = 7 * 24 * 60 * 60

    /// One-shot maintenance pass. Idempotent — safe to call on every scene
    /// activation. Re-runs are cheap (single fetch + linear scan).
    static func runDailyMaintenance(in context: ModelContext) {
        autoArchiveDeadReminders(in: context)
    }

    // MARK: Reminder auto-archive

    private static func autoArchiveDeadReminders(in context: ModelContext) {
        let cutoff = Date.now.addingTimeInterval(-reminderDeathInterval)
        let descriptor = FetchDescriptor<PersistedTask>()
        guard let all = try? context.fetch(descriptor) else { return }

        for task in all where shouldAutoArchive(task, beforeCutoff: cutoff) {
            task.isDone = true
            task.completedAt = .now
            task.updatedAt = .now
            // Cancel any scheduled notification that hasn't fired yet —
            // a 48h+ overdue reminder is past saving.
            NotificationManager.shared.cancel(for: task)
        }
    }

    private static func shouldAutoArchive(_ task: PersistedTask, beforeCutoff cutoff: Date) -> Bool {
        guard task.type == .reminder else { return false }
        guard !(task.isDone ?? false) else { return false }
        guard let due = task.dueDate else { return false }
        return due < cutoff
    }

    // MARK: Idea decay

    /// Pure predicate. `true` when an idea has gone untouched for more than
    /// `ideaStaleInterval`. Reads `updatedAt` as the activity timestamp —
    /// callers must route every meaningful interaction through
    /// `TaskMutator.markInteracted(_:)` for this to stay honest.
    nonisolated static func isIdeaStale(_ task: PersistedTask, now: Date = .now) -> Bool {
        guard task.type == .idea else { return false }
        // Completed ideas don't decay — they belong in the archive.
        guard (task.ideaStatus ?? .thinking) != .completed else { return false }
        return now.timeIntervalSince(task.updatedAt) > ideaStaleInterval
    }
}
