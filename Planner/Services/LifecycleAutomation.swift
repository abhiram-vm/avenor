import Foundation
import SwiftData
import SwiftUI
import os

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

    private static let logger = Logger(subsystem: "com.avenor.planner", category: "lifecycle")

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
        checkStreakLapses(in: context)
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

    // MARK: Smart rollover — Action Debt

    /// Outstanding "Action Debt": actionable tasks (`.todo` / `.reminder`)
    /// that are still open and whose `dueDate` fell strictly before the
    /// calendar start of `asOf`. Ideas are excluded — they marinate, they
    /// don't accrue debt. Sorted oldest-first so the UI reads chronologically.
    static func outstandingActionDebt(
        in context: ModelContext,
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> [PersistedTask] {
        let startOfToday = calendar.startOfDay(for: now)
        let descriptor = FetchDescriptor<PersistedTask>()
        guard let all = try? context.fetch(descriptor) else { return [] }

        return all
            .filter { task in
                guard task.type == .todo || task.type == .reminder else { return false }
                guard !(task.isDone ?? false) else { return false }
                guard let due = task.dueDate else { return false }
                return due < startOfToday
            }
            .sorted { lhs, rhs in
                (lhs.dueDate ?? .distantPast) < (rhs.dueDate ?? .distantPast)
            }
    }

    /// Atomically roll a batch of overdue tasks forward onto `target`'s
    /// calendar day, preserving each task's original wall-clock time. Bumps
    /// `updatedAt`, persists once, reschedules notifications, and republishes
    /// the widget snapshot so the Today glance reflects the new due dates.
    static func rollForwardTasks(
        _ tasks: [PersistedTask],
        to target: Date,
        in context: ModelContext,
        calendar: Calendar = .current
    ) {
        guard !tasks.isEmpty else { return }
        let targetDay = calendar.startOfDay(for: target)
        let now = Date.now

        for task in tasks {
            let newDue: Date
            if let oldDue = task.dueDate {
                // Preserve the original clock time on the new day.
                let comps = calendar.dateComponents([.hour, .minute, .second], from: oldDue)
                newDue = calendar.date(
                    bySettingHour: comps.hour ?? 0,
                    minute: comps.minute ?? 0,
                    second: comps.second ?? 0,
                    of: targetDay
                ) ?? targetDay
            } else {
                newDue = targetDay
            }
            task.dueDate = newDue
            task.updatedAt = now
            NotificationManager.shared.schedule(for: task)
        }

        do {
            try context.save()
        } catch {
            logger.error("rollForwardTasks save failed: \(error.localizedDescription, privacy: .public)")
        }

        let snapshot = (try? context.fetch(FetchDescriptor<PersistedTask>())) ?? tasks
        WidgetSnapshotPublisher.publishToday(tasks: snapshot)
    }

    // MARK: Streak lapse evaluation

    /// Scan every live routine and flip its broken/restoration flags when a
    /// scheduled completion window was missed. Preserves the historical streak
    /// integer — restoration ("Burn a Task") re-locks it. Idempotent.
    static func checkStreakLapses(
        in context: ModelContext,
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) {
        var descriptor = FetchDescriptor<PersistedHabit>()
        descriptor.fetchLimit = 200
        guard let habits = try? context.fetch(descriptor) else { return }
        for habit in habits where !habit.isArchived {
            habit.checkStreakLapse(currentDate: now, calendar: calendar)
        }
        do {
            try context.save()
        } catch {
            logger.error("checkStreakLapses save failed: \(error.localizedDescription, privacy: .public)")
        }
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
