import Foundation
import SwiftData
import os

// MARK: - GoalConversionMigration
//
// One-time, idempotent "Convert & Retire" pass that bridges the legacy
// `PersistedGoal` model into the unified 1.3 habit engine.
//
// Data-safety contract (locked by product decision):
//   • `PersistedGoal` stays registered in the schema forever — we never run a
//     destructive migration that drops the model, so no live user data is lost.
//   • For each ACTIVE goal we mint a matching `PersistedHabit` (streak 0) and
//     flip the source goal to `.converted` so it drops out of the Milestones
//     list. The goal row itself is preserved in the store.
//
// Atomicity contract:
//   • All habits are inserted and all goal statuses flipped in a single loop,
//     followed by exactly ONE `context.save()` at the very end.
//   • The UserDefaults guard flag is only set AFTER that save returns. If the
//     save throws, the flag stays unset so the next launch retries the WHOLE
//     set cleanly — a mid-loop crash can never half-convert and duplicate
//     habits on the retry.
//
// Execution-context contract:
//   • `@MainActor` — must be handed the app's main-actor context
//     (`container.mainContext`), never a background/secondary context, to avoid
//     cross-thread SwiftData context-access violations.

@MainActor
enum GoalConversionMigration {

    private static let logger = Logger(subsystem: "com.remyavipindas.avenor", category: "migration.goalToHabit")

    /// UserDefaults guard. Versioned so a future re-conversion pass can use a
    /// fresh key without colliding with this one.
    private static let didConvertKey = "didConvertGoalsToHabits.v1"

    /// Converts every active `PersistedGoal` into a `PersistedHabit` exactly
    /// once. Idempotent (guarded by the flag) and fail-soft (never crashes
    /// launch; retries the full set on the next launch if the save throws).
    static func runIfNeeded(in context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didConvertKey) else { return }

        do {
            // Only active goals are migrated. Abandoned goals stay archived;
            // already-converted goals are skipped by the status filter.
            let descriptor = FetchDescriptor<PersistedGoal>()
            let activeGoals = try context.fetch(descriptor).filter { $0.status == .active }

            guard !activeGoals.isEmpty else {
                // Nothing to convert — still mark done so we never re-scan.
                defaults.set(true, forKey: didConvertKey)
                logger.info("No active goals to convert; migration marked complete.")
                return
            }

            // Phase 1 — stage all mutations in-memory (no save yet).
            for goal in activeGoals {
                let habit = PersistedHabit(
                    title: goal.title,
                    details: "Progress tracking for: \(goal.targetText)",
                    recurrence: .daily,
                    streakCount: 0
                )
                context.insert(habit)
                goal.status = .converted
            }

            // Phase 2 — single atomic save. Flip the flag only on success.
            try context.save()
            defaults.set(true, forKey: didConvertKey)
            logger.info("Converted \(activeGoals.count, privacy: .public) goal(s) to habits.")
        } catch {
            // Fail-soft: leave the flag unset so the next launch retries the
            // entire set. Never crash launch.
            logger.error("Goal→Habit conversion failed: \(error.localizedDescription, privacy: .public). Will retry next launch.")
        }
    }
}
