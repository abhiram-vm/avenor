import Foundation
import SwiftData
import SwiftUI

// MARK: - TaskMutator
//
// Single entry point for the three primary mutations on `PersistedTask`:
// complete, uncomplete, and hard-delete. Every page that touches a task
// (Tasks, Calendar, Overview, Archive) routes through here so the side
// effects — `completedAt` stamp, widget refresh, notification cancel —
// stay in lockstep.
//
// Pure structs: no state, no actor. Animation is the caller's concern;
// pass the desired Animation as `with:` to wrap the SwiftData write.

@MainActor
enum TaskMutator {

    static func complete(_ task: PersistedTask, in context: ModelContext, with animation: Animation? = nil) {
        let apply = {
            switch task.type {
            case .todo, .reminder:
                task.isDone = true
                task.completedAt = .now
            case .idea:
                task.ideaStatus = .completed
            }
            task.updatedAt = .now
        }
        if let animation { withAnimation(animation, apply) } else { apply() }

        // schedule() no-ops for completed tasks → effectively a cancel.
        NotificationManager.shared.schedule(for: task)
    }

    static func uncomplete(_ task: PersistedTask, in context: ModelContext, with animation: Animation? = nil) {
        let apply = {
            switch task.type {
            case .todo, .reminder:
                task.isDone = false
                task.completedAt = nil
            case .idea:
                task.ideaStatus = .thinking
            }
            task.updatedAt = .now
        }
        if let animation { withAnimation(animation, apply) } else { apply() }

        NotificationManager.shared.schedule(for: task)
    }

    static func delete(_ task: PersistedTask, in context: ModelContext, with animation: Animation? = nil) {
        NotificationManager.shared.cancel(for: task)
        let apply = { context.delete(task) }
        if let animation { withAnimation(animation, apply) } else { apply() }
    }

    /// Bump `updatedAt` to signal user interaction. The idea-decay logic
    /// reads this timestamp to decide whether a `.idea` row has gone stale
    /// (7-day cutoff). Routing every "the user looked at this" moment
    /// through here keeps the decay clock honest.
    static func markInteracted(_ task: PersistedTask) {
        task.updatedAt = .now
    }
}
