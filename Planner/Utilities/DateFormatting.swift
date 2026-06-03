import Foundation

// MARK: - Date formatting utilities
//
// Extracted from `TaskRow` and `CalendarTabView`. Cached `DateFormatter`s
// avoid the per-call allocation that the previous implementation incurred
// (formatters are surprisingly expensive to construct). All formatters are
// locale-aware and respect the user's calendar.

enum TaskDateFormatter {
    private static let calendar = Calendar.autoupdatingCurrent

    private static let timeOfDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.calendar = calendar
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f
    }()

    private static let dateAndTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.calendar = calendar
        f.setLocalizedDateFormatFromTemplate("MMMd jmm")
        return f
    }()

    private static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.calendar = calendar
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()

    /// Friendly relative phrasing for reminder due dates.
    /// `today at 4:30 PM`, `tomorrow at 9:00 AM`, or `Mar 4, 2:15 PM`.
    static func friendlyDue(_ date: Date) -> String {
        if calendar.isDateInToday(date) {
            return "today at \(timeOfDay.string(from: date))"
        } else if calendar.isDateInTomorrow(date) {
            return "tomorrow at \(timeOfDay.string(from: date))"
        } else {
            return dateAndTime.string(from: date)
        }
    }

    /// `Mar 4` or `Mar 4–Mar 9` for a date range. Collapses to a single
    /// component when start and end are the same calendar day.
    static func range(_ start: Date, _ end: Date) -> String {
        let s = monthDay.string(from: start)
        if calendar.isDate(start, inSameDayAs: end) { return s }
        let e = monthDay.string(from: end)
        return "\(s)–\(e)"
    }
}

// MARK: - Calendar grid

enum CalendarFormatter {
    private static let calendar = Calendar.autoupdatingCurrent

    private static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.calendar = calendar
        f.setLocalizedDateFormatFromTemplate("LLLLyyyy")
        return f
    }()

    private static let weekdayMonthDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.calendar = calendar
        f.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return f
    }()

    static func monthTitle(_ date: Date) -> String {
        monthYear.string(from: date)
    }

    static func dayTitle(_ date: Date) -> String {
        weekdayMonthDay.string(from: date)
    }

    /// 6 weeks (42 cells) covering the month containing `date`, padded with
    /// leading and trailing days from neighboring months so the grid is
    /// always full. Honors the user's `firstWeekday`.
    static func monthGrid(containing date: Date) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [] }
        let firstOfMonth = monthInterval.start
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leading, to: firstOfMonth) ?? firstOfMonth
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }
}
