import Foundation
import SwiftData
import SwiftUI

// MARK: - Sort order helper
//
// Free function (not a static on the model) so it can be used as a default
// argument on `@Model` classes. The macro expansion of `@Model` triggers a
// "Covariant 'Self' type cannot be referenced from a default argument" error
// if we try to call a static method on the same class from its own init.
//
// Negative epoch-millis means new items naturally sort to the top under
// `@Query(sort: \.sortOrder)` ascending — matching the existing
// `insert(at: 0)` behavior without any renumbering pass.
func nextDefaultSortOrder() -> Int {
    -Int(Date.now.timeIntervalSince1970 * 1000)
}

// MARK: - PersistedTask
//
// SwiftData-backed replacement for `TaskItem`. We use a distinct name during the
// Phase 1 transition so old (struct) and new (class) types coexist while we
// migrate views. Renaming back to `TaskItem` is a mechanical step at the end
// of Phase 1 if desired.

@Model
final class PersistedTask {
    // Identity / ordering / audit
    // NOTE: `@Attribute(.unique)` is unsupported by CloudKit-backed
    // SwiftData stores. We rely on `UUID()` collision-resistance at the
    // app layer instead. Application-level lookups remain keyed on `id`.
    var id: UUID
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    // Content
    var title: String
    var details: String

    // Type is stored as a raw string so SwiftData can index/predicate on it
    // cheaply. The `type` computed property exposes the typed enum to callers.
    var typeRaw: String

    // Optional state per type
    var isDone: Bool?
    /// Set when `isDone` flips to true. Surfaces in the archive drawer as
    /// the monospaced "COMPLETED [DATE]" timestamp. Cleared if the user
    /// ever un-completes a task.
    var completedAt: Date?
    var dueDate: Date?
    var startDate: Date?
    var endDate: Date?
    var ideaStatusRaw: String?
    var ideaTag: String?

    /// Priority marker (1 = highest … 3 = lowest), mirrored from the capture
    /// bangs (`!!!`→1, `!!`→2, `!`→3). Optional so legacy / CloudKit rows
    /// default cleanly to "no priority". Surfaced through `priorityLevel`.
    var priority: Int?

    /// Optional, loose foreign key linking this task to a `PersistedGoal.id`.
    /// Phase 7 scaffolding: deliberately *not* a `@Relationship` macro so we
    /// stay CloudKit-safe (no inverse constraint required, no strict
    /// schema enforcement). Functional wiring (creation, validation, goal
    /// progress integration) is built next phase — this property only
    /// reserves the column today.
    var parentGoalID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        type: TaskType,
        isDone: Bool? = nil,
        completedAt: Date? = nil,
        dueDate: Date? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        ideaStatus: IdeaStatus? = nil,
        ideaTag: String? = nil,
        priority: Int? = nil,
        parentGoalID: UUID? = nil,
        sortOrder: Int = nextDefaultSortOrder(),
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.typeRaw = type.rawValue
        self.isDone = isDone
        self.completedAt = completedAt
        self.dueDate = dueDate
        self.startDate = startDate
        self.endDate = endDate
        self.ideaStatusRaw = ideaStatus?.rawValue
        self.ideaTag = ideaTag
        self.priority = priority
        self.parentGoalID = parentGoalID
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var type: TaskType {
        get { TaskType(rawValue: typeRaw) ?? .todo }
        set { typeRaw = newValue.rawValue }
    }

    var ideaStatus: IdeaStatus? {
        get { ideaStatusRaw.flatMap(IdeaStatus.init) }
        set { ideaStatusRaw = newValue?.rawValue }
    }

    /// Typed accessor for `priority`. `nil` (and any out-of-range legacy value)
    /// reads as "no priority", which sorts below `.p3` in hierarchical mode.
    var priorityLevel: PriorityLevel? {
        get { priority.flatMap(PriorityLevel.init(rawValue:)) }
        set { priority = newValue?.rawValue }
    }

    /// Type-aware label for the leading "complete" swipe action.
    var completionVerb: String {
        switch type {
        case .todo: return "Done"
        case .reminder: return "Ack"
        case .idea: return "Shipped"
        }
    }
}

