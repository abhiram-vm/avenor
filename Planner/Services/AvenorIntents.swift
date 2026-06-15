import AppIntents
import Foundation
import SwiftData

// MARK: - AvenorIntents
//
// App Intents layer — exposes Avenor's core actions to Siri, Spotlight,
// the Shortcuts app, and the Action Button. Lives in the MAIN app target
// (not an extension): the system launches the app process in the
// background to run these, so we get the real CaptureParser, service
// layer, and SwiftData store for free.
//
// Contract (mirrors the service layer's discipline):
//   • Every `perform()` is @MainActor — TaskMutator, NotificationManager,
//     and WidgetSnapshotPublisher are all main-actor isolated.
//   • Mutating intents open the SAME default SwiftData store as
//     `PlannerApp` (identical schema, default ModelConfiguration) via the
//     cached `IntentModelStore` container.
//   • `openAppWhenRun = false` everywhere — intents work entirely in the
//     background and answer through dialog.
//   • Fail-soft: every error path returns an explanatory dialog. An
//     intent must never crash or throw raw errors at Siri.

// MARK: - Shared model container

@MainActor
enum IntentModelStore {

    private static var cached: ModelContainer?

    /// Same schema + default configuration as `PlannerApp`'s
    /// `.modelContainer(for:)`, so both point at the same on-disk store.
    /// Cached so repeated intent invocations don't re-open the store.
    static func container() throws -> ModelContainer {
        if let cached { return cached }
        let container = try ModelContainer(for:
            PersistedTask.self,
            PersistedNote.self,
            PersistedGoal.self,
            PersistedHabit.self
        )
        cached = container
        return container
    }
}

// MARK: - Shared helpers

@MainActor
private enum IntentSupport {

    static let storeUnavailableDialog: IntentDialog =
        "Avenor couldn't open its data store. Open the app once and try again."

    /// Re-materialize the widget snapshots after a task mutation so the
    /// Home Screen reflects the Siri-side change without opening the app.
    static func refreshTaskWidgets(in context: ModelContext) {
        let tasks = (try? context.fetch(FetchDescriptor<PersistedTask>())) ?? []
        WidgetSnapshotPublisher.publishToday(tasks: tasks)
        WidgetSnapshotPublisher.publishTasks(tasks)
    }

    static func refreshRoutineWidgets(in context: ModelContext) {
        let habits = (try? context.fetch(FetchDescriptor<PersistedHabit>())) ?? []
        WidgetSnapshotPublisher.publishRoutine(habits)
    }
}

// MARK: - Donations
//
// Lightweight signal to the system that capture is a high-frequency action,
// so Siri Suggestions / Spotlight rank the shortcut higher. Fire-and-forget;
// a donation failure is never user-visible.

@MainActor
enum IntentDonations {
    static func donateAddTask() {
        Task { try? await IntentDonationManager.shared.donate(intent: AddTaskIntent()) }
    }
}

// MARK: - AddTaskIntent

struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Task to Avenor"
    static var description = IntentDescription(
        "Capture a task, note, or idea in Avenor using natural language."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Input",
        description: "What you want to capture. Try 'call mom 5pm' or 'big idea #design'"
    )
    var input: String

    static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$input)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let intent = CaptureParser.parse(input) else {
            return .result(dialog: "I didn't catch anything to capture. Try something like 'call mom @5pm'.")
        }

        guard let container = try? IntentModelStore.container() else {
            return .result(dialog: IntentSupport.storeUnavailableDialog)
        }
        let context = container.mainContext

        // Mirror of OverviewTabView.commitCapture, minus animation and the
        // Live Activity hook (countdowns can't start from the background).
        let savedTitle: String
        switch intent {
        case .todo(let title, let dueDate, let priority):
            let task = PersistedTask(title: title, type: .todo, dueDate: dueDate, priority: priority)
            context.insert(task)
            NotificationManager.shared.schedule(for: task)
            savedTitle = title

        case .reminder(let title, let dueDate, let priority):
            let task = PersistedTask(title: title, type: .reminder, dueDate: dueDate, priority: priority)
            context.insert(task)
            NotificationManager.shared.schedule(for: task)
            savedTitle = title

        case .idea(let title, let tag, let priority):
            let task = PersistedTask(
                title: title,
                type: .idea,
                ideaStatus: .thinking,
                ideaTag: tag.isEmpty ? nil : tag,
                priority: priority
            )
            context.insert(task)
            savedTitle = title

        case .note(let title, let body):
            let note = PersistedNote(title: title, details: body, lastEditedAt: .now)
            context.insert(note)
            savedTitle = title

        case .habit(let title, let rule, let anchor, let tag, let priority):
            let habit = PersistedHabit(
                title: title,
                recurrence: rule,
                anchorDate: anchor,
                tag: tag,
                priority: priority
            )
            context.insert(habit)
            savedTitle = title
        }

        do {
            try context.save()
        } catch {
            return .result(dialog: "Avenor couldn't save that. Open the app and try again.")
        }

        if case .habit = intent {
            IntentSupport.refreshRoutineWidgets(in: context)
        } else {
            IntentSupport.refreshTaskWidgets(in: context)
        }
        IntentDonations.donateAddTask()

        return .result(dialog: "Added: \(savedTitle)")
    }
}

// MARK: - GetTodaysTasksIntent

