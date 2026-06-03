import Foundation
import SwiftData
import os

// MARK: - WidgetActionApplier
//
// Drains the App Group pending-action queue (taps performed from the
// interactive Home Screen widget) and applies each mutation to the live
// SwiftData store. The widget process can't safely open the app's store, so
// it journals taps via `WidgetActionQueue.enqueue`; this runs in the main
// app on every foreground transition (see `PlannerApp.onScenePhaseChange`).
//
// After applying, it republishes fresh widget snapshots so the optimistic
// overlay the widget rendered is replaced by authoritative state.

@MainActor
enum WidgetActionApplier {

    private static let logger = Logger(subsystem: "com.remyavipindas.avenor", category: "widget")

    /// Drains every queued action and applies it. No-ops cheaply when the
    /// queue is empty so it's safe to call on every foreground.
    ///
    /// Thread safety: the whole type is `@MainActor`, and the `context`
    /// passed in is always the SwiftUI-injected main `ModelContext`. Every
    /// fetch / mutate / save therefore runs on the main actor — there is no
    /// cross-thread access of a `ModelContext`, so a SwiftData threading
    /// violation cannot occur here.
    static func drainAndApply(in context: ModelContext) {
        // `drainAll()` reads + clears atomically and returns `[]` on a
        // missing / corrupt / undecodable payload (see `WidgetActionQueue`),
        // so a malformed App Group blob degrades to a clean no-op rather than
        // a crash. Spam-tapping Flush just races to empty: the first call
        // drains, every subsequent call sees an empty queue.
        let actions = WidgetActionQueue.drainAll()
        guard !actions.isEmpty else { return }

        // Collapse duplicate taps by (kind + target). Order-preserving. This
        // makes a double-enqueue idempotent: without it, two `.toggleHabit`
        // entries for the same loop would toggle then un-toggle, silently
        // cancelling the user's action.
        var seen = Set<String>()
        let uniqueActions = actions.filter { action in
            seen.insert("\(action.kind.rawValue):\(action.targetID.uuidString)").inserted
        }

        var didMutate = false
        for action in uniqueActions {
            switch action.kind {
            case .completeTask:
                if applyCompleteTask(action.targetID, in: context) { didMutate = true }
            case .toggleHabit:
                if applyToggleHabit(action.targetID, in: context) { didMutate = true }
            }
        }

        guard didMutate else { return }
        do {
            try context.save()
            republish(in: context)
            logger.debug("Applied \(uniqueActions.count, privacy: .public) widget action(s).")
        } catch {
            // Never crash the host app on a save failure — the worst case is
            // the optimistic widget overlay reconciles on the next publish.
            logger.error("Widget action save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Mutations

    private static func applyCompleteTask(_ id: UUID, in context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<PersistedTask>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let task = try? context.fetch(descriptor).first else { return false }
        guard !(task.isDone ?? false) else { return false }
        task.isDone = true
        task.completedAt = .now
        task.updatedAt = .now
        return true
    }

    private static func applyToggleHabit(_ id: UUID, in context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<PersistedHabit>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let habit = try? context.fetch(descriptor).first else { return false }
        habit.toggleToday()
        return true
    }

    // MARK: Republish

    /// Re-materializes the today + routine snapshots from the post-mutation
    /// store and reloads the interactive widget's timeline.
    private static func republish(in context: ModelContext) {
        if let tasks = try? context.fetch(FetchDescriptor<PersistedTask>()) {
            WidgetSnapshotPublisher.publishTasks(tasks)
        }
        if let habits = try? context.fetch(FetchDescriptor<PersistedHabit>()) {
            WidgetSnapshotPublisher.publishRoutine(habits)
        }
    }
}