// MARK: - Task ordering
//
// Pure, view-agnostic sort used by the Tasks list toggle. Kept on the model
// layer so non-view callers (Overview, Calendar) can reuse the exact ordering.
//   • .chronological → soonest deadline first; undated drop to the bottom,
//     ties broken by `sortOrder` (newest-first negative epoch).
//   • .hierarchical  → most urgent first (P1 → P2 → P3 → unprioritized), then
//     by deadline. Unprioritized tasks use a `99` sentinel so they sit cleanly
//     beneath every explicit `PriorityLevel`.

extension Array where Element == PersistedTask {
    func sorted(by mode: TaskSortMode) -> [PersistedTask] {
        switch mode {
        case .chronological:
            return sorted { lhs, rhs in
                let l = lhs.dueDate ?? .distantFuture
                let r = rhs.dueDate ?? .distantFuture
                if l != r { return l < r }
                return lhs.sortOrder < rhs.sortOrder
            }
        case .hierarchical:
            return sorted { lhs, rhs in
                let priorityLhs = lhs.priorityLevel?.rawValue ?? 99
                let priorityRhs = rhs.priorityLevel?.rawValue ?? 99
                if priorityLhs != priorityRhs { return priorityLhs < priorityRhs }
                let l = lhs.dueDate ?? .distantFuture
                let r = rhs.dueDate ?? .distantFuture
                if l != r { return l < r }
                return lhs.sortOrder < rhs.sortOrder
            }
        }
    }
}

// MARK: - PersistedNote

@Model
final class PersistedNote {
    // NOTE: `@Attribute(.unique)` is unsupported by CloudKit-backed
    // SwiftData stores. We rely on `UUID()` collision-resistance at the
    // app layer instead. Application-level lookups remain keyed on `id`.
    var id: UUID
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var lastEditedAt: Date?

    var title: String
    var details: String

    init(
        id: UUID = UUID(),
        title: String = "",
        details: String = "",
        sortOrder: Int = nextDefaultSortOrder(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastEditedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastEditedAt = lastEditedAt
    }

    var wordCount: Int {
        details.split { $0.isWhitespace || $0.isNewline }.count
    }
}

// MARK: - PersistedGoal

@Model
final class PersistedGoal {
    // NOTE: `@Attribute(.unique)` is unsupported by CloudKit-backed
    // SwiftData stores. We rely on `UUID()` collision-resistance at the
    // app layer instead. Application-level lookups remain keyed on `id`.
    var id: UUID
    var sortOrder: Int
    var createdAt: Date

    var title: String
    var subtitle: String
    var icon: String

    /// `Color` isn't `Codable` for SwiftData; we serialize through hex (RGBA).
    var tintHex: String

    /// `GoalUnit` (preset vs custom) is stored as a Codable blob via the
    /// existing `GoalUnitKindDTO`. Lets us evolve unit shapes without
    /// schema migration.
    var unitData: Data

    var currentValue: Double
    var targetValue: Double

    var lastUpdateNote: String?
    var lastUpdatedAt: Date?

    /// Lifecycle state. Stored as raw string so legacy goals (which never
    /// had this field) read as `.active` via the computed `status` accessor.
    /// `nil` is treated as `.active` for CloudKit-safe defaults.
    var goalStatusRaw: String?

    /// Stamp set when the user explicitly abandons the goal. Used by the
    /// archive view to render a monospaced "ABANDONED [DATE]" timestamp
    /// without overloading `lastUpdatedAt`.
    var abandonedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String = "",
        icon: String = "target",
        tint: Color = .blue,
        unit: GoalUnit = .preset(.books),
        currentValue: Double = 0,
        targetValue: Double = 1,
        lastUpdateNote: String? = nil,
        lastUpdatedAt: Date? = nil,
        status: GoalStatus = .active,
        abandonedAt: Date? = nil,
        sortOrder: Int = nextDefaultSortOrder(),
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.tintHex = tint.toHexRGBA()
        self.unitData = Self.encode(unit: unit)
        self.currentValue = currentValue
        self.targetValue = targetValue
        self.lastUpdateNote = lastUpdateNote
        self.lastUpdatedAt = lastUpdatedAt
        self.goalStatusRaw = status.rawValue
        self.abandonedAt = abandonedAt
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    var tint: Color {
        get { Color.fromHexRGBA(tintHex) }
        set { tintHex = newValue.toHexRGBA() }
    }

    var unit: GoalUnit {
        get {
            (try? JSONDecoder().decode(GoalUnitKindDTO.self, from: unitData))?
                .toModel() ?? .preset(.books)
        }
        set { unitData = Self.encode(unit: newValue) }
    }

