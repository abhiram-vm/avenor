import SwiftUI
import SwiftData

// MARK: - OverviewTabView — Command Center (Sophisticated Stark)
//
// The default landing surface. A ruthless, high-density global timeline of
// the local system. Reads from SwiftData live and routes mutations through
// `TaskMutator` so notifications + widget snapshots stay in lockstep with
// the rest of the app.
//
// Anatomy:
//   • Header           — heavy editorial COMMAND title + meta strip
//   • DUE TODAY        — actionable todos/reminders due today, swipe-to-complete
//   • ACTIVE METRICS   — uncompleted goals, compact hairline progress bars
//   • RECENT BRAIN DUMPS — top 3 most-recently-edited notes, meta-only display

struct OverviewTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeStore.self) private var theme

    // Live queries. Full result sets are sorted and filtered locally so we
    // can re-use the existing computed properties on each model.
    @Query(sort: \PersistedTask.sortOrder) private var tasks: [PersistedTask]
    @Query(sort: \PersistedGoal.sortOrder) private var goals: [PersistedGoal]
    @Query private var notes: [PersistedNote]

    @State private var expandedTaskID: UUID? = nil
    @State private var isPresentingSettings: Bool = false

    private let spring = Animation.spring(response: 0.35, dampingFraction: 0.7)
    private let exitSpring = Animation.spring(duration: 0.25)

    // Header date — formatted once per render. `dateStyle` short keeps it
    // unambiguous in any locale ("MAY 24, 2026" / "24 MAY 2026").
    private static let headerDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        return f
    }()

    var body: some View {
        let p = theme.palette
        NavigationStack {
            ZStack {
                canvasLayer(p)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        header
                            .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                            .padding(.top, DesignTokens.Spacing.pageTop)
                            .padding(.bottom, 16)

                        captureBar
                            .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                            .padding(.bottom, DesignTokens.Spacing.stackLarge)

                        dueTodaySection
                            .padding(.bottom, DesignTokens.Spacing.stackLarge)

                        activeMetricsSection
                            .padding(.bottom, DesignTokens.Spacing.stackLarge)

                        recentDumpsSection
                            .padding(.bottom, DesignTokens.Spacing.pageBottom)
                    }
                }
                .scrollIndicators(.hidden)
                .animation(exitSpring, value: dueToday.map(\.id))
                .animation(spring, value: expandedTaskID)
            }
            .navigationTitle("Overview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Capture bar

    private var captureBar: some View {
        StarkCaptureBar(onSubmit: commitCapture)
    }

    /// Routes free-form text through `CaptureParser` and inserts the
    /// appropriate model. All inserts animate in via the active spring so
    /// the new row visibly drops into the lists below.
    private func commitCapture(_ raw: String) {
        guard let intent = CaptureParser.parse(raw) else { return }
        withAnimation(spring) {
            switch intent {
            case .todo(let title, let dueDate, let priority):
                // Priority is rendered into `details` as a leading marker so
                // it's visible without a dedicated schema field. Future
                // phases can promote this to a typed column on
                // `PersistedTask`; until then the prefix is the lightest-
                // touch surface for the value to live.
                let task = PersistedTask(
                    title: title,
                    details: priorityDetailsPrefix(priority),
                    type: .todo,
                    dueDate: dueDate
                )
                modelContext.insert(task)
                NotificationManager.shared.schedule(for: task)
                // High-priority timed todos that start within the next 15
                // minutes spin up a Lock Screen / Dynamic Island countdown.
                // Gates internally — untimed or low-priority captures no-op.
                EventLiveActivityManager.maybeStartCountdown(
                    title: title,
                    eventStart: dueDate,
                    priority: priority
                )

            case .idea(let title, let tag, let priority):
                // Ideas don't have a dedicated priority field either, so we
                // route the same prefix into `details`. The hashtag remains
                // the canonical `ideaTag`.
                let task = PersistedTask(
                    title: title,
                    details: priorityDetailsPrefix(priority),
                    type: .idea,
                    ideaStatus: .thinking,
                    ideaTag: tag.isEmpty ? nil : tag
                )
                modelContext.insert(task)

            case .note(let title, let body):
                let note = PersistedNote(title: title, details: body, lastEditedAt: .now)
                modelContext.insert(note)

            case .habit(let title, let rule, let anchor, let tag, let priority):
                // Recurring captures route to the dedicated habit container
                // rather than the task list. Streak tracking starts at zero.
                let habit = PersistedHabit(
                    title: title,
                    details: priorityDetailsPrefix(priority),
                    recurrence: rule,
                    anchorDate: anchor,
                    tag: tag,
                    priority: priority
                )
                modelContext.insert(habit)
            }
        }
        // Commit the capture immediately so newly captured tasks/notes/
        // habits surface in their @Query-backed feeds without waiting for
        // the autosave coalescing window.
        try? modelContext.save()
    }

    /// Maps a parser-extracted priority (1 = highest, 3 = lowest) to a
    /// short uppercase marker the user can read at a glance. Returns the
    /// empty string when no priority was set.
    private func priorityDetailsPrefix(_ priority: Int?) -> String {
        guard let priority else { return "" }
        return "P\(priority)"
    }

    // MARK: Canvas

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

    // MARK: Header

    private var header: some View {
        let p = theme.palette
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Command")
                    .font(p.font(.display))
                    .tracking(p.displayTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(p.textPrimary)

                Spacer(minLength: 0)

                settingsButton
            }

            HStack(spacing: 0) {
                Text(Self.headerDateFormatter.string(from: .now))
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .monospacedDigit()
                    .foregroundStyle(p.textSecondary)

                Text("·")
                    .font(p.font(.micro))
                    .foregroundStyle(p.textTertiary)
                    .padding(.horizontal, 8)

                Text("Registry Status: Active")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(p.textSecondary)

                Spacer(minLength: 0)
            }
        }
        .sheet(isPresented: $isPresentingSettings) {
            SettingsView()
        }
    }

    /// 32pt circular toolbar affordance — same anatomy as the plus button
    /// on Tasks/Notes/Goals so the entry point reads as native chrome.
    private var settingsButton: some View {
        let p = theme.palette
        return Button {
            AppHaptic.tap()
            isPresentingSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(p.textPrimary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(p.chromeSurface))
                .overlay(
                    Circle().strokeBorder(p.hairline, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    // MARK: Section A — DUE TODAY

    private var dueTodaySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "Due Today", count: dueToday.count)

            if dueToday.isEmpty {
                StarkEmptyState(
                    "No action items due today.",
                    footnote: "Inbox holds the line."
                )
                .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
            } else {
                rowSeparator
                ForEach(dueToday) { task in
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
                    rowSeparator
                }
            }
        }
    }

    // MARK: Section B — ACTIVE METRICS
    //
    // Each metric is wrapped in `GoalIncrementSwipeRow` so the Apple-Music
    // gesture works from the home screen too. Trailing swipe leads to
    // abandon — the same destructive action surfaced on the Goals tab.

    private var activeMetricsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "Active Metrics", count: activeGoals.count)

            if activeGoals.isEmpty {
                StarkEmptyState(
                    "No metrics tracked.",
                    footnote: "Open Goals to define one."
                )
                .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
            } else {
                rowSeparator
                ForEach(activeGoals) { goal in
                    GoalIncrementSwipeRow(
                        onIncrement: { GoalMutator.increment(goal, with: exitSpring) },
                        trailing: StarkSwipeAction(
                            systemImage: "archivebox",
                            label: "Abandon",
                            perform: { GoalMutator.abandon(goal, with: exitSpring) }
                        ),
                        isAtCeiling: goal.currentValue >= goal.targetValue
                    ) {
                        CompactGoalMetricRow(goal: goal)
                    }
                    rowSeparator
                }
            }
        }
    }

    // MARK: Section C — RECENT BRAIN DUMPS

    private var recentDumpsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "Recent Brain Dumps", count: recentNotes.count)

            if recentNotes.isEmpty {
                StarkEmptyState(
                    "No notes recorded.",
                    footnote: "Capture a thought in Notes."
                )
                .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
            } else {
                rowSeparator
                ForEach(recentNotes) { note in
                    RecentDumpRow(note: note)
                    rowSeparator
                }
            }
        }
    }

    // MARK: Shared chrome

    private func sectionHeader(title: String, count: Int) -> some View {
        let p = theme.palette
        return HStack(spacing: 0) {
            Text(title)
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .foregroundStyle(p.textPrimary)

            Text("·")
                .font(p.font(.micro))
                .foregroundStyle(p.textTertiary)
                .padding(.horizontal, 8)

            Text("\(count)")
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .monospacedDigit()
                .foregroundStyle(p.textTertiary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
        .padding(.bottom, 12)
    }

    private var rowSeparator: some View {
        Rectangle()
            .fill(theme.palette.hairline)
            .frame(height: 0.5)
    }

    // MARK: Derived queries

    /// Todos and reminders whose `dueDate` lands on the current day and that
    /// have not been completed. Sorted by deadline ascending so the next
    /// thing to act on is at the top.
    private var dueToday: [PersistedTask] {
        let calendar = Calendar.autoupdatingCurrent
        return tasks.filter { t in
            guard t.type == .todo || t.type == .reminder else { return false }
            guard !(t.isDone ?? false) else { return false }
            guard let due = t.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: .now)
        }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    /// Uncompleted, un-abandoned goals only. Sorted by progress descending
    /// so the most advanced metric reads first.
    private var activeGoals: [PersistedGoal] {
        goals.filter { !$0.isCompleted && !$0.isAbandoned }
            .sorted { $0.progress > $1.progress }
    }

    /// Top 3 most-recently-edited notes. Falls back to `updatedAt` when a
    /// note hasn't been explicitly edited yet.
    private var recentNotes: [PersistedNote] {
        notes
            .sorted { effectiveEdit($0) > effectiveEdit($1) }
            .prefix(3)
            .map { $0 }
    }

    private func effectiveEdit(_ n: PersistedNote) -> Date {
        n.lastEditedAt ?? n.updatedAt
    }

    // MARK: Mutations (routed through TaskMutator)

    private func toggleExpanded(_ task: PersistedTask) {
        withAnimation(spring) {
            expandedTaskID = (expandedTaskID == task.id) ? nil : task.id
        }
        AppHaptic.tap()
    }

    private func complete(_ task: PersistedTask) {
        TaskMutator.complete(task, in: modelContext, with: exitSpring)
        WidgetSnapshotPublisher.publishToday(tasks: tasks)
    }

    private func delete(_ task: PersistedTask) {
        if expandedTaskID == task.id { expandedTaskID = nil }
        TaskMutator.delete(task, in: modelContext, with: spring)
        WidgetSnapshotPublisher.publishToday(tasks: tasks)
    }

    private func completionLabel(for task: PersistedTask) -> String {
        switch task.type {
        case .todo: return "Done"
        case .reminder: return "Ack"
        case .idea: return "Shipped"
        }
    }
}

// MARK: - CompactGoalMetricRow
//
// Higher-density variant of `GoalRowCell`. One-line title, meta strip
// underneath, hairline progress bar. No tap target — Overview is a
// read-only command center.

struct CompactGoalMetricRow: View {
    @Environment(ThemeStore.self) private var theme
    let goal: PersistedGoal

    var body: some View {
        let p = theme.palette
        HStack(spacing: 0) {
            Rectangle()
                .fill(goal.tint.opacity(0.85))
                .frame(width: 2)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text(goal.title)
                    .font(p.font(.headline))
                    .tracking(p.headlineTracking)
                    .foregroundStyle(p.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 0) {
                    Text("Goal")
                        .font(p.font(.micro))
                        .tracking(p.microTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(p.textSecondary)

                    Text("·")
                        .font(p.font(.micro))
                        .foregroundStyle(p.textTertiary)
                        .padding(.horizontal, 8)

                    Text("\(goal.currentText) / \(goal.targetText)")
                        .font(p.font(.micro))
                        .tracking(p.microTracking)
                        .textCase(.uppercase)
                        .monospacedDigit()
                        .foregroundStyle(p.textSecondary)

                    Spacer(minLength: 0)

                    Text(goal.percentText)
                        .font(p.font(.micro))
                        .tracking(p.microTracking)
                        .textCase(.uppercase)
                        .monospacedDigit()
                        .foregroundStyle(p.textPrimary)
                }

                progressBar(p)
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(p.rowFill)
    }

    private func progressBar(_ p: ThemePalette) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(p.hairline)
                Rectangle()
                    .fill(goal.tint.opacity(0.85))
                    .frame(width: max(0, min(1, goal.progress)) * geo.size.width)
            }
        }
        .frame(height: 2)
    }
}