struct GetTodaysTasksIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Today's Tasks from Avenor"
    static var description = IntentDescription(
        "Returns a list of tasks due today in Avenor."
    )
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<[String]> {
        // Primary source: the App Group widget payload — no model context
        // needed. The payload carries the top 3 items + the full count.
        let payload = WidgetSnapshotIO.readToday()

        var titles = payload.items.map(\.title)
        var total = max(payload.totalDueToday, titles.count)

        // The payload is a snapshot; if it predates today the list is
        // stale (yesterday's tasks). Recompute from the store in that case.
        if !Calendar.autoupdatingCurrent.isDateInToday(payload.generatedAt),
           let container = try? IntentModelStore.container() {
            let calendar = Calendar.autoupdatingCurrent
            let tasks = (try? container.mainContext.fetch(FetchDescriptor<PersistedTask>())) ?? []
            let dueToday = tasks
                .filter { t in
                    (t.type == .todo || t.type == .reminder)
                        && !(t.isDone ?? false)
                        && t.dueDate.map { calendar.isDateInToday($0) } == true
                }
                .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            titles = dueToday.map(\.title)
            total = dueToday.count
        }

        guard !titles.isEmpty else {
            return .result(value: [], dialog: "Nothing due today. You're clear.")
        }

        let list = titles.joined(separator: ", ")
        let overflow = total - titles.count
        let suffix = overflow > 0 ? ", and \(overflow) more" : ""
        let noun = total == 1 ? "task" : "tasks"
        return .result(
            value: titles,
            dialog: "You have \(total) \(noun) due today: \(list)\(suffix)."
        )
    }
}

// MARK: - CompleteTaskIntent

struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete a Task in Avenor"
    static var description = IntentDescription(
        "Marks a matching open task as done in Avenor."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Task Name")
    var taskName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Complete \(\.$taskName)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let container = try? IntentModelStore.container() else {
            return .result(dialog: IntentSupport.storeUnavailableDialog)
        }
        let context = container.mainContext
        let tasks = (try? context.fetch(FetchDescriptor<PersistedTask>())) ?? []

        // Open tasks only — done todos/reminders and shipped ideas are out.
        let open = tasks.filter { task in
            switch task.type {
            case .todo, .reminder: return !(task.isDone ?? false)
            case .idea:            return task.ideaStatus != .completed
            }
        }

        // Fuzzy match: lowercased contains. An exact title match wins
        // outright so "gym" can complete "Gym" even when "Gym laundry"
        // also exists.
        let needle = taskName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = open.filter { $0.title.lowercased().contains(needle) }
        let exact = matches.filter { $0.title.lowercased() == needle }

        let target: PersistedTask
        switch (exact.count, matches.count) {
        case (1, _):
            target = exact[0]
        case (_, 1):
            target = matches[0]
        case (_, 0):
            return .result(dialog: "No task found matching '\(taskName)'.")
        default:
            let names = matches.prefix(4).map(\.title).joined(separator: ", ")
            return .result(dialog: "I found \(matches.count) tasks matching '\(taskName)': \(names). Try a more specific name.")
        }

        TaskMutator.complete(target, in: context)
        do {
            try context.save()
        } catch {
            return .result(dialog: "Avenor couldn't save that change. Open the app and try again.")
        }
        IntentSupport.refreshTaskWidgets(in: context)
        IntentDonations.donateAddTask()

        return .result(dialog: "Marked '\(target.title)' as done.")
    }
}

// MARK: - CheckGoalProgressIntent

struct CheckGoalProgressIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Goal Progress in Avenor"
    static var description = IntentDescription(
        "Reads back progress on your active Avenor goals."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Goal Name",
        description: "Leave blank to get all active goals"
    )
    var goalName: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Check progress of \(\.$goalName)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let container = try? IntentModelStore.container() else {
            return .result(dialog: IntentSupport.storeUnavailableDialog)
        }
        let goals = ((try? container.mainContext.fetch(FetchDescriptor<PersistedGoal>())) ?? [])
            .filter { $0.status == .active }
            .sorted { $0.sortOrder < $1.sortOrder }

        guard !goals.isEmpty else {
            return .result(dialog: "You have no active goals right now.")
        }

        func line(_ g: PersistedGoal) -> String {
            "\(g.title): \(g.currentText) of \(g.targetText). \(g.percentText) complete."
        }

        guard let name = goalName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return .result(dialog: "\(goals.map(line).joined(separator: " "))")
        }

        let needle = name.lowercased()
        let matches = goals.filter { $0.title.lowercased().contains(needle) }
        guard let goal = matches.first else {
            return .result(dialog: "No active goal found matching '\(name)'.")
        }
        return .result(dialog: "\(line(goal))")
    }
}

// MARK: - CaptureNoteIntent

struct CaptureNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Note to Avenor"
    static var description = IntentDescription(
        "Saves a note with a title and optional body to Avenor."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Title")
    var noteTitle: String

    @Parameter(title: "Body", description: "Optional note content")
    var noteBody: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add note \(\.$noteTitle)") {
            \.$noteBody
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let container = try? IntentModelStore.container() else {
            return .result(dialog: IntentSupport.storeUnavailableDialog)
        }
        let context = container.mainContext
        let note = PersistedNote(title: noteTitle, details: noteBody ?? "", lastEditedAt: .now)
        context.insert(note)
        do {
            try context.save()
        } catch {
            return .result(dialog: "Avenor couldn't save the note. Open the app and try again.")
        }
        return .result(dialog: "Note '\(noteTitle)' saved to Avenor.")
    }
}