    /// Typed accessor for `goalStatusRaw`. Defaults to `.active` so any
    /// pre-existing or CloudKit-synced goal that predates this field
    /// surfaces in the active workspace exactly as before.
    var status: GoalStatus {
        get { goalStatusRaw.flatMap(GoalStatus.init(rawValue:)) ?? .active }
        set { goalStatusRaw = newValue.rawValue }
    }

    var isAbandoned: Bool { status == .abandoned }

    /// Rendering tint for rails, progress fills, and dots. Slightly damped
    /// from the raw `tint` so chromatic accents read as deliberate rather
    /// than saturated. Single source of truth for goal color intensity.
    var displayTint: Color { tint.opacity(0.85) }

    // MARK: Derived

    var progress: Double {
        guard targetValue > 0 else { return 0 }
        return min(max(currentValue / targetValue, 0), 1)
    }

    var isCompleted: Bool { progress >= 1.0 }
    var percentText: String { "\(Int(progress * 100))%" }
    var currentText: String { GoalValueFormatter.string(currentValue, unit: unit) }
    var targetText: String { GoalValueFormatter.string(targetValue, unit: unit) }

    // MARK: Loose task association (Phase 7 scaffold)
    //
    // Returns every `PersistedTask` whose `parentGoalID` equals this goal's
    // id. Implemented as a `FetchDescriptor` on `self.modelContext` rather
    // than a `@Relationship` so we stay CloudKit-compatible (no inverse,
    // no strict schema). Fetch failure or a detached model (no context yet)
    // both return an empty array — fail-soft by design.
    //
    // ⚠️ Phase 7 scaffold only. No call sites read this property today.
    // Mutation paths (assign / unassign / progress integration) are wired
    // in the next phase.
    var associatedTasks: [PersistedTask] {
        guard let context = self.modelContext else { return [] }
        let goalID = self.id
        let descriptor = FetchDescriptor<PersistedTask>(
            predicate: #Predicate { $0.parentGoalID == goalID },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func encode(unit: GoalUnit) -> Data {
        (try? JSONEncoder().encode(GoalUnitKindDTO(unit))) ?? Data()
    }
}

// MARK: - PersistedHabit
//
// The "ongoing tracking habit" container — the destination for recurring
// captures ("Read 20 pages every day"). Deliberately distinct from
// `PersistedTask` (one-off actions) and `PersistedGoal` (target-driven
// metrics): a habit is an open-ended routine measured by streak, not by a
// completion checkbox or a numeric goal.
//
// CloudKit constraints (identical discipline to the other models):
//   • No `@Attribute(.unique)` — `UUID()` collision-resistance + the
//     existing `ConflictResolver` dedup pass cover identity.
//   • Every non-optional property has an init default.
//   • No `@Relationship` macros — `tag` is a loose string, not a join.
//
// ⚠️ Registering this entity is an additive CloudKit schema change: it
// requires a schema deploy + on-device sync test before shipping. Captured
// habits surface in the `HabitsFeed` section of the unified Progress tab
// (`GoalsTabView`), which reads/streaks them and supports swipe-to-archive
// via `isArchived`.

@Model
final class PersistedHabit {
    var id: UUID
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    var title: String
    var details: String

    /// Cadence, serialized via `RecurrenceRule.rawToken`. Stored as a raw
    /// string (not a blob) so SwiftData can predicate on it cheaply. The
    /// typed `recurrence` accessor below bridges to the enum, defaulting to
    /// `.daily` for any unknown / legacy token.
    var recurrenceRaw: String

    /// Optional time-of-day anchor (first occurrence). Only the clock
    /// components are meaningful for daily / weekly cadences.
    var anchorDate: Date?

    /// Optional hashtag carried over from capture ("#health"). Loose string.
    var tag: String?

    /// Raw value of the `RecurrenceTemplate` the user picked in the template
    /// browser, when the cadence came from a template rather than manual
    /// chips. Drives the routine card's meta-strip label ("WEEKDAYS",
    /// "MON, WED, FRI") in place of raw day abbreviations. Optional-with-nil
    /// is a CloudKit-safe additive column; legacy rows read as "no template".
    var templateRaw: String?

