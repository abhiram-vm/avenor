import SwiftUI
import SwiftData

// MARK: - Mac_TasksPane
//
// Every actionable task, sorted by `sortOrder` (negative epoch-millis,
// ascending → newest first). The leading checkbox and the right-click context
// menu both route through the shared `TaskMutator` service — views never
// mutate SwiftData directly. Right-click exposes complete / edit / delete
// (the macOS equivalent of the iOS StarkSwipeRow actions).

struct Mac_TasksPane: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(Mac_NavState.self) private var nav
    @Query(sort: \PersistedTask.sortOrder, order: .forward) private var tasks: [PersistedTask]

    @State private var editingTask: PersistedTask?
    /// Task id currently flashing a mint ring after a cross-pane navigation.
    @State private var flashID: UUID?

    var body: some View {
        let p = theme.palette
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if tasks.isEmpty {
                        StarkEmptyState("Empty.", footnote: "Press ⌘N to capture your first item.")
                    } else {
                        ForEach(tasks) { task in
                            Mac_TaskRow(
                                task: task,
                                onToggleComplete: { toggle(task, isDone: task.isDone ?? false) },
                                onEdit: { editingTask = task },
                                onDelete: {
                                    TaskMutator.delete(task, in: modelContext)
                                    try? modelContext.save()
                                },
                                highlighted: flashID == task.id
                            )
                            .id(task.id)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: nav.pendingFocus) { _, target in
                guard case .task(let id)? = target else { return }
                reveal(id, proxy: proxy)
            }
            .onAppear {
                if case .task(let id)? = nav.pendingFocus { reveal(id, proxy: proxy) }
            }
        }
        .themedCanvas(p)
        .navigationTitle("Tasks")
        .sheet(item: $editingTask) { task in
            Mac_EditTaskSheet(task: task)
        }
    }

    /// Scroll the requested task into view, flash its ring, then clear the
    /// nav token so the same target can be requested again later.
    private func reveal(_ id: UUID, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
        flashID = id
        nav.pendingFocus = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if flashID == id { withAnimation(.easeInOut(duration: 0.2)) { flashID = nil } }
        }
    }

    private func toggle(_ task: PersistedTask, isDone: Bool) {
        if isDone {
            TaskMutator.uncomplete(task, in: modelContext)
        } else {
            TaskMutator.complete(task, in: modelContext)
        }
    }
}

// MARK: - Mac_EditTaskSheet
//
// Minimal Mac edit form for a single task: rename plus an optional due date.
// Local state is applied only on Save, so Cancel is non-destructive. Saving
// re-runs notification scheduling so a changed deadline stays in sync.

struct Mac_EditTaskSheet: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let task: PersistedTask

    @State private var title: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date

    init(task: PersistedTask) {
        self.task = task
        _title = State(initialValue: task.title)
        _hasDueDate = State(initialValue: task.dueDate != nil)
        _dueDate = State(initialValue: task.dueDate ?? .now)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit Task")
                .font(p.font(.title))
                .foregroundStyle(p.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text("TITLE")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(p.textSecondary)
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(p.font(.body))
                    .foregroundStyle(p.textPrimary)
                    .tint(Mac_Accent.mint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous).fill(p.rowFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                            .strokeBorder(p.hairline)
                    )
            }

            Toggle(isOn: $hasDueDate.animation(.easeInOut(duration: 0.15))) {
                Text("Due date")
                    .font(p.font(.body))
                    .foregroundStyle(p.textPrimary)
            }
            .tint(Mac_Accent.mint)

            if hasDueDate {
                DatePicker("", selection: $dueDate)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }

            HStack(spacing: 12) {
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedTitle.isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 420)
        .themedCanvas(p)
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        task.title = trimmedTitle
        task.dueDate = hasDueDate ? dueDate : nil
        task.updatedAt = .now
        // schedule() is idempotent and re-anchors the notification to the new
        // deadline (or cancels it when the date is cleared / already past).
        NotificationManager.shared.schedule(for: task)
        try? modelContext.save()
        dismiss()
    }
}
