import Foundation
import SwiftData
import SwiftUI

// MARK: - GoalMutator
//
// Mirror of `TaskMutator`. Every mutation that touches a `PersistedGoal`
// (increment from swipe, scrub, abandon, restore, delete) flows through
// here so widget snapshot publishing, last-updated stamps, and lifecycle
// transitions stay consistent across the app.

@MainActor
enum GoalMutator {

    /// Numerical step used by both the Apple-Music-style swipe-through and
    /// the scrub wheel. Decimal-allowing units increment by 0.1 to feel
    /// continuous; integer units bump by 1.
    static func step(for goal: PersistedGoal) -> Double {
        goal.unit.allowsDecimals ? 0.1 : 1
    }

    /// Single-shot increment used by the swipe-through. Caps at target,
    /// no-ops when already at target so the swipe gesture can be re-armed
    /// without overshoot. Returns whether a mutation actually happened —
    /// callers use this to suppress the "+1 logged" haptic at the ceiling.
    @discardableResult
    static func increment(_ goal: PersistedGoal, with animation: Animation? = nil) -> Bool {
        guard goal.currentValue < goal.targetValue else { return false }
        let next = min(goal.targetValue, goal.currentValue + step(for: goal))
        let apply = {
            goal.currentValue = next
            goal.lastUpdatedAt = .now
        }
        if let animation { withAnimation(animation, apply) } else { apply() }
        return true
    }

    /// Direct value assignment used by the scrub-wheel gesture. Clamps to
    /// `[0, targetValue]`. The scrub controller fires this once per integer
    /// crossing so the underlying property only flips when the user has
    /// actually moved a whole step.
    static func setValue(_ goal: PersistedGoal, to raw: Double) {
        let clamped = max(0, min(goal.targetValue, raw))
        guard clamped != goal.currentValue else { return }
        goal.currentValue = clamped
        goal.lastUpdatedAt = .now
    }

    /// Soft retire. The goal leaves the active workspace but its history
    /// survives — abandoned goals re-surface in the Goals archive drawer.
    static func abandon(_ goal: PersistedGoal, with animation: Animation? = nil) {
        let apply = {
            goal.status = .abandoned
            goal.abandonedAt = .now
        }
        if let animation { withAnimation(animation, apply) } else { apply() }
    }

    /// Inverse of `abandon`. Surfaces the goal back in the active list.
    static func restore(_ goal: PersistedGoal, with animation: Animation? = nil) {
        let apply = {
            goal.status = .active
            goal.abandonedAt = nil
        }
        if let animation { withAnimation(animation, apply) } else { apply() }
    }

    /// Hard delete from SwiftData. Only the archive view exposes this — the
    /// active workspace soft-retires through `abandon` instead.
    static func delete(_ goal: PersistedGoal, in context: ModelContext, with animation: Animation? = nil) {
        let apply = { context.delete(goal) }
        if let animation { withAnimation(animation, apply) } else { apply() }
    }
}
