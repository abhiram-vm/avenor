import AppIntents

// MARK: - AvenorShortcuts
//
// AppShortcutsProvider — registers the zero-setup phrases that surface in
// Siri, Spotlight, and the Shortcuts app the moment the app is installed.
// Every phrase MUST embed `.applicationName` ("Avenor") or the system
// rejects it at build time.

struct AvenorShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add \(.applicationName) task",
                "Capture in \(.applicationName)",
                "Add to \(.applicationName)",
                "New \(.applicationName) task"
            ],
            shortTitle: "Capture in Avenor",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: GetTodaysTasksIntent(),
            phrases: [
                "What's on my \(.applicationName) list today",
                "Show my \(.applicationName) tasks",
                "What do I have in \(.applicationName) today"
            ],
            shortTitle: "Today's Tasks",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: CompleteTaskIntent(),
            phrases: [
                "Complete \(.applicationName) task",
                "Mark done in \(.applicationName)"
            ],
            shortTitle: "Complete Task",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: CheckGoalProgressIntent(),
            phrases: [
                "Check my \(.applicationName) goals",
                "How are my \(.applicationName) goals"
            ],
            shortTitle: "Goal Progress",
            systemImageName: "target"
        )
        AppShortcut(
            intent: CaptureNoteIntent(),
            phrases: [
                "Add \(.applicationName) note",
                "Save note to \(.applicationName)"
            ],
            shortTitle: "Add Note",
            systemImageName: "note.text"
        )
    }
}
