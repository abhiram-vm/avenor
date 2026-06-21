import SwiftUI
import SwiftData
import EventKit

// MARK: - CalendarViewMode

enum CalendarViewMode: String, CaseIterable, Identifiable {
    case week, list
    var id: String { rawValue }
}

// MARK: - Mac_CalendarPane
//
// The Calendar context layer: this week's EventKit events shown alongside the
// tasks due each day. Read + create only — editing happens in Calendar.app
// (double-click an event to deep-link out). Events are created from the capture
// bar, not here.
//
// The pane owns the shared `EventKitService`, requests access once on first
// appearance, and re-fetches whenever the visible week changes. Tasks come from
// a read-only `@Query`; events from EventKit. Nothing here mutates SwiftData.

struct Mac_CalendarPane: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var allTasks: [PersistedTask]

    @State private var eventKit = EventKitService.shared
    @State private var currentWeekStart: Date = Mac_CalendarPane.mondayOfCurrentWeek()
    @State private var viewMode: CalendarViewMode = .week
    @State private var events: [EKEvent] = []

    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        let p = theme.palette
        VStack(spacing: 0) {
            toolbar(p)
            Divider().overlay(p.hairline)

            if eventKit.accessDenied {
                accessDeniedState(p)
            } else {
                switch viewMode {
                case .week:
                    Mac_WeekView(
                        days: weekDays,
                        eventsByDay: eventsByDay,
                        tasksByDay: tasksByDay,
                        onOpenEvent: { eventKit.openInCalendarApp(event: $0) }
                    )
                case .list:
                    Mac_CalendarListView(
                        days: weekDays,
                        eventsByDay: eventsByDay,
                        tasksByDay: tasksByDay,
                        onOpenEvent: { eventKit.openInCalendarApp(event: $0) }
                    )
                }
            }
        }
        .themedCanvas(p)
        .task(id: currentWeekStart) {
            await eventKit.requestAccess()
            reload()
        }
    }

    // MARK: Toolbar

    private func toolbar(_ p: ThemePalette) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(monthLabel)
                    .font(.system(size: 30, weight: .heavy, design: p.fontDesign))
                    .tracking(-1.2)
                    .foregroundStyle(p.textPrimary)
                Text(weekLabel)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(2.0)
                    .textCase(.uppercase)
                    .foregroundStyle(p.textTertiary)
            }

            Spacer(minLength: 0)

            // Previous / next week.
            HStack(spacing: 4) {
                chevron("chevron.left", p) { shiftWeek(-1) }
                    .keyboardShortcut("[", modifiers: .command)
                    .help("Previous Week (⌘[)")
                Button { currentWeekStart = Self.mondayOfCurrentWeek() } label: {
                    Text("Today")
                        .font(p.font(.micro))
                        .tracking(p.microTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(isThisWeek ? p.textTertiary : Mac_Accent.mint)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                                .fill(p.chromeSurface)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isThisWeek)
                chevron("chevron.right", p) { shiftWeek(1) }
                    .keyboardShortcut("]", modifiers: .command)
                    .help("Next Week (⌘])")
            }

            // Week / list toggle.
            Button {
                if reduceMotion {
                    viewMode = viewMode == .week ? .list : .week
                } else {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        viewMode = viewMode == .week ? .list : .week
                    }
                }
            } label: {
                Image(systemName: viewMode == .week ? "list.bullet" : "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(p.textSecondary)
                    .frame(width: 30, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                            .fill(p.chromeSurface)
                    )
            }
            .buttonStyle(.plain)
            .help(viewMode == .week ? "List View" : "Week View")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func chevron(_ symbol: String, _ p: ThemePalette, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(p.textSecondary)
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                        .fill(p.chromeSurface)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Access-denied state

    private func accessDeniedState(_ p: ThemePalette) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Mac_Accent.mint)
            VStack(spacing: 6) {
                Text("Calendar access required")
                    .font(p.font(.headline))
                    .foregroundStyle(p.textPrimary)
                Text("Enable in System Settings → Privacy → Calendars.")
                    .font(p.font(.body))
                    .foregroundStyle(p.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("Open System Settings")
                    .font(p.font(.body))
                    .foregroundStyle(p.textPrimary)
                    .padding(.horizontal, 16)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                            .fill(p.chromeSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                            .strokeBorder(p.prominent, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Data

    private func reload() {
        events = eventKit.fetchWeekEvents(startingFrom: currentWeekStart)
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: currentWeekStart) }
    }

    /// Events grouped by the start-of-day they begin on.
    private var eventsByDay: [Date: [EKEvent]] {
        Dictionary(grouping: events) { calendar.startOfDay(for: $0.startDate) }
    }

    /// Open tasks with a due date inside the visible week, grouped by day.
    private var tasksByDay: [Date: [PersistedTask]] {
        let weekSet = Set(weekDays.map { calendar.startOfDay(for: $0) })
        let dated = allTasks.filter { task in
            guard !(task.isDone ?? false), let due = task.dueDate else { return false }
            return weekSet.contains(calendar.startOfDay(for: due))
        }
        return Dictionary(grouping: dated) { calendar.startOfDay(for: $0.dueDate ?? .now) }
    }

    private func shiftWeek(_ direction: Int) {
        if let d = calendar.date(byAdding: .day, value: 7 * direction, to: currentWeekStart) {
            currentWeekStart = calendar.startOfDay(for: d)
        }
    }

    private var isThisWeek: Bool {
        calendar.isDate(currentWeekStart, inSameDayAs: Self.mondayOfCurrentWeek())
    }

    private var weekLabel: String {
        guard let end = calendar.date(byAdding: .day, value: 6, to: currentWeekStart) else { return "" }
        let start = currentWeekStart.formatted(.dateTime.month(.abbreviated).day())
        let endStr = end.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(endStr)"
    }

    /// Editorial hero label — the month(s) the visible week spans.
    private var monthLabel: String {
        guard let end = calendar.date(byAdding: .day, value: 6, to: currentWeekStart) else { return "Calendar" }
        let startMonth = currentWeekStart.formatted(.dateTime.month(.wide))
        let endMonth = end.formatted(.dateTime.month(.wide))
        if startMonth == endMonth { return startMonth }
        let startAbbr = currentWeekStart.formatted(.dateTime.month(.abbreviated))
        let endAbbr = end.formatted(.dateTime.month(.abbreviated))
        return "\(startAbbr) / \(endAbbr)"
    }

    /// Monday of the week containing today. Calendar weeks vary by locale, so we
    /// anchor explicitly on Monday (weekday 2) regardless of the locale's first
    /// weekday, matching the spec.
    static func mondayOfCurrentWeek(now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today) // 1=Sun…7=Sat
        let delta = (weekday == 1) ? -6 : (2 - weekday) // back up to Monday
        return calendar.date(byAdding: .day, value: delta, to: today) ?? today
    }
}

// MARK: - Shared calendar helpers
//
// Small view-layer utilities shared by the week and list views. Kept here
// (rather than a fifth file) so the Calendar pane stays a tight 4-file set.

enum CalendarUI {

    /// SwiftUI color for an EKCalendar's native color. Event colors come from
    /// the user's calendars (per the spec) — every OTHER color reads from the
    /// active `ThemePalette`.
    static func color(for cal: EKCalendar?) -> Color {
        guard let cg = cal?.cgColor else { return Mac_Accent.mint }
        return Color(cgColor: cg)
    }

    /// "2:00 – 3:00 PM". The start drops the AM/PM marker when it matches the
    /// end's, so the period prints once at the tail.
    static func timeRange(_ event: EKEvent) -> String {
        let start = event.startDate.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
        let end = event.endDate.formatted(.dateTime.hour().minute())
        return "\(start) – \(end)"
    }
}

// MARK: - Mac_CalTaskRow
//
// "Tasks due that day" row — a small square checkbox glyph + the task title.
// Display-only at this stage (no completion interaction), shared by both views.

struct Mac_CalTaskRow: View {
    @Environment(ThemeStore.self) private var theme
    let task: PersistedTask

    var body: some View {
        let p = theme.palette
        HStack(spacing: 7) {
            Image(systemName: "square")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(p.textTertiary)
            Text(task.title.isEmpty ? "Untitled" : task.title)
                .font(.system(size: 12, weight: .regular, design: p.fontDesign))
                .foregroundStyle(p.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}