    /// Priority marker (1 = highest … 3), mirrored from the capture bangs.
    /// Optional so legacy / CloudKit rows default cleanly.
    var priority: Int?

    // Streak tracking — the habit's core metric.
    var streakCount: Int
    var lastCompletedAt: Date?

    /// Archived loops are hidden from the active dashboard but retain their
    /// streak history (non-destructive swipe-to-archive). Optional-with-default
    /// keeps the column CloudKit-safe for legacy rows.
    var isArchived: Bool

    /// Optional reference to a parent `PersistedGoal.id`. When set, this
    /// routine is the execution system for that goal and renders nested
    /// beneath it in the unified Goals interface. `nil` → standalone routine.
    /// Optional with nil-default is a CloudKit-safe additive column —
    /// no schema migration required.
    var anchorGoalID: UUID?

    /// Streak-restoration state. When a scheduled window is missed,
    /// `checkStreakLapse` flips `isStreakBroken` true *without* zeroing
    /// `streakCount` — the historical value is preserved so the user can
    /// "Rekindle" it by burning a high-priority task. `restorationAvailable`
    /// gates whether the burn affordance is offered. Both carry inline
    /// defaults so this is a lightweight, CloudKit-safe additive migration:
    /// every legacy row reads `false` for both.
    var isStreakBroken: Bool = false
    var restorationAvailable: Bool = false

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        recurrence: RecurrenceRule = .daily,
        anchorDate: Date? = nil,
        tag: String? = nil,
        templateRaw: String? = nil,
        priority: Int? = nil,
        streakCount: Int = 0,
        lastCompletedAt: Date? = nil,
        isArchived: Bool = false,
        anchorGoalID: UUID? = nil,
        isStreakBroken: Bool = false,
        restorationAvailable: Bool = false,
        sortOrder: Int = nextDefaultSortOrder(),
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.recurrenceRaw = recurrence.rawToken
        self.anchorDate = anchorDate
        self.tag = tag
        self.templateRaw = templateRaw
        self.priority = priority
        self.streakCount = streakCount
        self.lastCompletedAt = lastCompletedAt
        self.isArchived = isArchived
        self.anchorGoalID = anchorGoalID
        self.isStreakBroken = isStreakBroken
        self.restorationAvailable = restorationAvailable
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Typed accessor for `recurrenceRaw`. Unknown / legacy tokens read as
    /// `.daily` so a row never fails to materialize.
    var recurrence: RecurrenceRule {
        get { RecurrenceRule(rawToken: recurrenceRaw) ?? .daily }
        set { recurrenceRaw = newValue.rawToken }
    }

    /// Typed accessor for `priority`. Mirrors `PersistedTask.priorityLevel`.
    var priorityLevel: PriorityLevel? {
        get { priority.flatMap(PriorityLevel.init(rawValue:)) }
        set { priority = newValue?.rawValue }
    }

    /// Typed accessor for `templateRaw`. Unknown / legacy values read as
    /// "no template" so the display falls back to the derived cadence label.
    var recurrenceTemplate: RecurrenceTemplate? {
        get { templateRaw.flatMap(RecurrenceTemplate.init(rawValue:)) }
        set { templateRaw = newValue?.rawValue }
    }

    /// Cadence label for row meta strips ("EVERY DAY", "EVERY MONDAY").
    var cadenceLabel: String { recurrence.label }

    /// Meta-strip label preferring the template's display name ("Weekdays",
    /// "Mon, Wed, Fri") over raw day abbreviations. Falls back to the
    /// rule-derived `cadenceLabel` for manual chip selections.
    var cadenceDisplayLabel: String {
        recurrenceTemplate?.rawValue ?? cadenceLabel
    }

    /// Dashboard subtitle pairing cadence with the optional time anchor,
    /// e.g. "Every day · 9:00 PM". Falls back to the bare cadence when no
    /// time was captured.
    var cadenceSubtitle: String {
        guard let anchorDate else { return cadenceDisplayLabel }
        let time = anchorDate.formatted(date: .omitted, time: .shortened)
        return "\(cadenceDisplayLabel) · \(time)"
    }

    /// `true` once the loop has been logged for the current calendar day.
    func isCompletedToday(calendar: Calendar = .current) -> Bool {
        guard let lastCompletedAt else { return false }
        return calendar.isDateInToday(lastCompletedAt)
    }

