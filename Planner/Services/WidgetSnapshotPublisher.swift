import Foundation
import WidgetKit
import os

// MARK: - WidgetSnapshotPublisher
//
// Bridges SwiftData into the App Group payload that the widget extension
// reads. Call `publish(tasks:goals:)` whenever the underlying data changes
// (insert, complete, delete, deadline edit, goal increment).
//
// The publisher only writes a payload when the materialized snapshot is
// different from the previously written one — silent reloads cost battery
// on the user's lock screen.

@MainActor
enum WidgetSnapshotPublisher {

    private static let logger = Logger(subsystem: "com.remyavipindas.avenor", category: "widget")

    // MARK: Public entry points

    /// Kind string of the unified widget — keep in lockstep with
    /// `AvenorWidget.kind` in the extension target.
    private static let widgetKind = "AvenorWidget"

    /// Refreshes today payload only. Use from the Tasks page.
    static func publishToday(tasks: [PersistedTask]) {
        let today = makeTodayPayload(from: tasks)
        WidgetSnapshotIO.writeToday(today)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        logger.debug("Published today snapshot — \(today.totalDueToday, privacy: .public) item(s).")
    }

    /// Refreshes goals payload only. Use from the Goals page.
    static func publishGoals(_ goals: [PersistedGoal]) {
        let payload = makeGoalsPayload(from: goals)
        WidgetSnapshotIO.writeGoals(payload)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        logger.debug("Published goals snapshot — \(payload.goals.count, privacy: .public) goal(s).")
    }

    /// Kind string of the interactive task/routine widget — keep in lockstep
    /// with `AvenorTasksWidget.kind` in the extension target.
    private static let tasksWidgetKind = "AvenorTasksWidget"

    /// Refreshes the routine (habit) payload. Call from the Progress page
    /// whenever habits change (create / toggle / archive). Reloads BOTH the
    /// legacy widget and the interactive task/routine widget so the medium
    /// family's habit column stays live.
    static func publishRoutine(_ habits: [PersistedHabit]) {
        let payload = makeRoutinePayload(from: habits)
        WidgetSnapshotIO.writeRoutine(payload)
        WidgetCenter.shared.reloadTimelines(ofKind: tasksWidgetKind)
        logger.debug("Published routine snapshot — \(payload.habits.count, privacy: .public) loop(s).")
    }

    /// Convenience: refresh the interactive widget's task column too. Use
    /// alongside `publishToday` from any task-mutating surface.
    static func publishTasks(_ tasks: [PersistedTask]) {
        let today = makeTodayPayload(from: tasks)
        WidgetSnapshotIO.writeToday(today)
        WidgetCenter.shared.reloadTimelines(ofKind: tasksWidgetKind)
    }

    // MARK: Today

    private static func makeTodayPayload(from tasks: [PersistedTask]) -> TodayWidgetPayload {
        let calendar = Calendar.autoupdatingCurrent
        let today = Date.now

        let dueToday = tasks
            .filter { t in
                guard t.type == .todo || t.type == .reminder else { return false }
                guard !(t.isDone ?? false) else { return false }
                guard let due = t.dueDate else { return false }
                return calendar.isDate(due, inSameDayAs: today)
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

        let items = dueToday.prefix(3).map { t in
            TodayWidgetItem(
                id: t.id,
                title: t.title,
                typeRaw: t.type.rawValue,
                dueDate: t.dueDate,
                ideaTag: t.ideaTag
            )
        }

        return TodayWidgetPayload(items: Array(items), totalDueToday: dueToday.count)
    }

    // MARK: Goals

    private static func makeGoalsPayload(from goals: [PersistedGoal]) -> GoalsWidgetPayload {
        // First non-completed goal, falling back to first goal if all are done.
        let chosen = goals.first(where: { !$0.isCompleted }) ?? goals.first

        guard let g = chosen else {
            return GoalsWidgetPayload(goals: [])
        }

        let item = GoalWidgetItem(
            id: g.id,
            title: g.title,
            subtitle: g.subtitle,
            currentValueText: g.currentText,
            targetValueText: g.targetText,
            progress: g.progress,
            tintHex: g.tintHex
        )
        return GoalsWidgetPayload(goals: [item])
    }

    // MARK: Routine

    private static func makeRoutinePayload(from habits: [PersistedHabit]) -> RoutineWidgetPayload {
        let calendar = Calendar.autoupdatingCurrent
        let active = habits
            .filter { !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
            .prefix(4)

        let items = active.map { h in
            HabitWidgetItem(
                id: h.id,
                title: h.title,
                cadenceLabel: h.cadenceLabel,
                streakCount: h.streakCount,
                isCompletedToday: h.isCompletedToday(calendar: calendar),
                tintHex: "#FFFFFFFF"
            )
        }
        return RoutineWidgetPayload(habits: Array(items))
    }
}
