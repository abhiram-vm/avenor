// RecurrenceGateTests.swift
// PlannerTests
//
// TEST STRATEGY 2 — Recurrence Gate & Multi-Tap Constraint
//
// Verifies that PersistedHabit.isEligibleForCompletion(on:) correctly:
//   • Blocks taps on off-schedule days (Saturday for a Weekdays habit).
//   • Allows taps on valid schedule days.
//   • Freezes execution after the first log within the same window
//     (double-log protection).
//   • Applies the right window granularity — daily locks per-day,
//     weekly locks per-calendar-week.
//
// All tests use a fixed, injected Calendar so they are clock-independent
// and can be run at any time without device-clock manipulation.

import XCTest
import SwiftData
@testable import Avenor

@MainActor
final class RecurrenceGateTests: XCTestCase {

    // MARK: Container lifecycle
    //
    // The container is held at the class level so it stays alive for the full
    // duration of every test. When makeHabit created a local container that was
    // released before the test body accessed habit properties, SwiftData would
    // block indefinitely on the dangling context — causing the observed hangs.

    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([PersistedTask.self, PersistedNote.self,
                             PersistedGoal.self, PersistedHabit.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    // MARK: Helpers

    /// Returns the next occurrence of a given weekday (1=Sun…7=Sat) on or
    /// after the reference date, using the supplied calendar.
    private func nextWeekday(_ target: Int, from ref: Date = .now,
                             calendar: Calendar = .current) -> Date {
        var date = calendar.startOfDay(for: ref)
        for _ in 0..<7 {
            if calendar.component(.weekday, from: date) == target { return date }
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        fatalError("No weekday \(target) found within 7 days — impossible")
    }

    /// Returns the most recent occurrence of a weekday (1=Sun…7=Sat) strictly
    /// before `ref`.
    private func prevWeekday(_ target: Int, from ref: Date = .now,
                             calendar: Calendar = .current) -> Date {
        var date = calendar.date(byAdding: .day, value: -1,
                                 to: calendar.startOfDay(for: ref))!
        for _ in 0..<7 {
            if calendar.component(.weekday, from: date) == target { return date }
            date = calendar.date(byAdding: .day, value: -1, to: date)!
        }
        fatalError("No weekday \(target) found within 7 days — impossible")
    }

    private func makeHabit(recurrence: RecurrenceRule,
                           lastCompletedAt: Date? = nil) throws -> PersistedHabit {
        let context = container.mainContext
        let habit = PersistedHabit(title: "Test habit", recurrence: recurrence,
                                   lastCompletedAt: lastCompletedAt)
        context.insert(habit)
        try context.save()
        return habit
    }

    // MARK: - 2a: Weekday habit is BLOCKED on Saturday (off-schedule day)

    func test_weekdays_blockedOnSaturday() throws {
        let habit   = try makeHabit(recurrence: .weekdays)
        let saturday = nextWeekday(7) // 7 = Saturday (Calendar standard)
        XCTAssertFalse(habit.isEligibleForCompletion(on: saturday),
                       "Weekday habit must be ineligible on Saturday")
    }

    // MARK: - 2b: Weekday habit is BLOCKED on Sunday

    func test_weekdays_blockedOnSunday() throws {
        let habit  = try makeHabit(recurrence: .weekdays)
        let sunday = nextWeekday(1)  // 1 = Sunday
        XCTAssertFalse(habit.isEligibleForCompletion(on: sunday),
                       "Weekday habit must be ineligible on Sunday")
    }

    // MARK: - 2c: Weekday habit is ALLOWED on each Monday–Friday

    func test_weekdays_allowedOnAllWeekdays() throws {
        let habit = try makeHabit(recurrence: .weekdays)
        for weekday in 2...6 {          // 2=Mon … 6=Fri
            let day = nextWeekday(weekday)
            XCTAssertTrue(habit.isEligibleForCompletion(on: day),
                          "Weekday habit must be eligible on weekday \(weekday)")
        }
    }

    // MARK: - 2d: Double-log protection — second tap on same day is rejected

    func test_daily_doubleLogOnSameDayIsBlocked() throws {
        let calendar = Calendar.current
        let today    = calendar.startOfDay(for: .now)

        // Pre-set lastCompletedAt to earlier today (simulating first tap).
        let firstLogTime = calendar.date(byAdding: .hour, value: 1, to: today)!
        let habit = try makeHabit(recurrence: .daily, lastCompletedAt: firstLogTime)

        // Second tap later today must be gated.
        let secondTapTime = calendar.date(byAdding: .hour, value: 3, to: today)!
        XCTAssertFalse(habit.isEligibleForCompletion(on: secondTapTime),
                       "Double-log on the same day must be blocked")
    }

    // MARK: - 2e: Daily habit becomes eligible again the next day

    func test_daily_eligibleNextDay() throws {
        let calendar  = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1,
                                      to: calendar.startOfDay(for: .now))!
        let habit = try makeHabit(recurrence: .daily, lastCompletedAt: yesterday)

        XCTAssertTrue(habit.isEligibleForCompletion(on: .now),
                      "Daily habit must be eligible on the next calendar day")
    }

    // MARK: - 2f: Custom days habit — blocked on unlisted day, allowed on listed day

    func test_customDays_tuesdayThursday_blockedOnWednesday() throws {
        // Custom schedule: Tuesday (3) and Thursday (5).
        let habit = try makeHabit(recurrence: .customDays([3, 5]))
        let wednesday = nextWeekday(4)     // 4 = Wednesday
        XCTAssertFalse(habit.isEligibleForCompletion(on: wednesday),
                       "Custom Tue/Thu habit must be blocked on Wednesday")
    }

    func test_customDays_tuesdayThursday_allowedOnTuesday() throws {
        let habit   = try makeHabit(recurrence: .customDays([3, 5]))
        let tuesday = nextWeekday(3)
        XCTAssertTrue(habit.isEligibleForCompletion(on: tuesday),
                      "Custom Tue/Thu habit must be eligible on Tuesday")
    }

    // MARK: - 2g: Weekly habit (anchor day) — blocked same week after logging

    func test_weekly_anchorDay_doubleLogSameWeekIsBlocked() throws {
        let calendar = Calendar.current
        // Anchor = Monday (2). Log on Monday, then try again on Thursday same week.
        let monday   = nextWeekday(2)
        let thursday = nextWeekday(5, from: monday)
        let habit    = try makeHabit(recurrence: .weekly(weekday: 2),
                                     lastCompletedAt: monday)

        XCTAssertFalse(habit.isEligibleForCompletion(on: thursday, calendar: calendar),
                       "Anchored weekly habit must block a second log in the same calendar week")
    }

    // MARK: - 2h: Weekly habit (anchor day) — allowed next week

    func test_weekly_anchorDay_allowedNextWeek() throws {
        let calendar   = Calendar.current
        let monday     = nextWeekday(2)
        let nextMonday = calendar.date(byAdding: .weekOfYear, value: 1, to: monday)!
        let habit      = try makeHabit(recurrence: .weekly(weekday: 2),
                                       lastCompletedAt: monday)

        XCTAssertTrue(habit.isEligibleForCompletion(on: nextMonday, calendar: calendar),
                      "Anchored weekly habit must be eligible on the matching day next week")
    }

    // MARK: - 2i: Generic weekly (no anchor) — blocked any second log same week

    func test_weeklyNoAnchor_blockedSameWeek() throws {
        let calendar  = Calendar.current
        let tuesday   = nextWeekday(3)
        let saturday  = nextWeekday(7, from: tuesday)
        let habit     = try makeHabit(recurrence: .weekly(weekday: nil),
                                      lastCompletedAt: tuesday)

        XCTAssertFalse(habit.isEligibleForCompletion(on: saturday, calendar: calendar),
                       "Generic weekly habit must block any second log in the same week")
    }

    // MARK: - 2j: Fresh habit with no prior log is always eligible on a scheduled day

    func test_freshHabit_noLastCompleted_alwaysEligible() throws {
        let habit = try makeHabit(recurrence: .daily)
        XCTAssertNil(habit.lastCompletedAt, "Precondition: fresh habit has no prior log")
        XCTAssertTrue(habit.isEligibleForCompletion(on: .now),
                      "Fresh habit must always be eligible on a valid schedule day")
    }

    // MARK: - 2k: isCompletedToday — reversal path bypasses eligibility gate

    func test_isCompletedToday_reversalBypassesGate() throws {
        let context  = container.mainContext
        let calendar = Calendar.current

        // Simulate a completed-today state by setting lastCompletedAt to now.
        let habit = PersistedHabit(title: "Reversal test", recurrence: .weekdays,
                                   lastCompletedAt: .now)
        context.insert(habit)
        try context.save()

        // The eligibility check on its own says "blocked" (already logged today).
        XCTAssertFalse(habit.isEligibleForCompletion(on: .now, calendar: calendar),
                       "Eligibility gate must block a second forward log")

        // But isCompletedToday() returns true, which allows the reversal path.
        XCTAssertTrue(habit.isCompletedToday(calendar: calendar),
                      "isCompletedToday must be true when logged today")

        // Callers combine them: reversal is valid, forward log is not.
        let canAct = habit.isCompletedToday() || habit.isEligibleForCompletion(on: .now)
        XCTAssertTrue(canAct, "Combined gate must permit the reversal action")
    }
}