    /// Toggle today's completion. Completing extends the streak when yesterday
    /// was also logged, otherwise it restarts at 1. Un-completing rolls the
    /// streak back by one day so the loop stays reversible (no destroyed
    /// history). All mutations stamp `updatedAt` for last-writer-wins sync.
    func toggleToday(calendar: Calendar = .current) {
        let now = Date()
        // Capture the resulting state BEFORE mutating so the parent-goal
        // progress mirror knows which direction to move.
        let willComplete = !isCompletedToday(calendar: calendar)
        if isCompletedToday(calendar: calendar) {
            streakCount = max(0, streakCount - 1)
            let startOfToday = calendar.startOfDay(for: now)
            lastCompletedAt = streakCount == 0
                ? nil
                : calendar.date(byAdding: .day, value: -1, to: startOfToday)
        } else {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
            if let last = lastCompletedAt,
               let yesterday,
               calendar.isDate(last, inSameDayAs: yesterday) {
                streakCount += 1
            } else {
                streakCount = 1
            }
            lastCompletedAt = now
            // A fresh completion resolves any pending lapse: the broken
            // banner clears and the streak restarts cleanly at 1. (Burning a
            // task is the *only* path that preserves the old count — handled
            // by the Rekindle sheet, not here.)
            isStreakBroken = false
            restorationAvailable = false
        }
        updatedAt = now
        syncAnchorGoalProgress(completed: willComplete)
    }

    // MARK: - Recurrence-gated completion

    /// `true` when `date`'s weekday falls inside this routine's scheduled
    /// window. Weekday numbering is `Calendar` 1=Sun…7=Sat to match
    /// `RecurrenceRule.customDays`. Generic weekly (`.weekly(nil)`) has no
    /// anchor day, so every day is a valid logging day.
    func isScheduledDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        let wd = calendar.component(.weekday, from: date)
        switch recurrence {
        case .daily:
            return true
        case .weekdays:
            return (2...6).contains(wd)
        case .weekly(let weekday):
            guard let weekday else { return true }
            return wd == weekday
        case .customDays(let days):
            return days.contains(wd)
        case .biweekly(let weekday):
            guard isOnBiweeklyWeek(date, calendar: calendar) else { return false }
            guard let weekday else { return true }
            return wd == weekday
        case .monthly(let day):
            return calendar.component(.day, from: date) == day
        }
    }

    /// Bi-weekly alternation anchor: the routine's first scheduled week.
    /// "On" weeks are an even number of weeks away from the week containing
    /// `anchorDate` (time-of-day anchor, when captured) or `createdAt`.
    private func isOnBiweeklyWeek(_ date: Date, calendar: Calendar) -> Bool {
        let anchor = anchorDate ?? createdAt
        guard
            let anchorWeek = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start,
            let dateWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
            let weeks = calendar.dateComponents([.weekOfYear], from: anchorWeek, to: dateWeek).weekOfYear
        else { return true }
        return weeks.isMultiple(of: 2)
    }

    /// Validation gate fired by the UI *before* a new completion is committed.
    /// Enforces two structural rules and returns `false` if either fails:
    ///   1. Calendar-window alignment — `date` must be a scheduled day.
    ///   2. Double-log protection — already logged this window. Daily /
    ///      weekday / custom / monthly cadences lock once per calendar *day*
    ///      (monthly only ever schedules one day per month, so per-day is
    ///      per-window); weekly and bi-weekly cadences lock once per
    ///      calendar *week*.
    /// Reversing today's completion is a separate path (the caller checks
    /// `isCompletedToday`) and is always allowed.
    func isEligibleForCompletion(on date: Date = .now, calendar: Calendar = .current) -> Bool {
        guard isScheduledDay(date, calendar: calendar) else { return false }
        guard let last = lastCompletedAt else { return true }
        switch recurrence {
        case .weekly, .biweekly:
            return !calendar.isDate(last, equalTo: date, toGranularity: .weekOfYear)
        case .daily, .weekdays, .customDays, .monthly:
            return !calendar.isDate(last, inSameDayAs: date)
        }
    }