// MARK: - RecentDumpRow
//
// Demoted note preview. Title + meta strip (`NOTE · N WORDS · EDITED MAR 4`).
// No body preview — Overview surfaces the *existence* of recent thinking,
// not the content. Tapping in is the Notes tab's job.

struct RecentDumpRow: View {
    @Environment(ThemeStore.self) private var theme
    let note: PersistedNote

    private static let editedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()

    var body: some View {
        let p = theme.palette
        HStack(spacing: 0) {
            Rectangle()
                .fill(DesignTokens.Accent.note.opacity(0.85))
                .frame(width: 2)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                metaStrip
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(p.font(.headline))
                    .tracking(p.headlineTracking)
                    .foregroundStyle(note.title.isEmpty ? p.textSecondary : p.textPrimary)
                    .lineLimit(1)
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(p.rowFill)
    }

    private var metaStrip: some View {
        HStack(spacing: 0) {
            metaToken("Note")

            separator
            metaToken("\(note.wordCount) word\(note.wordCount == 1 ? "" : "s")", monospaced: true)

            if let edited = note.lastEditedAt {
                separator
                metaToken("Edited \(Self.editedFormatter.string(from: edited))", monospaced: true)
            }

            Spacer(minLength: 0)
        }
    }

    private func metaToken(_ text: String, monospaced: Bool = false) -> some View {
        let p = theme.palette
        return Text(text)
            .font(p.font(.micro))
            .tracking(p.microTracking)
            .textCase(.uppercase)
            .monospacedDigit()
            .foregroundStyle(p.textSecondary)
            .lineLimit(1)
    }

    private var separator: some View {
        let p = theme.palette
        return Text("·")
            .font(p.font(.micro))
            .foregroundStyle(p.textTertiary)
            .padding(.horizontal, 8)
    }
}

#Preview {
    OverviewTabView()
        .environment(ThemeStore())
        .modelContainer(
            for: [PersistedTask.self, PersistedNote.self, PersistedGoal.self],
            inMemory: true
        )
        .preferredColorScheme(.dark)
}
