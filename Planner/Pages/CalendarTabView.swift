import SwiftUI
import SwiftData
import EventKit

// MARK: - CalendarTabView (Sophisticated Stark)
//
// Two-part layout:
// Part A: Month grid (read-only, Stark-styled day cells with task dots)
// Part B: Daily timeline — interactive tasks (StarkSwipeRow) merged
//         chronologically with read-only system calendar events (EventKit).

struct CalendarTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ThemeStore.self) private var theme

    @Query(sort: \PersistedTask.sortOrder) private var tasks: [PersistedTask]

    @State private var monthAnchor: Date = .now
    @State private var selectedDay: Date = .now
    @State private var dailyEvents: [EKEvent] = []

    private let calendar = Calendar.autoupdatingCurrent
    private let service = TaskCalendarService()
    private let calendarService = CalendarKitService.shared
    private let spring = Animation.spring(response: 0.35, dampingFraction: 0.7)

    var body: some View {
        let p = theme.palette
        NavigationStack {
            ZStack {
                p.canvasView

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.stackLarge) {
                        monthGrid
                        dayTasksSection
                    }
                    .padding(.horizontal, DesignTokens.Spacing.pageHorizontal)
                    .padding(.top, DesignTokens.Spacing.pageTop)
                    .padding(.bottom, DesignTokens.Spacing.pageBottom)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: selectedDay) {
                await loadEvents(for: selectedDay)
            }
            .onChange(of: scenePhase) { _, phase in
                // External calendar edits may have landed while backgrounded —
                // drop the cache and re-scan the visible day on return.
                guard phase == .active else { return }
                calendarService.invalidateCache()
                Task { await loadEvents(for: selectedDay) }
            }
        }
    }

    // MARK: Part A — Month Grid (Read-Only, palette-driven)

    private var monthGrid: some View {
        let p = theme.palette
        return VStack(alignment: .leading, spacing: 14) {
            header
            weekdayRow

            let days = CalendarFormatter.monthGrid(containing: monthAnchor)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                spacing: 8
            ) {
                ForEach(days, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
        .padding(DesignTokens.Spacing.cardInset)
        .background(monthGridBackground(p))
    }

    @ViewBuilder
    private func monthGridBackground(_ p: ThemePalette) -> some View {
        let shape = RoundedRectangle(cornerRadius: p.cardRadius, style: .continuous)
        switch p.cardSurface {
        case .flat(let fill):
            shape
                .fill(fill)
                .overlay(shape.strokeBorder(p.cardBorder, lineWidth: p.cardBorderWidth))
        case .material(let material, _):
            shape
                .fill(material)
                .overlay(shape.strokeBorder(p.cardBorder, lineWidth: p.cardBorderWidth))
        }
    }

    private var header: some View {
        let p = theme.palette
        return HStack {
            navButton(icon: "chevron.left") {
                withAnimation(spring) {
                    monthAnchor = calendar.date(byAdding: .month, value: -1, to: monthAnchor) ?? monthAnchor
                }
            }

            Spacer()

            VStack(alignment: .center, spacing: 2) {
                Text(CalendarFormatter.monthTitle(monthAnchor))
                    .font(p.font(.title))
                    .tracking(p.headlineTracking)
                    .foregroundStyle(p.textPrimary)
            }

            Spacer()

            navButton(icon: "chevron.right") {
                withAnimation(spring) {
                    monthAnchor = calendar.date(byAdding: .month, value: 1, to: monthAnchor) ?? monthAnchor
                }
            }
        }
    }

    private func navButton(icon: String, action: @escaping () -> Void) -> some View {
        let p = theme.palette
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(p.textPrimary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(p.chromeSurface))
                .overlay(Circle().strokeBorder(p.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var weekdayRow: some View {
        let p = theme.palette
        return HStack {
            ForEach(calendar.shortWeekdaySymbols, id: \.self) { s in
                Text(s)
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(p.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 2)
    }

    private func dayCell(_ day: Date) -> some View {
        let p = theme.palette
        let inDisplayedMonth = calendar.isDate(day, equalTo: monthAnchor, toGranularity: .month)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        let dayTasks = service.tasksForCalendar(on: day, in: tasks)
        let hasTasks = !dayTasks.isEmpty

        return Button {
            withAnimation(spring) { selectedDay = day }
            AppHaptic.tap()
        } label: {
            VStack(spacing: 6) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 14, weight: isToday ? .bold : .semibold, design: p.fontDesign))
                    .monospacedDigit()
                    .foregroundStyle(inDisplayedMonth ? p.textPrimary : p.textTertiary)

                if hasTasks {
                    HStack(spacing: 3) {
                        ForEach(dayTasks.prefix(3)) { task in
                            Circle()
                                .fill(task.type.tint.opacity(0.80))
                                .frame(width: 4, height: 4)
                        }
                        if dayTasks.count > 3 {
                            Circle()
                                .fill(p.textTertiary)
                                .frame(width: 4, height: 4)
                        }
                    }
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .fill(isSelected ? p.chromeSurface : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .strokeBorder(
                        isToday ? p.prominent : (isSelected ? p.hairline : Color.clear),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Part B — Daily Task List (StarkSwipeRow Pattern)

    private var dayTasksSection: some View {
        let items   = service.tasksForCalendar(on: selectedDay, in: tasks)
        let entries = mergedTimeline(tasks: items, events: dailyEvents)

        return VStack(alignment: .leading, spacing: 12) {
            dayHeader(taskCount: items.count, eventCount: dailyEvents.count)

            if entries.isEmpty {
                emptyState
            } else {
                timelineList(entries)
            }
        }
    }

    private func dayHeader(taskCount: Int, eventCount: Int) -> some View {
        let p = theme.palette
        return HStack(spacing: 0) {
            Text(CalendarFormatter.dayTitle(selectedDay))
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .foregroundStyle(p.textSecondary)

            Text("·")
                .font(p.font(.micro))
                .foregroundStyle(p.textTertiary)
                .padding(.horizontal, 8)

            Text("\(taskCount) task\(taskCount == 1 ? "" : "s")")
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .monospacedDigit()
                .foregroundStyle(p.textSecondary)

            if eventCount > 0 {
                Text("·")
                    .font(p.font(.micro))
                    .foregroundStyle(p.textTertiary)
                    .padding(.horizontal, 8)

                Text("\(eventCount) event\(eventCount == 1 ? "" : "s")")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .monospacedDigit()
                    .foregroundStyle(p.textSecondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        StarkEmptyState(
            "No action items due today.",
            footnote: "Quiet day on the calendar."
        )
    }

    private func timelineList(_ entries: [TimelineEntry]) -> some View {
        VStack(spacing: 0) {
            separator
            ForEach(entries) { entry in
                Group {
                    switch entry {
                    case .task(let task):
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
                                isExpanded: false,
                                onToggleExpanded: { },
                                onDelete: { delete(task) }
                            )
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                    case .event(let event):
                        CalendarEventCard(event: event)
                            .transition(.opacity)
                    }
                }
                separator
            }
        }
        .animation(spring, value: entries.map(\.id))
    }

    private var separator: some View {
        Rectangle()
            .fill(theme.palette.hairline)
            .frame(height: 0.5)
    }

    // MARK: Timeline merge (tasks + system calendar events)

    /// A single row in the daily timeline — either an interactive Avenor task
    /// or a read-only system calendar event. Sorted chronologically so a 9 AM
    /// meeting lands above a 2 PM todo.
    private enum TimelineEntry: Identifiable {
        case task(PersistedTask)
        case event(EKEvent)

        var id: String {
            switch self {
            case .task(let t):  return "task-\(t.id.uuidString)"
            case .event(let e): return "event-\(e.eventIdentifier ?? e.calendarItemIdentifier)"
            }
        }

        /// Chronological sort key. All-day events and untimed/active tasks
        /// sink to the top of the day.
        var sortTime: Date {
            switch self {
            case .task(let t):  return t.dueDate ?? .distantPast
            case .event(let e): return e.isAllDay ? .distantPast : e.startDate
            }
        }
    }

    private func mergedTimeline(tasks: [PersistedTask], events: [EKEvent]) -> [TimelineEntry] {
        let merged = tasks.map(TimelineEntry.task) + events.map(TimelineEntry.event)
        return merged.sorted { $0.sortTime < $1.sortTime }
    }

    private func loadEvents(for day: Date) async {
        guard await calendarService.requestAccessIfNeeded() else {
            if !dailyEvents.isEmpty { dailyEvents = [] }
            return
        }
        let fetched = await calendarService.fetchEvents(for: day)
        withAnimation(.easeInOut(duration: 0.25)) {
            dailyEvents = fetched
        }
    }

    // MARK: Task mutation

    private func complete(_ task: PersistedTask) {
        withAnimation(spring) {
            switch task.type {
            case .todo, .reminder: task.isDone = true
            case .idea: task.ideaStatus = .completed
            }
        }
        NotificationManager.shared.schedule(for: task)
    }

    private func delete(_ task: PersistedTask) {
        NotificationManager.shared.cancel(for: task)
        withAnimation(spring) {
            modelContext.delete(task)
        }
    }
}

#Preview {
    CalendarTabView()
        .environment(ThemeStore())
        .modelContainer(
            for: [PersistedTask.self, PersistedNote.self, PersistedGoal.self],
            inMemory: true
        )
        .preferredColorScheme(.dark)
}
