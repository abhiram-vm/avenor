import SwiftUI
import SwiftData

// MARK: - TasksTabView (Sophisticated Stark)
//
// Pattern: `ScrollView + LazyVStack + StarkSwipeRow`. No `List`.
// Custom swipe overlay paints near-black with pure-white glyphs.

struct TasksTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeStore.self) private var theme

    @Query(sort: \PersistedTask.sortOrder) private var tasks: [PersistedTask]

    @State private var selectedFilter: TaskType? = nil
    @State private var expandedTaskID: UUID? = nil
    @State private var showingNewItemSheet = false
    @State private var showingArchive = false
    @State private var draftType: TaskType = .todo
    @State private var searchText: String = ""

    private let spring = Animation.spring(response: 0.35, dampingFraction: 0.7)
    /// Tighter spring for the active→archive transition. Crisp enough that
    /// the completed row feels punted off the list rather than fading away.
    private let exitSpring = Animation.spring(duration: 0.25)

    var body: some View {
        let p = theme.palette
        NavigationStack {
            ZStack {
                canvasLayer(p)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        TodayHeader(tasks: tasks)
                            .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                            .padding(.top, DesignTokens.Spacing.pageTop)
                            .padding(.bottom, DesignTokens.Spacing.stackLarge)

                        filterRow
                            .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                            .padding(.bottom, 12)

                        if filteredTasks.isEmpty {
                            emptyState
                                .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                                .padding(.top, 24)
                                .padding(.bottom, DesignTokens.Spacing.pageBottom)
                        } else {
                            rowSeparator
                            ForEach(liveTasks) { task in
                                taskSwipeRow(for: task)
                                rowSeparator
                            }

                            if !marinatingIdeas.isEmpty {
                                marinatingHeader
                                rowSeparator
                                ForEach(marinatingIdeas) { task in
                                    taskSwipeRow(for: task)
                                    rowSeparator
                                }
                            }

                            Spacer(minLength: DesignTokens.Spacing.pageBottom)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                // Exit animation: 0.25s spring when a row drops out (complete/delete).
                .animation(exitSpring, value: filteredTasks.map(\.id))
                .animation(spring, value: expandedTaskID)
            }
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { archiveButton }
                ToolbarItem(placement: .topBarTrailing) { plusButton }
            }
            .sheet(isPresented: $showingArchive) {
                ArchiveTaskListView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(p.sheetBackground)
                    .presentationCornerRadius(DesignTokens.Radius.sheet)
            }
            .sheet(isPresented: $showingNewItemSheet) {
                NewItemSheet(initialType: draftType) { draft in
                    insert(from: draft)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(p.id == .liquidGlass ? AnyShapeStyle(.clear) : AnyShapeStyle(p.sheetBackground))
                .presentationCornerRadius(DesignTokens.Radius.sheet)
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search tasks"
        )
        .onChange(of: tasks.map(\.id)) { _, _ in
            WidgetSnapshotPublisher.publishToday(tasks: tasks)
        }
        .onChange(of: tasks.map { $0.dueDate ?? .distantPast }) { _, _ in
            WidgetSnapshotPublisher.publishToday(tasks: tasks)
        }
        .onAppear {
            WidgetSnapshotPublisher.publishToday(tasks: tasks)
        }
    }

    // MARK: Row builder + sub-section split
    //
    // `liveTasks` keeps the page reading as fresh; `marinatingIdeas` are
    // stale `.idea` rows (7+ days untouched) shuffled to a demoted bottom
    // sub-section so they don't disappear but also don't claim primacy.

    @ViewBuilder
    private func taskSwipeRow(for task: PersistedTask) -> some View {
        StarkSwipeRow(
            leading: StarkSwipeAction(
                systemImage: "checkmark",
                label: completionLabel(for: task),
                perform: { complete(task) }
            ),
            trailing: StarkSwipeAction(
                systemImage: "trash",
                label: "Delete",
                perform: { delete(task) }
            )
        ) {
            TaskRow(
                task: task,
                isExpanded: expandedTaskID == task.id,
                onToggleExpanded: { toggleExpanded(task) },
                onDelete: { delete(task) }
            )
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity
        ))
    }

    // MARK: Canvas layer (palette-aware)

    @ViewBuilder
    private func canvasLayer(_ p: ThemePalette) -> some View {
        switch p.canvas {
        case .solid(let c):
            c.ignoresSafeArea()
        case .gradient(let stops, let start, let end):
            LinearGradient(stops: stops, startPoint: start, endPoint: end)
                .ignoresSafeArea()
        }
    }

    /// Tracked uppercase divider that announces the marinating sub-section.
    /// Reads as a quiet structural note rather than a feature header — it
    /// shouldn't pull the eye away from the live work.
    private var marinatingHeader: some View {
        let p = theme.palette
        return HStack(spacing: 0) {
            Text("Marinating")
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .foregroundStyle(p.textSecondary)

            Text("·")
                .font(p.font(.micro))
                .foregroundStyle(p.textTertiary)
                .padding(.horizontal, 8)

            Text("\(marinatingIdeas.count)")
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .monospacedDigit()
                .foregroundStyle(p.textTertiary)

            Spacer(minLength: 0)

            Text("Untouched 7d+")
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .foregroundStyle(p.textTertiary)
        }
        .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
        .padding(.top, DesignTokens.Spacing.stackLarge)
        .padding(.bottom, 12)
    }

    // MARK: Row separator (between rows)

    private var rowSeparator: some View {
        Rectangle()
            .fill(theme.palette.hairline)
            .frame(height: 0.5)
    }

    // MARK: Archive button — tracked uppercase pill, hairline border

    private var archiveButton: some View {
        let p = theme.palette
        return Button {
            showingArchive = true
            AppHaptic.tap()
        } label: {
            Text("Archive")
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .foregroundStyle(p.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(p.chromeSurface))
                .overlay(Capsule().strokeBorder(p.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Archive")
    }

    // MARK: Plus button

    private var plusButton: some View {
        let p = theme.palette
        return Button {
            draftType = .todo
            showingNewItemSheet = true
            AppHaptic.tap()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(p.textPrimary)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(p.chromeSurface)
                )
                .overlay(
                    Circle().strokeBorder(p.prominent, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Filter row

    private var filterRow: some View {
        let p = theme.palette
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your list")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(p.textSecondary)

                Text("\(filteredTasks.count) item\(filteredTasks.count == 1 ? "" : "s")")
                    .font(p.font(.caption))
                    .foregroundStyle(p.textSecondary)
                    .monospacedDigit()
            }

            Spacer()

            Menu {
                Button("All") { selectedFilter = nil }
                Divider()
                ForEach(TaskType.allCases) { type in
                    Button(type.displayName) { selectedFilter = type }
                }
            } label: {
                HStack(spacing: 6) {
                    Text((selectedFilter?.displayName ?? "Filter"))
                        .font(p.font(.micro))
                        .tracking(p.microTracking)
                        .textCase(.uppercase)
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(p.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(p.chromeSurface)
                )
                .overlay(
                    Capsule().strokeBorder(p.hairline, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        StarkEmptyState(
            tasks.isEmpty ? "Empty." : "No matches.",
            footnote: tasks.isEmpty ? "Tap + to capture your first item." : "Try a different filter or search."
        )
    }

    // MARK: Filtering / mutation

    /// Active workspace: hides everything the user already finished.
    ///   • Todos / reminders → `isDone != true`
    ///   • Ideas             → `ideaStatus != .completed`
    private var filteredTasks: [PersistedTask] {
        let active = tasks.filter { t in
            switch t.type {
            case .todo, .reminder: return (t.isDone ?? false) == false
            case .idea:            return (t.ideaStatus ?? .thinking) != .completed
            }
        }
        let typed: [PersistedTask]
        if let selectedFilter {
            typed = active.filter { $0.type == selectedFilter }
        } else {
            typed = active
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return typed }
        return typed.filter { t in
            t.title.localizedCaseInsensitiveContains(q) ||
            t.details.localizedCaseInsensitiveContains(q) ||
            (t.ideaTag?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    /// Fresh items only: anything that isn't a stale `.idea`. Preserves
    /// the order returned by `filteredTasks` (which respects sortOrder).
    private var liveTasks: [PersistedTask] {
        filteredTasks.filter { !LifecycleAutomation.isIdeaStale($0) }
    }

    /// Stale ideas sorted oldest-first so the deepest-in-marination floats
    /// to the very bottom of the page. `LifecycleAutomation.isIdeaStale`
    /// guarantees these are `.idea` rows that haven't been touched in 7+
    /// days and aren't completed.
    private var marinatingIdeas: [PersistedTask] {
        filteredTasks
            .filter { LifecycleAutomation.isIdeaStale($0) }
            .sorted { $0.updatedAt < $1.updatedAt }
    }

    private func toggleExpanded(_ task: PersistedTask) {
        withAnimation(spring) {
            expandedTaskID = (expandedTaskID == task.id) ? nil : task.id
        }
        // Expanding an idea counts as an interaction — keeps the row out
        // of the marinating bucket while the user is actively reading it.
        if task.type == .idea {
            TaskMutator.markInteracted(task)
        }
        AppHaptic.tap()
    }

    private func delete(_ task: PersistedTask) {
        if expandedTaskID == task.id { expandedTaskID = nil }
        TaskMutator.delete(task, in: modelContext, with: spring)
    }

    private func complete(_ task: PersistedTask) {
        // Tight crisp spring so the row punts out of the active list cleanly.
        TaskMutator.complete(task, in: modelContext, with: exitSpring)
    }

    private func completionLabel(for task: PersistedTask) -> String {
        switch task.type {
        case .todo: return "Done"
        case .reminder: return "Ack"
        case .idea: return "Shipped"
        }
    }

    private func insert(from draft: NewTaskDraft) {
        let task = PersistedTask(
            title: draft.title,
            details: draft.details,
            type: draft.type,
            isDone: draft.isDone,
            dueDate: draft.dueDate,
            ideaStatus: draft.ideaStatus,
            ideaTag: draft.ideaTag,
            parentGoalID: draft.parentGoalID
        )
        withAnimation(spring) {
            modelContext.insert(task)
            expandedTaskID = task.id
        }
        // Commit immediately so the row appears the moment the sheet closes.
        try? modelContext.save()
        NotificationManager.shared.schedule(for: task)
    }
}

// MARK: - TodayHeader
//
// Default welcome: Option B (hyper-minimal) — locked.
//   "Welcome."
//   "A faster way to think."

struct TodayHeader: View {
    @Environment(ThemeStore.self) private var theme
    let tasks: [PersistedTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if tasks.isEmpty {
                firstLaunchState
            } else {
                steadyState
            }
        }
    }

    private var firstLaunchState: some View {
        let p = theme.palette
        return VStack(alignment: .leading, spacing: 10) {
            Text("Welcome.")
                .font(p.font(.display))
                .tracking(p.displayTracking)
                .foregroundStyle(p.textPrimary)

            Text("A faster way to think.")
                .font(p.font(.body))
                .foregroundStyle(p.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private var steadyState: some View {
        let p = theme.palette
        let today = Date.now
        let calendar = Calendar.autoupdatingCurrent

        // Due today: any actionable item (todo or reminder) with a deadline
        // landing on the current calendar day and not yet completed.
        let dueToday = tasks.filter { t in
            guard t.type == .todo || t.type == .reminder else { return false }
            guard let due = t.dueDate else { return false }
            guard !(t.isDone ?? false) else { return false }
            return calendar.isDate(due, inSameDayAs: today)
        }.count

        // Upcoming: actionable items with a deadline in the future.
        let upcoming = tasks.filter { t in
            guard t.type == .todo || t.type == .reminder else { return false }
            guard let due = t.dueDate else { return false }
            guard !(t.isDone ?? false) else { return false }
            return due > today && !calendar.isDate(due, inSameDayAs: today)
        }.count

        let marinating = tasks.filter {
            $0.type == .idea && ($0.ideaStatus ?? .thinking) != .completed
        }.count

        return VStack(alignment: .leading, spacing: 16) {
            Text("Today")
                .font(p.font(.display))
                .tracking(p.displayTracking)
                .foregroundStyle(p.textPrimary)

            HStack(spacing: 22) {
                countLabel(value: dueToday, label: "Due today")
                divider
                countLabel(value: upcoming, label: "Upcoming")
                divider
                countLabel(value: marinating, label: "Marinating")
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.palette.prominent)
            .frame(width: 0.5, height: 22)
    }

    private func countLabel(value: Int, label: String) -> some View {
        let p = theme.palette
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.system(size: 22, weight: .semibold, design: p.fontDesign))
                .monospacedDigit()
                .tracking(-0.2)
                .foregroundStyle(p.textPrimary)
            Text(label)
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .foregroundStyle(p.textSecondary)
        }
    }
}

#Preview {
    TasksTabView()
        .environment(ThemeStore())
        .modelContainer(
            for: [PersistedTask.self, PersistedNote.self, PersistedGoal.self],
            inMemory: true
        )
        .preferredColorScheme(.dark)
}
