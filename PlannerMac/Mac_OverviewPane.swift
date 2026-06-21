import SwiftUI
import SwiftData
import EventKit

// MARK: - Mac_OverviewPane
//
// The first thing you see: an enormous editorial "Today's Overview" hero with
// the date and a live due-count callout floated asymmetrically off its right,
// then a stacked digest of the day across every data type — Events, Tasks,
// Goals, and pinned Notes. Each section hides entirely when it has nothing to
// show, so the pane stays composed regardless of how full the day is.
//
// Reads are pull-only: tasks / goals / notes via `@Query`, calendar events via
// the shared `EventKitService`. The pane never mutates — completing a task
// routes through `TaskMutator`; goals here are read-only previews (incrementing
// lives in the Goals pane). Clicking a note jumps to the Notes pane.

struct Mac_OverviewPane: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(Mac_NavState.self) private var nav

    @Query private var tasks: [PersistedTask]
    @Query(sort: \PersistedGoal.createdAt) private var goals: [PersistedGoal]
    @Query private var notes: [PersistedNote]
    @Query private var habits: [PersistedHabit]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var orbView = MetalOrbView()

    /// Today's calendar events, refreshed on appear (EventKit is not a SwiftData
    /// source, so it can't drive an `@Query`).
    @State private var todaysEvents: [EKEvent] = []
    private let eventKit = EventKitService.shared

    private let calendar = Calendar.autoupdatingCurrent

    // MARK: Derived collections

    private var dueToday: [PersistedTask] {
        tasks
            .filter { t in
                guard !(t.isDone ?? false), let due = t.dueDate else { return false }
                return calendar.isDate(due, inSameDayAs: .now)
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var activeGoals: [PersistedGoal] {
        goals.filter { $0.status == .active }
    }

    private var pinnedNotes: [PersistedNote] {
        notes
            .filter { $0.isPinned && !$0.isArchived }
            .sorted { noteDate($0) > noteDate($1) }
    }

    private func noteDate(_ n: PersistedNote) -> Date {
        n.lastEditedAt ?? n.updatedAt
    }

    // MARK: Stats counters

    private var tasksCompletedToday: Int {
        tasks.filter { t in
            guard t.isDone == true, let at = t.completedAt else { return false }
            return calendar.isDateInToday(at)
        }.count
    }

    private var goalsProgressedToday: Int {
        goals.filter { g in
            guard g.status == .active, let at = g.lastUpdatedAt else { return false }
            return calendar.isDateInToday(at)
        }.count
    }

    private var notesToday: Int {
        notes.filter { calendar.isDateInToday($0.createdAt) }.count
    }

    private var activeStreaks: Int {
        habits.filter { !$0.isArchived && $0.streakCount > 0 }.count
    }

    var body: some View {
        let p = theme.palette
        ZStack(alignment: .top) {
            p.canvasView                                   // opaque base (was .themedCanvas)
            MetalOrbViewRepresentable(view: orbView, reduceMotion: reduceMotion)
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipped()
                .allowsHitTesting(false)
                .frame(maxHeight: .infinity, alignment: .top)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Editorial hero — "Today's Overview", date + due-count floated right.
                    Mac_DisplayTitle(
                        title: "Today's Overview",
                        metaLabel: todayMeta,
                        accentCallout: dueToday.isEmpty ? nil : "\(dueToday.count) DUE",
                        size: 80
                    )
                    .padding(.bottom, 28)

                    Mac_DailyStatsGrid(
                        tasksCompleted: tasksCompletedToday,
                        goalsProgressed: goalsProgressedToday,
                        notesCaptured: notesToday,
                        activeStreaks: activeStreaks
                    )
                    .padding(.bottom, 40)

                    if isEverythingEmpty {
                        Mac_CinematicEmpty(
                            headline: "nothing\nto show",
                            footnote: "Capture below to fill the day."
                        )
                        .padding(.top, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 30) {
                            eventsSection(p)
                            tasksSection(p)
                            goalsSection(p)
                            notesSection(p)
                            // Section 5: Routines — deferred until iOS sync confirmed.
                        }
                    }
                }
                .padding(.horizontal, 56)
                .padding(.top, 60)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { await refreshEvents() }
        .onAppear { orbView.fadeIn(duration: 1.0) }
        .onChange(of: nav.selection) { _, pane in
            if pane == .overview { Task { await refreshEvents() } }
        }
    }

    private var isEverythingEmpty: Bool {
        todaysEvents.isEmpty && dueToday.isEmpty && activeGoals.isEmpty && pinnedNotes.isEmpty
    }

    // MARK: Sections

    @ViewBuilder
    private func eventsSection(_ p: ThemePalette) -> some View {
        if !todaysEvents.isEmpty {
            section("Events · Today", p) {
                ForEach(todaysEvents, id: \.eventIdentifier) { event in
                    Mac_OverviewEvent(event: event)
                }
            }
        }
    }

    @ViewBuilder
    private func tasksSection(_ p: ThemePalette) -> some View {
        if !dueToday.isEmpty {
            section("Tasks · Due Today", p) {
                ForEach(dueToday) { task in
                    Mac_TaskRow(
                        task: task,
                        onToggleComplete: { TaskMutator.complete(task, in: modelContext) },
                        onDelete: {
                            TaskMutator.delete(task, in: modelContext)
                            try? modelContext.save()
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func goalsSection(_ p: ThemePalette) -> some View {
        if !activeGoals.isEmpty {
            section("Goals · Active", p) {
                ForEach(activeGoals) { goal in
                    Mac_CompactGoalRow(goal: goal)
                }
            }
        }
    }

    @ViewBuilder
    private func notesSection(_ p: ThemePalette) -> some View {
        if !pinnedNotes.isEmpty {
            section("Notes · Pinned", p) {
                ForEach(pinnedNotes) { note in
                    Mac_OverviewNoteRow(note: note, date: noteDate(note)) {
                        nav.selection = .notes
                    }
                }
            }
        }
    }

    /// Mini section header + its rows, in a consistent 12pt rhythm.
    @ViewBuilder
    private func section<Content: View>(_ title: String, _ p: ThemePalette,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(2.0)
                .textCase(.uppercase)
                .foregroundStyle(p.textTertiary)
            LazyVStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
    }

    // MARK: Events fetch

    private func refreshEvents() async {
        await eventKit.requestAccess()
        let fetched = eventKit.fetchWeekEvents(startingFrom: .now)
            .filter { calendar.isDate($0.startDate, inSameDayAs: .now) }
            .sorted { $0.startDate < $1.startDate }
        todaysEvents = fetched
    }

    private var todayMeta: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased()
    }
}

// MARK: - Mac_DailyStatsGrid
//
// 2×2 glance grid. Mint number, Space Mono ALL CAPS label. Card surface
// background with hairline border, 12pt radius. Compact — not dominant.

struct Mac_DailyStatsGrid: View {
    @Environment(ThemeStore.self) private var theme
    let tasksCompleted: Int
    let goalsProgressed: Int
    let notesCaptured: Int
    let activeStreaks: Int

    var body: some View {
        let p = theme.palette
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                statCell(value: tasksCompleted, label: "Tasks Done", p)
                statCell(value: goalsProgressed, label: "Goals", p)
            }
            GridRow {
                statCell(value: notesCaptured, label: "Notes", p)
                statCell(value: activeStreaks, label: "Streaks", p)
            }
        }
    }

    private func statCell(value: Int, label: String, _ p: ThemePalette) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(value)")
                .font(.system(size: 32, weight: .heavy, design: p.fontDesign))
                .foregroundStyle(Mac_Accent.mint)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(p.textPrimary.opacity(0.28))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(p.chromeSurface))
        .overlay(shape.strokeBorder(p.hairline, lineWidth: 1))
        .clipShape(shape)
    }
}

// MARK: - Mac_OverviewEvent
//
// A single calendar event in the Overview digest: a 2pt rail in the source
// calendar's own color, the title, and a Space-Mono time range (or "All Day").
// Read-only — events are edited in Calendar.app, never inline.

struct Mac_OverviewEvent: View {
    @Environment(ThemeStore.self) private var theme
    let event: EKEvent

    var body: some View {
        let p = theme.palette
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
        HStack(spacing: 0) {
            Rectangle()
                .fill(railColor)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 5) {
                Text(timeText)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .monospacedDigit()
                    .foregroundStyle(p.textTertiary)
                Text(event.title?.isEmpty == false ? event.title : "Untitled Event")
                    .font(.system(size: 14, weight: .medium, design: p.fontDesign))
                    .tracking(p.headlineTracking)
                    .foregroundStyle(p.textPrimary)
                    .lineLimit(1)
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 52)
        .background(shape.fill(p.rowFill))
        .overlay(shape.strokeBorder(p.hairline, lineWidth: 1))
        .clipShape(shape)
    }

    /// The source calendar's own tint (EventKit guarantees a non-nil cgColor).
    private var railColor: Color {
        if let cg = event.calendar?.cgColor { return Color(cgColor: cg) }
        return Mac_Accent.mint
    }

    private var timeText: String {
        if event.isAllDay { return "All Day" }
        let style = Date.FormatStyle.dateTime.hour().minute()
        return "\(event.startDate.formatted(style)) – \(event.endDate.formatted(style))"
    }
}

// MARK: - Mac_CompactGoalRow
//
// A read-only goal preview for the Overview: title, a hairline-track 3pt
// progress bar with a mint fill, and a "current of target" meta line. No
// increment affordance here — that lives in the Goals pane.

struct Mac_CompactGoalRow: View {
    @Environment(ThemeStore.self) private var theme
    let goal: PersistedGoal

    private var clamped: CGFloat { max(0, min(1, CGFloat(goal.progress))) }

    var body: some View {
        let p = theme.palette
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
        VStack(alignment: .leading, spacing: 9) {
            Text(goal.title.isEmpty ? "Untitled" : goal.title)
                .font(.system(size: 14, weight: .medium, design: p.fontDesign))
                .tracking(p.headlineTracking)
                .foregroundStyle(p.textPrimary)
                .lineLimit(1)

            ZStack(alignment: .leading) {
                Capsule().fill(p.hairline)
                Capsule()
                    .fill(Mac_Accent.mint)
                    .scaleEffect(x: clamped, anchor: .leading)
            }
            .frame(height: 3)

            Text(metaText)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .textCase(.uppercase)
                .monospacedDigit()
                .foregroundStyle(p.textTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(p.rowFill))
        .overlay(shape.strokeBorder(p.hairline, lineWidth: 1))
        .clipShape(shape)
    }

    private var metaText: String {
        let current = goal.currentValue.rounded() == goal.currentValue
            ? String(Int(goal.currentValue))
            : String(format: "%.1f", goal.currentValue)
        return "\(current) of \(goal.targetText)"
    }
}

// MARK: - Mac_OverviewNoteRow
//
// A pinned note in the Overview digest: a 2pt mint accent mark, the title, and
// a Space-Mono edited-date. Clicking jumps to the Notes pane.

struct Mac_OverviewNoteRow: View {
    @Environment(ThemeStore.self) private var theme
    let note: PersistedNote
    let date: Date
    var onOpen: () -> Void

    @State private var hovering = false

    var body: some View {
        let p = theme.palette
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
        Button(action: onOpen) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Mac_Accent.mint)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                HStack(spacing: 12) {
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .font(.system(size: 14, weight: .medium, design: p.fontDesign))
                        .tracking(p.headlineTracking)
                        .foregroundStyle(p.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .monospacedDigit()
                        .foregroundStyle(p.textTertiary)
                }
                .padding(.leading, 16)
                .padding(.trailing, 14)
                .padding(.vertical, 12)
            }
            .frame(minHeight: 48)
            .background(shape.fill(hovering ? p.chromeSurface : p.rowFill))
            .overlay(shape.strokeBorder(p.hairline, lineWidth: 1))
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
