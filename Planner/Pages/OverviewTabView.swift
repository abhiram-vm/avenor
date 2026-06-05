import SwiftUI
import SwiftData

// MARK: - OverviewTabView — Command Center (1.3 Rebuild)
//
// The default landing surface. A ruthless, high-density global timeline of
// the local system. Reads from SwiftData live and routes mutations through
// `TaskMutator` so notifications + widget snapshots stay in lockstep.
//
// Anatomy:
//   • Header           — editorial COMMAND title + date meta
//   • Capture Bar      — smart natural-language capture
//   • 7-Day Heatmap    — timezone-safe weekly completion indicator
//                        (replaces the former "Recent Brain Dumps" block)
//   • DUE ON [DATE]    — tasks due on the heatmap-selected day
//   • ACTIVE METRICS   — uncompleted goals, compact hairline progress bars

struct OverviewTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeStore.self) private var theme

    // Live queries. Full result sets are sorted and filtered locally so we
    // can re-use the existing computed properties on each model.
    @Query(sort: \PersistedTask.sortOrder) private var tasks: [PersistedTask]
    @Query(sort: \PersistedGoal.sortOrder) private var goals: [PersistedGoal]
    @Query(sort: \PersistedHabit.sortOrder) private var habits: [PersistedHabit]

    @State private var expandedTaskID: UUID? = nil
    @State private var isPresentingSettings: Bool = false
    /// The day currently selected in the 7-day heatmap. Defaults to today.
    /// Drives the "Due on [date]" task timeline below the heatmap.
    @State private var selectedDate: Date = Calendar.autoupdatingCurrent.startOfDay(for: Date())

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
                p.canvasView

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        header
                            .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                            .padding(.top, DesignTokens.Spacing.pageTop)
                            .padding(.bottom, 16)

                        captureBar
                            .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                            .padding(.bottom, 16)

                        weekHeatmapSection
                            .padding(.bottom, DesignTokens.Spacing.stackLarge)

                        dueTodaySection
                            .padding(.bottom, DesignTokens.Spacing.stackLarge)

                        activeMetricsSection
                            .padding(.bottom, DesignTokens.Spacing.pageBottom)
                    }
                }
                .scrollIndicators(.hidden)
                .animation(exitSpring, value: dueOnSelectedDate.map(\.id))
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
                // Priority is stored on the typed `priority` column (1 = highest)
                // so the Tasks list can sort hierarchically and `.p1` rows can
                // render their accent glow.
                let task = PersistedTask(
                    title: title,
                    type: .todo,
                    dueDate: dueDate,
                    priority: priority
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
                // The hashtag remains the canonical `ideaTag`; priority lands
                // on the typed `priority` column like todos.
                let task = PersistedTask(
                    title: title,
                    type: .idea,
                    ideaStatus: .thinking,
                    ideaTag: tag.isEmpty ? nil : tag,
                    priority: priority
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

                Text("\(openTaskCount) Open")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .monospacedDigit()
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

    // MARK: Section A — 7-DAY HEATMAP

    private var weekHeatmapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "This Week", count: 0, showCount: false)
            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { day in
                    DayHeatCell(
                        day: day,
                        state: heatState(for: day),
                        isSelected: Calendar.autoupdatingCurrent.isDate(day, inSameDayAs: selectedDate),
                        palette: theme.palette,
                        onTap: {
                            withAnimation(DesignTokens.Motion.smooth) { selectedDate = day }
                            AppHaptic.tap()
                        }
                    )
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
        }
    }

    // MARK: Section B — DUE ON [DATE]

    private var dueTodaySection: some View {
        let cal = Calendar.autoupdatingCurrent
        let isToday = cal.isDateInToday(selectedDate)
        let title = isToday ? "Due Today" : "Due \(selectedDayLabel)"
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: title, count: dueOnSelectedDate.count)

            if dueOnSelectedDate.isEmpty {
                StarkEmptyState(
                    isToday ? "No action items due today." : "Nothing due on this day.",
                    footnote: isToday ? "You're all clear." : "Select today to see your queue."
                )
                .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
            } else {
                RowSeparator()
                ForEach(dueOnSelectedDate) { task in
                    StarkSwipeRow(
                        leading: StarkSwipeAction(
                            systemImage: "checkmark",
                            label: task.completionVerb,
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
                    RowSeparator()
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
                RowSeparator()
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
                        CompactGoalMetricRow(goal: goal, routineStreak: linkedRoutineStreak(for: goal))
                    }
                    RowSeparator()
                }
            }
        }
    }

    // MARK: Shared chrome

    private func sectionHeader(title: String, count: Int, showCount: Bool = true) -> some View {
        let p = theme.palette
        return HStack(spacing: 0) {
            Text(title)
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .foregroundStyle(p.textPrimary)

            if showCount {
                Text("·")
                    .font(p.font(.micro))
                    .foregroundStyle(p.textTertiary)
                    .padding(.horizontal, 8)

                Text("\(count)")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .monospacedDigit()
                    .foregroundStyle(p.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
        .padding(.bottom, 12)
    }

    // MARK: Derived queries

    /// Tasks (todos / reminders) due on `selectedDate` that are not yet
    /// completed. Sorted by deadline ascending so the next action is at top.
    /// The "Due on [date]" section header updates to reflect the selection.
    private var dueOnSelectedDate: [PersistedTask] {
        let cal = Calendar.autoupdatingCurrent
        return tasks.filter { t in
            guard t.type == .todo || t.type == .reminder else { return false }
            guard !(t.isDone ?? false) else { return false }
            guard let due = t.dueDate else { return false }
            return cal.isDate(due, inSameDayAs: selectedDate)
        }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    /// Uncompleted `.active` goals only. Converted goals (migrated into the
    /// 1.3 habit engine) and abandoned goals are excluded. Sorted by progress
    /// descending so the most advanced metric reads first.
    private var activeGoals: [PersistedGoal] {
        goals.filter { !$0.isCompleted && $0.status == .active }
            .sorted { $0.progress > $1.progress }
    }

    /// Count of incomplete actionable tasks (todos + reminders) — surfaced in
    /// the header as a true, live status rather than decorative chrome.
    private var openTaskCount: Int {
        tasks.filter { ($0.type == .todo || $0.type == .reminder) && !($0.isDone ?? false) }.count
    }

    /// Current streak of the child routine anchored to a goal, if one exists.
    /// Returns `nil` for goals with no linked execution system so the Overview
    /// flame only surfaces where a real streak is being tracked.
    private func linkedRoutineStreak(for goal: PersistedGoal) -> Int? {
        habits.first { !$0.isArchived && $0.anchorGoalID == goal.id }?.streakCount
    }

    // MARK: Heatmap data model

    struct DayHeatState {
        let scheduledCount: Int
        let completedCount: Int

        var ratio: Double {
            guard scheduledCount > 0 else { return 0 }
            return Double(completedCount) / Double(scheduledCount)
        }

        var completionLevel: CompletionLevel {
            if scheduledCount == 0 { return .empty }
            if completedCount >= scheduledCount { return .full }
            if completedCount > 0 { return .partial }
            return .empty
        }
    }

    enum CompletionLevel { case full, partial, empty }

    /// The 7 start-of-day dates for the current calendar week, computed
    /// strictly from `Date()` using `Calendar.autoupdatingCurrent` so the
    /// week boundary respects the device's active time zone and locale.
    private var weekDays: [Date] {
        let cal = Calendar.autoupdatingCurrent
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return (0..<7).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: weekInterval.start)
        }.map { cal.startOfDay(for: $0) }
    }

    private var selectedDayLabel: String {
        let cal = Calendar.autoupdatingCurrent
        if cal.isDateInYesterday(selectedDate) { return "Yesterday" }
        if cal.isDateInTomorrow(selectedDate) { return "Tomorrow" }
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f.string(from: selectedDate)
    }

    /// Compute the completion heat state for a given calendar day.
    /// Uses `Calendar.autoupdatingCurrent` throughout for timezone safety.
    private func heatState(for day: Date) -> DayHeatState {
        let cal = Calendar.autoupdatingCurrent
        let dayStart = cal.startOfDay(for: day)
        let today = cal.startOfDay(for: Date())

        // Don't report completion for future days — they're unscheduled.
        guard dayStart <= today else {
            return DayHeatState(scheduledCount: 0, completedCount: 0)
        }

        let weekday = cal.component(.weekday, from: dayStart)   // 1=Sun, 2=Mon…7=Sat
        let isWeekday = weekday >= 2 && weekday <= 6

        // Active, non-archived routines
        let activeHabits = habits.filter { !$0.isArchived }

        // Which routines are scheduled for this specific day?
        let scheduled = activeHabits.filter { habit in
            switch habit.recurrence {
            case .daily:             return true
            case .weekdays:          return isWeekday
            case .weekly(let wd):
                guard let wd else { return false }
                return wd == weekday
            case .customDays(let days):
                return days.contains(weekday)
            }
        }

        // Infer completion from streak window (same logic as WeekDotChain).
        var completedHabits = 0
        for habit in scheduled {
            guard habit.streakCount > 0, let last = habit.lastCompletedAt else { continue }
            let lastDay = cal.startOfDay(for: last)
            for offset in 0..<habit.streakCount {
                guard let d = cal.date(byAdding: .day, value: -offset, to: lastDay) else { continue }
                if cal.startOfDay(for: d) == dayStart { completedHabits += 1; break }
            }
        }

        // Tasks due on this day
        let dayTasks = tasks.filter { t in
            guard let due = t.dueDate else { return false }
            return cal.isDate(due, inSameDayAs: dayStart)
        }
        let completedTasks = dayTasks.filter { $0.isDone ?? false }.count

        return DayHeatState(
            scheduledCount: scheduled.count + dayTasks.count,
            completedCount: completedHabits + completedTasks
        )
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
}

// MARK: - CompactGoalMetricRow
//
// Higher-density variant of `GoalRowCell`. One-line title, meta strip
// underneath, hairline progress bar. No tap target — Overview is a
// read-only command center.

struct CompactGoalMetricRow: View {
    @Environment(ThemeStore.self) private var theme
    let goal: PersistedGoal
    /// Streak of the linked child routine. `nil` → goal has no execution
    /// system, so the flame + streak chip is suppressed entirely.
    var routineStreak: Int? = nil

    var body: some View {
        let p = theme.palette
        HStack(spacing: 0) {
            Rectangle()
                .fill(goal.displayTint)
                .frame(width: 2)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(goal.title)
                        .font(p.font(.headline))
                        .tracking(p.headlineTracking)
                        .foregroundStyle(p.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let streak = routineStreak {
                        StreakFlameChip(streak: streak, palette: p)
                    }
                }

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
                    .fill(goal.displayTint)
                    .frame(width: max(0, min(1, goal.progress)) * geo.size.width)
            }
        }
        .frame(height: 2)
    }
}

// MARK: - DayHeatCell
//
// One capsule-shaped day indicator in the 7-day heatmap bar.
//
// Completion levels drive the visual:
//   • Full    — solid palette.accent fill (all scheduled items done)
//   • Partial — unfilled ring with a 1.5pt muted border
//   • Empty   — hairline 0.5pt ring (nothing scheduled, or nothing done)
//
// Tapping sets selectedDate, which drives the timeline below.
// All date math uses Calendar.autoupdatingCurrent for timezone safety.

struct DayHeatCell: View {
    let day: Date
    let state: OverviewTabView.DayHeatState
    let isSelected: Bool
    let palette: ThemePalette
    let onTap: () -> Void

    private let cal = Calendar.autoupdatingCurrent

    private static let letterFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.dateFormat = "EEEEE"     // single-letter weekday: M, T, W…
        return f
    }()

    private static let numberFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.dateFormat = "d"
        return f
    }()

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                // Weekday letter — highlighted when selected
                Text(Self.letterFormatter.string(from: day))
                    .font(.system(size: 10, weight: .semibold, design: palette.fontDesign))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(isSelected ? palette.textPrimary : palette.textTertiary)

                // Bento date tile — rounded square with completion fill and
                // a precise current-day indicator line beneath the number.
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(cellFill)

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(ringColor, lineWidth: ringWidth)

                    VStack(spacing: 3) {
                        Text(Self.numberFormatter.string(from: day))
                            .font(.system(size: 13,
                                          weight: isSelected ? .bold : .semibold,
                                          design: palette.fontDesign))
                            .monospacedDigit()
                            .foregroundStyle(numberColor)

                        // Current-day indicator: a sharp, thin contrast track
                        // that grounds the calendar with a cockpit-style "now"
                        // marker. Only the live system date renders it.
                        if isToday {
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .fill(todayIndicatorColor)
                                .frame(width: 14, height: 2)
                        }
                    }
                }
                .frame(width: 38, height: 38)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Visual tokens

    private var level: OverviewTabView.CompletionLevel { state.completionLevel }
    private var isToday: Bool { cal.isDateInToday(day) }

    private var cellFill: Color {
        switch level {
        case .full:              return palette.accent.opacity(isToday ? 1.0 : 0.85)
        case .partial, .empty:  return isSelected ? palette.chromeSurface : .clear
        }
    }

    private var ringColor: Color {
        if level == .full {
            return isSelected ? palette.textPrimary.opacity(0.5) : .clear
        }
        if isSelected { return palette.prominent }
        if isToday    { return palette.textSecondary.opacity(0.55) }
        return level == .partial ? palette.textTertiary.opacity(0.45) : palette.hairline
    }

    private var ringWidth: CGFloat {
        if level == .full    { return isSelected ? 2 : 0 }
        if isSelected || isToday { return 1.5 }
        return 0.5
    }

    private var numberColor: Color {
        switch level {
        case .full: return palette.rowFill           // dark text on accent fill
        case .partial, .empty:
            return (isSelected || isToday) ? palette.textPrimary : palette.textTertiary
        }
    }

    /// Current-day indicator track color. On a fully-complete (accent-filled)
    /// tile we invert to `rowFill` for legible contrast; otherwise the line
    /// reads as a crisp palette-accent marker.
    private var todayIndicatorColor: Color {
        level == .full ? palette.rowFill : palette.accent
    }

    private var accessibilityLabel: String {
        let letter = Self.letterFormatter.string(from: day)
        let number = Self.numberFormatter.string(from: day)
        let desc: String
        switch level {
        case .full:    desc = "fully complete"
        case .partial: desc = "partially complete"
        case .empty:   desc = "no completions"
        }
        return "\(letter) \(number), \(desc)"
    }
}

// MARK: - StreakFlameChip
//
// Compact read-only streak indicator surfaced on the Overview dashboard for
// any goal backed by a child routine. Pairs the live streak count with an
// explicit white flame running a looping, hardware-accelerated breathing
// animation (scale + opacity) to read as fluid kinetic energy.

struct StreakFlameChip: View {
    let streak: Int
    let palette: ThemePalette

    @State private var animatePulse = false

    var body: some View {
        HStack(spacing: 5) {
            Text("\(streak)")
                .font(.system(size: 13, weight: .bold, design: palette.fontDesign))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .contentTransition(.numericText())

            Image(systemName: "flame.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .scaleEffect(animatePulse ? 1.06 : 0.94)
                .opacity(animatePulse ? 1.0 : 0.75)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous).fill(palette.chromeSurface)
        )
        .overlay(
            Capsule(style: .continuous).strokeBorder(palette.hairline, lineWidth: 0.5)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                animatePulse = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Routine streak \(streak) days")
    }
}

#Preview {
    OverviewTabView()
        .environment(ThemeStore())
        .modelContainer(
            for: [PersistedTask.self, PersistedNote.self, PersistedGoal.self, PersistedHabit.self],
            inMemory: true
        )
        .preferredColorScheme(.dark)
}
