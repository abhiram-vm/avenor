// PlannerTestsSetup.swift
// PlannerTests
//
// ─────────────────────────────────────────────────────────────────────────────
// ONE-TIME XCODE SETUP  (do this once, then ⌘U runs everything)
// ─────────────────────────────────────────────────────────────────────────────
//
//  1. File → New → Target → Unit Testing Bundle
//     • Product Name:    PlannerTests
//     • Host Application: Planner
//     Click Finish.
//
//  2. In the PlannerTests target → Build Settings:
//     • "Enable Testability" → Yes   (usually auto-set)
//
//  3. Select all four .swift files in this folder and add them to the
//     PlannerTests target (checkbox in File Inspector → Target Membership).
//
//  4. In the Planner scheme (Edit Scheme → Test):
//     Confirm PlannerTests appears under the Test action.
//
//  5. ⌘U  — all tests run against an in-memory SwiftData store; the
//     production on-device database is never touched.
//
// ─────────────────────────────────────────────────────────────────────────────
// TEST COVERAGE MAP
// ─────────────────────────────────────────────────────────────────────────────
//
//  RolloverTimePreservationTests  (6 tests)
//  ┌──────────────────────────────────────────────────────────────────────────┐
//  │  1a  Roll-to-today preserves wall-clock time (4:15 PM stays 4:15 PM)    │
//  │  1b  Roll-to-tomorrow preserves wall-clock time                         │
//  │  1c  Undated task receives startOfDay, no phantom time injected         │
//  │  1d  updatedAt is stamped after the roll                                │
//  │  1e  Batch roll is atomic — all tasks in the batch update together       │
//  │  1f  outstandingActionDebt excludes ideas and completed tasks            │
//  └──────────────────────────────────────────────────────────────────────────┘
//
//  RecurrenceGateTests  (11 tests)
//  ┌──────────────────────────────────────────────────────────────────────────┐
//  │  2a  Weekdays habit blocked on Saturday                                 │
//  │  2b  Weekdays habit blocked on Sunday                                   │
//  │  2c  Weekdays habit allowed on Mon–Fri                                  │
//  │  2d  Daily double-log same day is blocked                               │
//  │  2e  Daily eligible again the next day                                  │
//  │  2f  Custom Tue/Thu habit blocked on Wednesday                          │
//  │  2g  Custom Tue/Thu habit allowed on Tuesday                            │
//  │  2h  Anchored weekly habit blocked same calendar week                   │
//  │  2i  Anchored weekly habit allowed next calendar week                   │
//  │  2j  Generic weekly habit blocked same week                             │
//  │  2k  isCompletedToday reversal path bypasses eligibility gate           │
//  └──────────────────────────────────────────────────────────────────────────┘
//
//  StreakLapseAndRekindleTests  (14 tests)
//  ┌──────────────────────────────────────────────────────────────────────────┐
//  │  Phase A — Lapse detection                                              │
//  │  3a  2-day gap flags lapse, preserves streak count of 5                 │
//  │  3b  1-day gap flags lapse                                              │
//  │  3c  Completed today → no lapse                                         │
//  │  3d  Zero-streak → no lapse                                             │
//  │  3e  checkStreakLapse is idempotent                                      │
//  │  3f  Weekday habit: weekend gap does NOT trigger lapse                  │
//  │                                                                         │
//  │  Phase B — Rekindle (burn a task)                                       │
//  │  3g  rekindleStreak clears flags, preserves historical streak count     │
//  │  3h  Burn atomic: todo task completed+archived, habit re-locked         │
//  │  3i  Burn atomic: idea task gets ideaStatus = .completed                │
//  │  3j  Normal completion clears flags but RESETS streak to 1              │
//  │                                                                         │
//  │  Phase C — LifecycleAutomation service sweep                            │
//  │  3k  checkStreakLapses sweeps all lapsed habits in one pass             │
//  │  3l  Archived habits are skipped by the sweep                          │
//  │  3m  Weekly habit: missed full week triggers lapse                      │
//  │  3n  Weekly habit: logged this week → no lapse                         │
//  └──────────────────────────────────────────────────────────────────────────┘
//
// Total: 31 deterministic unit tests, zero device-clock dependency.
