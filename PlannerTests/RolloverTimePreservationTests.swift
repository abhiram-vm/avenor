// RolloverTimePreservationTests.swift
// PlannerTests
//
// TEST STRATEGY 1 — Smart Rollover & Time-Preservation
//
// Verifies that LifecycleAutomation.rollForwardTasks(_:to:in:) advances the
// calendar day without disturbing the task's original wall-clock time. A task
// due yesterday at 4:15 PM must land on the target day still at 4:15 PM —
// never flattened to midnight or any other sentinel time.

import XCTest
import SwiftData
@testable import Avenor

@MainActor
final class RolloverTimePreservationTests: XCTestCase {

    // MARK: Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([PersistedTask.self, PersistedNote.self, PersistedGoal.self, PersistedHabit.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Builds a fixed date: today + dayOffset at the given hour:minute.
    private func makeDate(dayOffset: Int, hour: Int, minute: Int,
                          calendar: Calendar = .current) -> Date {
        let base = calendar.startOfDay(for: .now)
        let day  = calendar.date(byAdding: .day, value: dayOffset, to: base)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    // MARK: - 1a: Wall-clock time is preserved on roll-to-today

    func test_rollToToday_preservesClockTime() throws {
        let container = try makeContainer()
        let context   = container.mainContext
        let calendar  = Calendar.current

        // Yesterday at 4:15 PM — the canonical Action Debt scenario.
        let originalDue = makeDate(dayOffset: -1, hour: 16, minute: 15)
        let task = PersistedTask(title: "Quarterly review", type: .todo, dueDate: originalDue)
        context.insert(task)
        try context.save()

        LifecycleAutomation.rollForwardTasks([task], to: .now, in: context, calendar: calendar)

        let newDue = try XCTUnwrap(task.dueDate, "dueDate must be non-nil after rollover")

        // Calendar day must be today.
        XCTAssertTrue(calendar.isDateInToday(newDue),
                      "Rolled date must land on today; got \(newDue)")

        // Clock components must be 4:15 PM — NOT midnight or any sentinel.
        XCTAssertEqual(calendar.component(.hour,   from: newDue), 16,
                       "Hour must be preserved as 16 (4 PM)")
        XCTAssertEqual(calendar.component(.minute, from: newDue), 15,
                       "Minute must be preserved as 15")
    }

    // MARK: - 1b: Roll-to-tomorrow also preserves clock time

    func test_rollToTomorrow_preservesClockTime() throws {
        let container = try makeContainer()
        let context   = container.mainContext
        let calendar  = Calendar.current

        let originalDue = makeDate(dayOffset: -3, hour: 9, minute: 45)
        let task = PersistedTask(title: "Budget call", type: .reminder, dueDate: originalDue)
        context.insert(task)
        try context.save()

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!
        LifecycleAutomation.rollForwardTasks([task], to: tomorrow, in: context, calendar: calendar)

        let newDue = try XCTUnwrap(task.dueDate)
        XCTAssertEqual(calendar.startOfDay(for: newDue),
                       calendar.startOfDay(for: tomorrow),
                       "Date must be tomorrow")
        XCTAssertEqual(calendar.component(.hour,   from: newDue), 9)
        XCTAssertEqual(calendar.component(.minute, from: newDue), 45)
    }

    // MARK: - 1c: Task with no dueDate lands at startOfDay (no phantom time injected)

    func test_rollWithNoDueDate_landsAtStartOfDay() throws {
        let container = try makeContainer()
        let context   = container.mainContext
        let calendar  = Calendar.current

        let task = PersistedTask(title: "Undated orphan", type: .todo)
        context.insert(task)
        try context.save()

        LifecycleAutomation.rollForwardTasks([task], to: .now, in: context, calendar: calendar)

        let newDue = try XCTUnwrap(task.dueDate, "Undated task must receive a dueDate after rollover")
        XCTAssertEqual(calendar.startOfDay(for: newDue),
                       calendar.startOfDay(for: .now),
                       "Undated task must land at startOfDay of the target")
    }

    // MARK: - 1d: updatedAt is stamped after the roll

    func test_roll_bumpsUpdatedAt() throws {
        let container  = try makeContainer()
        let context    = container.mainContext
        let calendar   = Calendar.current
        let beforeRoll = Date.now

        let task = PersistedTask(title: "Stand-up", type: .reminder,
                                 dueDate: makeDate(dayOffset: -1, hour: 8, minute: 0))
        context.insert(task)
        try context.save()

        LifecycleAutomation.rollForwardTasks([task], to: .now, in: context, calendar: calendar)

        XCTAssertGreaterThan(task.updatedAt, beforeRoll,
                             "updatedAt must be stamped after the roll")
    }

    // MARK: - 1e: Batch roll is atomic — all tasks update, none skipped

    func test_batchRoll_allTasksUpdateTogether() throws {
        let container = try makeContainer()
        let context   = container.mainContext
        let calendar  = Calendar.current

        let batch = [
            PersistedTask(title: "T1", type: .todo,
                          dueDate: makeDate(dayOffset: -1, hour: 7,  minute: 30)),
            PersistedTask(title: "T2", type: .reminder,
                          dueDate: makeDate(dayOffset: -2, hour: 14, minute: 0)),
            PersistedTask(title: "T3", type: .todo,
                          dueDate: makeDate(dayOffset: -3, hour: 23, minute: 59)),
        ]
        batch.forEach { context.insert($0) }
        try context.save()

        LifecycleAutomation.rollForwardTasks(batch, to: .now, in: context, calendar: calendar)

        for task in batch {
            let due = try XCTUnwrap(task.dueDate, "\(task.title) must have dueDate post-roll")
            XCTAssertTrue(calendar.isDateInToday(due), "\(task.title) must land on today")
        }

        // Per-task clock fidelity.
        let expected = [(7, 30), (14, 0), (23, 59)]
        for (index, (h, m)) in expected.enumerated() {
            let due = batch[index].dueDate!
            XCTAssertEqual(calendar.component(.hour,   from: due), h,
                           "\(batch[index].title): hour mismatch")
            XCTAssertEqual(calendar.component(.minute, from: due), m,
                           "\(batch[index].title): minute mismatch")
        }
    }

    // MARK: - 1f: outstandingActionDebt excludes ideas and completed tasks

    func test_actionDebt_excludesIdeasAndCompletedTasks() throws {
        let container = try makeContainer()
        let context   = container.mainContext
        let calendar  = Calendar.current

        let yesterday = makeDate(dayOffset: -1, hour: 10, minute: 0)

        let openTodo      = PersistedTask(title: "Open todo",      type: .todo,
                                          isDone: false, dueDate: yesterday)
        let completedTodo = PersistedTask(title: "Done todo",       type: .todo,
                                          isDone: true,  dueDate: yesterday)
        let staleIdea     = PersistedTask(title: "Old idea",        type: .idea,
                                          dueDate: yesterday)
        let openReminder  = PersistedTask(title: "Open reminder",   type: .reminder,
                                          isDone: false, dueDate: yesterday)

        [openTodo, completedTodo, staleIdea, openReminder].forEach { context.insert($0) }
        try context.save()

        let debt = LifecycleAutomation.outstandingActionDebt(
            in: context, asOf: .now, calendar: calendar)

        XCTAssertEqual(debt.count, 2,
                       "Debt must contain exactly the 2 open actionable tasks")
        XCTAssertTrue(debt.contains(where: { $0.title == "Open todo" }))
        XCTAssertTrue(debt.contains(where: { $0.title == "Open reminder" }))
        XCTAssertFalse(debt.contains(where: { $0.title == "Done todo" }),
                       "Completed tasks must not appear in debt")
        XCTAssertFalse(debt.contains(where: { $0.title == "Old idea" }),
                       "Ideas must not appear in debt (they marinate, not accrue debt)")
    }
}
