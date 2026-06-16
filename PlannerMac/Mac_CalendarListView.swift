import SwiftUI
import SwiftData
import EventKit

// MARK: - Mac_CalendarListView
//
// The chronological fallback to the week grid: the week's events as a single
// scrolling column, grouped under day section headers, with each day's due
// tasks beneath its events. Same double-click-to-open behavior as the week
// view.
//
// Built with `ScrollView + LazyVStack` and pinned section headers rather than a
// native `List` — CLAUDE.md prohibits native `List` (it can't carry the Stark
// accent or theme cleanly across all four palettes), and this matches every
// other Mac pane.

struct Mac_CalendarListView: View {
    @Environment(ThemeStore.self) private var theme

    let days: [Date]
    let eventsByDay: [Date: [EKEvent]]
    let tasksByDay: [Date: [PersistedTask]]
    var onOpenEvent: (EKEvent) -> Void

    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        let p = theme.palette
        if isEmpty {
            StarkEmptyState("Nothing this week.", footnote: "Capture an event like “lunch friday 1pm”.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(populatedDays, id: \.self) { day in
                        Section {
                            daySection(day, palette: p)
                        } header: {
                            sectionHeader(day, palette: p)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Section header

    private func sectionHeader(_ day: Date, palette p: ThemePalette) -> some View {
        let isToday = calendar.isDateInToday(day)
        let label = day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased()
        return HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(p.microTracking + 0.4)
                .foregroundStyle(isToday ? Mac_Accent.mint : p.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .background(p.canvasView)
    }

    // MARK: Day section body

    private func daySection(_ day: Date, palette p: ThemePalette) -> some View {
        let dayStart = calendar.startOfDay(for: day)
        let events = (eventsByDay[dayStart] ?? []).sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            return lhs.startDate < rhs.startDate
        }
        let tasks = tasksByDay[dayStart] ?? []

        return VStack(alignment: .leading, spacing: 8) {
            ForEach(events, id: \.self) { event in
                eventRow(event, palette: p)
            }
            if !tasks.isEmpty {
                ForEach(tasks) { task in
                    Mac_CalTaskRow(task: task)
                        .padding(.leading, 2)
                }
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: Event row

    private func eventRow(_ event: EKEvent, palette p: ThemePalette) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(CalendarUI.color(for: event.calendar))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title ?? "Untitled")
                    .font(.system(size: 14, weight: .medium, design: p.fontDesign))
                    .foregroundStyle(p.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(event.isAllDay ? "All day" : CalendarUI.timeRange(event))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(p.textTertiary)
                    if let name = event.calendar?.title {
                        Text(name)
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(p.textTertiary.opacity(0.8))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpenEvent(event) }
        .help("Double-click to open in Calendar")
    }

    // MARK: Derived

    /// Days that have at least one event or task — empty days are skipped so the
    /// list stays dense.
    private var populatedDays: [Date] {
        days.filter { day in
            let s = calendar.startOfDay(for: day)
            return !(eventsByDay[s] ?? []).isEmpty || !(tasksByDay[s] ?? []).isEmpty
        }
    }

    private var isEmpty: Bool { populatedDays.isEmpty }
}
