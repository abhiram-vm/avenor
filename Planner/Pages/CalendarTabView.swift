import SwiftUI
import SwiftData

// MARK: - CalendarTabView (Sophisticated Stark)
//
// Two-part layout:
// Part A: Month grid (read-only, Stark-styled day cells with task dots)
// Part B: Daily task list (StarkSwipeRow pattern for interactive task management)

struct CalendarTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeStore.self) private var theme

    @Query(sort: \PersistedTask.sortOrder) private var tasks: [PersistedTask]

    @State private var monthAnchor: Date = .now
    @State private var selectedDay: Date = .now

    private let calendar = Calendar.autoupdatingCurrent
    private let service = TaskCalendarService()
    private let spring = Animation.spring(response: 0.35, dampingFraction: 0.7)

    var body: some View {
        let p = theme.palette
        NavigationStack {
            ZStack {
                canvasLayer(p)

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
        }
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
        let items = service.tasksForCalendar(on: selectedDay, in: tasks)

        return VStack(alignment: .leading, spacing: 12) {
            dayHeader(itemCount: items.count)

            if items.isEmpty {
                emptyState
            } else {
                taskListWithSwipe(items)
            }
        }
    }

    private func dayHeader(itemCount: Int) -> some View {
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

            Text("\(itemCount) task\(itemCount == 1 ? "" : "s")")
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .monospacedDigit()
                .foregroundStyle(p.textSecondary)

            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        StarkEmptyState(
            "No action items due today.",
            footnote: "Quiet day on the calendar."
        )
    }

    private func taskListWithSwipe(_ items: [PersistedTask]) -> some View {
        VStack(spacing: 0) {
            separator
            ForEach(items) { task in
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
                        isExpanded: false,
                        onToggleExpanded: { },
                        onDelete: { delete(task) }
                    )
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
                separator
            }
        }
        .animation(spring, value: items.map(\.id))
    }

    private var separator: some View {
        Rectangle()
            .fill(theme.palette.hairline)
            .frame(height: 0.5)
    }

    // MARK: Task mutation

    private func completionLabel(for task: PersistedTask) -> String {
        switch task.type {
        case .todo: return "Done"
        case .reminder: return "Ack"
        case .idea: return "Shipped"
        }
    }

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