    /// Run during scene-phase activation. If a scheduled window elapsed since
    /// the last completion, flag the streak as broken + restorable — but
    /// preserve `streakCount` so the historical value can be locked back in
    /// via the Rekindle sheet. Idempotent: a no-op once already flagged or
    /// when there's no live streak to lose.
    func checkStreakLapse(currentDate: Date = .now, calendar: Calendar = .current) {
        guard !isStreakBroken else { return }
        guard streakCount > 0, let last = lastCompletedAt else { return }
        let startOfToday = calendar.startOfDay(for: currentDate)
        let lastDay = calendar.startOfDay(for: last)
        // Logged today already → nothing lapsed.
        if calendar.isDate(lastDay, inSameDayAs: startOfToday) { return }
        if didMissScheduledWindow(lastDay: lastDay, startOfToday: startOfToday, calendar: calendar) {
            isStreakBroken = true
            restorationAvailable = true
            updatedAt = currentDate
        }
    }

    /// `true` when at least one scheduled completion fell in the gap between
    /// the last log and today and was missed.
    private func didMissScheduledWindow(lastDay: Date, startOfToday: Date, calendar: Calendar) -> Bool {
        // Generic weekly: once per week, any day. Lapsed only once a full
        // week has been skipped (last log predates the start of last week).
        if case .weekly(let weekday) = recurrence, weekday == nil {
            guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: startOfToday)?.start,
                  let prevWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart)
            else { return false }
            return lastDay < prevWeekStart
        }
        // Generic bi-weekly: once per "on" week, any day. Same shape as
        // generic weekly but with a two-week cycle — lapsed only once an
        // entire on-week has been skipped (the per-day walker below would
        // misfire here, since every day of an on-week reads as scheduled
        // while the window is still open until the week ends).
        if case .biweekly(let weekday) = recurrence, weekday == nil {
            guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: startOfToday)?.start,
                  let prevCycleStart = calendar.date(byAdding: .weekOfYear, value: -2, to: thisWeekStart)
            else { return false }
            return lastDay < prevCycleStart
        }
        // Per-day cadences: walk back from yesterday to the day after the last
        // log; any scheduled day in that span is a missed window. Capped to
        // stay O(1) for pathological gaps.
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) else { return false }
        var cursor = yesterday
        var guardrail = 0
        while cursor > lastDay && guardrail < 60 {
            if isScheduledDay(cursor, calendar: calendar) { return true }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
            guardrail += 1
        }
        return false
    }

    /// Lock a broken streak back in place after the user burns a task. Clears
    /// both restoration flags, preserves `streakCount`, and re-stamps the loop
    /// as current (so it reads "completed today" and continues tomorrow).
    /// Deliberately does NOT touch the anchor goal — a burn is a save, not a
    /// routine completion.
    func rekindleStreak(asOf now: Date = .now) {
        isStreakBroken = false
        restorationAvailable = false
        lastCompletedAt = now
        updatedAt = now
    }

    /// Keep the parent `PersistedGoal.currentValue` perfectly mirrored with
    /// this routine's completion state. Completing the loop bumps the goal +1
    /// (clamped to `targetValue`); un-completing rolls it back −1 (clamped to
    /// 0). Resolved through `self.modelContext` so the update lands in the
    /// same transaction as the streak mutation. Fail-soft: a detached model,
    /// missing goal, or absent anchor all no-op cleanly.
    private func syncAnchorGoalProgress(completed: Bool) {
        guard let goalID = anchorGoalID, let context = self.modelContext else { return }
        var descriptor = FetchDescriptor<PersistedGoal>(
            predicate: #Predicate { $0.id == goalID }
        )
        descriptor.fetchLimit = 1
        guard let goal = try? context.fetch(descriptor).first else { return }
        let delta = completed ? 1.0 : -1.0
        goal.currentValue = max(0, min(goal.targetValue, goal.currentValue + delta))
        goal.lastUpdatedAt = updatedAt
    }
}

// MARK: - GoalValueFormatter
//
// Pulled out of the old `Goal.format(_:)`. Keeping it free-standing means
// widgets, notifications, and tests can format goal values without owning
// a Goal instance.

enum GoalValueFormatter {
    static func string(_ value: Double, unit: GoalUnit) -> String {
        let rounded: String
        if unit.allowsDecimals {
            if value.rounded() == value { rounded = String(Int(value)) }
            else { rounded = String(format: "%.1f", value) }
        } else {
            rounded = String(Int(value.rounded()))
        }

        let symbol = unit.symbol
        return unit.isPrefixSymbol ? "\(symbol)\(rounded)" : "\(rounded) \(symbol)"
    }
}
