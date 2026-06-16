import SwiftUI
import SwiftData
import EventKit

// MARK: - Mac_WeekView
//
// Seven day-columns side by side, the Calendar pane's hero. Each column shows
// (top → bottom): a date header with today flagged in mint, all-day events,
// timed event cards in the calendar's native color, then the tasks due that
// day beneath a hairline. Double-click any event to open it in Calendar.app.

struct Mac_WeekView: View {
    @Environment(ThemeStore.self) private var theme

    let days: [Date]
    let eventsByDay: [Date: [EKEvent]]
    let tasksByDay: [Date: [PersistedTask]]
    var onOpenEvent: (EKEvent) -> Void

    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        let p = theme.palette
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                    dayColumn(day, palette: p)
                    if index < days.count - 1 {
                        Rectangle().fill(p.hairline).frame(width: 0.5)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Day column

    private func dayColumn(_ day: Date, palette p: ThemePalette) -> some View {
        let dayStart = calendar.startOfDay(for: day)
        let dayEvents = eventsByDay[dayStart] ?? []
        let allDay = dayEvents.filter { $0.isAllDay }
        let timed = dayEvents.filter { !$0.isAllDay }
        let tasks = tasksByDay[dayStart] ?? []

        return VStack(alignment: .leading, spacing: 8) {
            dayHeader(day, palette: p)

            ForEach(allDay, id: \.self) { event in
                allDayCard(event, palette: p)
            }

            ForEach(timed, id: \.self) { event in
                eventCard(event, palette: p)
            }

            if !tasks.isEmpty {
                if !dayEvents.isEmpty {
                    Rectangle().fill(p.hairline).frame(height: 0.5).padding(.vertical, 2)
                }
                ForEach(tasks) { task in
                    Mac_CalTaskRow(task: task)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Header

    private func dayHeader(_ day: Date, palette p: ThemePalette) -> some View {
        let isToday = calendar.isDateInToday(day)
        let dayName = day.formatted(.dateTime.weekday(.abbreviated)).uppercased()
        let dayNum = calendar.component(.day, from: day)

        return VStack(alignment: .leading, spacing: 4) {
            Text(dayName)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(p.microTracking)
                .foregroundStyle(p.textTertiary)

            Text("\(dayNum)")
                .font(.system(size: 20, weight: .medium, design: p.fontDesign))
                .monospacedDigit()
                .foregroundStyle(isToday ? canvasInk(p) : p.textSecondary)
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(isToday ? Mac_Accent.mint : Color.clear)
                )
        }
        .padding(.bottom, 4)
    }

    /// Readable ink to sit on top of the mint "today" circle across all themes.
    private func canvasInk(_ p: ThemePalette) -> Color {
        switch p.id {
        case .dark, .liquidGlass: return DesignTokens.Surface.canvas
        case .light, .calmEarth:  return DesignTokens.Surface.canvas
        }
    }

    // MARK: Event cards

    private func eventCard(_ event: EKEvent, palette p: ThemePalette) -> some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
        return HStack(spacing: 0) {
            Rectangle()
                .fill(CalendarUI.color(for: event.calendar))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title ?? "Untitled")
                    .font(.system(size: 13, weight: .medium, design: p.fontDesign))
                    .foregroundStyle(p.textPrimary)
                    .lineLimit(1)
                Text(CalendarUI.timeRange(event))
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .tracking(p.microTracking)
                    .foregroundStyle(p.textTertiary)
                    .lineLimit(1)
            }
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .padding(.vertical, 7)
            Spacer(minLength: 0)
        }
        .background(shape.fill(p.rowFill))
        .overlay(shape.strokeBorder(p.hairline, lineWidth: 1))
        .clipShape(shape)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpenEvent(event) }
        .help("Double-click to open in Calendar")
    }

    private func allDayCard(_ event: EKEvent, palette p: ThemePalette) -> some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
        return HStack(spacing: 0) {
            Rectangle()
                .fill(CalendarUI.color(for: event.calendar))
                .frame(width: 2)
            Text(event.title ?? "Untitled")
                .font(.system(size: 12, weight: .medium, design: p.fontDesign))
                .foregroundStyle(p.textPrimary)
                .lineLimit(1)
                .padding(.leading, 8)
                .padding(.trailing, 8)
                .padding(.vertical, 6)
            Spacer(minLength: 0)
        }
        .background(shape.fill(p.chromeSurface))
        .overlay(shape.strokeBorder(p.hairline, lineWidth: 1))
        .clipShape(shape)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpenEvent(event) }
        .help("Double-click to open in Calendar")
    }
}
