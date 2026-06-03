//
//  AppIntent.swift
//  AvenorWidget
//
//  Interactive widget intents. These run in the widget extension's process
//  on tap. Because the widget cannot safely open the main app's SwiftData
//  store (it lives in the app sandbox, not the App Group), each intent
//  journals the mutation into the App Group pending-action queue. The main
//  app drains + applies it on next foreground (`WidgetActionApplier`), then
//  republishes a fresh snapshot.
//
//  The widget UI updates OPTIMISTICALLY (the entry view reads an "applied"
//  overlay of pending actions) and the intent reloads its own timeline, so
//  the tap looks instant on the Home Screen without launching the app.
//
//  ⚠️ Haptics: `UIImpactFeedbackGenerator` / `AppHaptic.pop()` do NOT fire
//  from a widget AppIntent — there is no foreground UI session in the
//  extension process. The pop plays only when the equivalent action runs
//  inside the running app. This is an OS limitation, documented here so it
//  isn't mistaken for a bug.
//

import WidgetKit
import AppIntents

// MARK: - Complete Task

struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource { "Complete Task" }
    static var description: IntentDescription { "Marks a task done from the widget." }

    /// Keeps the tap from cold-launching the app — the whole point of the
    /// pending-action queue is a friction-free, in-place mutation.
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Task ID")
    var taskID: String

    init() {}
    init(taskID: UUID) { self.taskID = taskID.uuidString }

    func perform() async throws -> some IntentResult {
        if let uuid = UUID(uuidString: taskID) {
            WidgetActionQueue.enqueue(
                WidgetPendingAction(kind: .completeTask, targetID: uuid)
            )
        }
        // Reload only the interactive widget — the legacy date/time widget
        // is unaffected by a task completion.
        WidgetCenter.shared.reloadTimelines(ofKind: "AvenorTasksWidget")
        return .result()
    }
}

// MARK: - Toggle Habit Loop

struct ToggleHabitIntent: AppIntent {
    static var title: LocalizedStringResource { "Toggle Routine" }
    static var description: IntentDescription { "Logs or un-logs a routine for today from the widget." }

    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Habit ID")
    var habitID: String

    init() {}
    init(habitID: UUID) { self.habitID = habitID.uuidString }

    func perform() async throws -> some IntentResult {
        if let uuid = UUID(uuidString: habitID) {
            WidgetActionQueue.enqueue(
                WidgetPendingAction(kind: .toggleHabit, targetID: uuid)
            )
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "AvenorTasksWidget")
        return .result()
    }
}

// MARK: - Legacy template intent (unused, retained for the scaffolded
// configuration widget so the target keeps compiling).

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Configuration" }
    static var description: IntentDescription { "This is an example widget." }

    @Parameter(title: "Favorite Emoji", default: "😃")
    var favoriteEmoji: String
}
