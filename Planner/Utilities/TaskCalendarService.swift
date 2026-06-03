import Foundation

// MARK: - TaskCalendarService
//
// Pure logic layer. Operates on any sequence of `PersistedTask` and exposes
// the same three "what is on this day" queries that `AppStore` used to embed.
// Free of SwiftUI / SwiftData dependencies so it's reusable from widgets,
// notification scheduling, and unit tests.

struct TaskCalendarService {
    var calendar: Calendar = .autoupdatingCurrent

    /// Tasks whose `dueDate` falls on the same calendar day as `day`.
    func tasksDue<S: Sequence>(on day: Date, in tasks: S) -> [PersistedTask] where S.Element == PersistedTask {
        tasks.filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: day)
        }
    }

    /// Tasks whose `[startDate, endDate]` range overlaps `day`. Treats end as
    /// inclusive (extends to end-of-day) to match user expectation that a
    /// task ending "Mar 9" is still active on Mar 9.
    func tasksActive<S: Sequence>(on day: Date, in tasks: S) -> [PersistedTask] where S.Element == PersistedTask {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        return tasks.filter { task in
            guard let start = task.startDate, let end = task.endDate else { return false }
            let s = calendar.startOfDay(for: start)
            let eExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
            return s < dayEnd && eExclusive > dayStart
        }
    }

    /// The combined "what should appear in the calendar tab on this day" list:
    /// active tasks first, then due-only tasks (deduped against active).
    func tasksForCalendar<S: Sequence>(on day: Date, in tasks: S) -> [PersistedTask] where S.Element == PersistedTask {
        let materialized = Array(tasks)
        let active = tasksActive(on: day, in: materialized)
        let activeIDs = Set(active.map(\.id))
        let due = tasksDue(on: day, in: materialized).filter { !activeIDs.contains($0.id) }
        return active + due
    }
}
