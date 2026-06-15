import SwiftUI
import Foundation

// MARK: - AppTheme (legacy static constants)
//
// Retained as a convenience for any call sites that haven't migrated to
// `DesignTokens` yet. Light-mode support arrives in a later phase; Phase 1
// is dark-mode-only by design.

enum AppTheme {
    static let bg = Color(red: 0.05, green: 0.05, blue: 0.06)
    static let panel = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.12)
    static let text = Color.white
    static let text2 = Color.white.opacity(0.72)
    static let text3 = Color.white.opacity(0.45)

    static let field = Color.white.opacity(0.06)
    static let fieldStroke = Color.white.opacity(0.12)
}

// MARK: - App Theme Cases

enum AppThemeCase: String, CaseIterable, Identifiable {
    case dark, light, calmEarth, liquidGlass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .calmEarth: return "Calm Earth"
        case .liquidGlass: return "Liquid Glass"
        }
    }

    /// Per-case glyph for the Settings picker.
    var glyph: String {
        switch self {
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        case .calmEarth: return "leaf.fill"
        case .liquidGlass: return "sparkles"
        }
    }

    /// Drives `.preferredColorScheme` on Settings (the sheet honors the
    /// chosen theme even while the rest of the app stays dark).
    var colorScheme: ColorScheme {
        switch self {
        case .light, .calmEarth: return .light
        case .dark, .liquidGlass: return .dark
        }
    }

}

// MARK: - Theme Tokens

struct ThemeTokens {
    let bg: Color
    let panel: Color
    let stroke: Color
    let text: Color
    let text2: Color
    let text3: Color
    let field: Color
    let fieldStroke: Color
    let scheme: ColorScheme

    static func tokens(for theme: AppThemeCase) -> ThemeTokens {
        switch theme {
        case .dark, .liquidGlass:
            // Legacy struct — only the (mostly dead) CommonViews path
            // reads from it. Modern Settings consumes `ThemePalette`.
            return .init(
                bg: AppTheme.bg, panel: AppTheme.panel, stroke: AppTheme.stroke,
                text: AppTheme.text, text2: AppTheme.text2, text3: AppTheme.text3,
                field: AppTheme.field, fieldStroke: AppTheme.fieldStroke,
                scheme: .dark
            )
        case .light, .calmEarth:
            return .init(
                bg: Color(.systemBackground), panel: Color(.secondarySystemBackground),
                stroke: Color.black.opacity(0.12),
                text: Color(.label), text2: Color(.secondaryLabel), text3: Color(.tertiaryLabel),
                field: Color(.secondarySystemBackground), fieldStroke: Color.black.opacity(0.10),
                scheme: .light
            )
        }
    }
}

// MARK: - Task pill style + types

enum PillStyle {
    case todo, idea, reminder

    var color: Color {
        switch self {
        case .todo: return DesignTokens.Accent.todo
        case .idea: return DesignTokens.Accent.idea
        case .reminder: return DesignTokens.Accent.reminder
        }
    }

    var title: String {
        switch self {
        case .todo: return "TODO"
        case .idea: return "IDEA"
        case .reminder: return "REMINDER"
        }
    }

    var icon: String {
        switch self {
        case .todo: return "checklist"
        case .idea: return "lightbulb"
        case .reminder: return "bell"
        }
    }

    var fillOpacity: Double { 0.18 }
    var strokeOpacity: Double { 0.32 }
}

enum TaskType: String, CaseIterable, Identifiable, Codable {
    case todo, idea, reminder

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .todo: return "Todo"
        case .idea: return "Idea"
        case .reminder: return "Reminder"
        }
    }

    var icon: String {
        switch self {
        case .todo: return "checklist"
        case .idea: return "lightbulb"
        case .reminder: return "bell"
        }
    }

    var pillStyle: PillStyle {
        switch self {
        case .todo: return .todo
        case .idea: return .idea
        case .reminder: return .reminder
        }
    }

    var tint: Color { pillStyle.color }
    var pillTitle: String { pillStyle.title }
}

// MARK: - PriorityLevel
//
// Typed wrapper over the loose `priority: Int?` already stored on
// `PersistedHabit` (and, as of 1.3, `PersistedTask`). Raw values intentionally
// match the LIVE capture convention — `!!!` parses to `1` (highest), `!` to `3`
// (lowest), and the user-facing label is "P1" for top priority. Defining `p1`
// as rawValue `1` preserves every stored int and the existing label, rather
// than inverting them. `Comparable` is by rawValue, so ascending order surfaces
// the most urgent item first (`.p1 < .p2 < .p3`).

enum PriorityLevel: Int, Codable, CaseIterable, Identifiable, Comparable {
    case p1 = 1   // High (most urgent)
    case p2 = 2   // Medium
    case p3 = 3   // Low

    var id: Int { rawValue }

    static func < (lhs: PriorityLevel, rhs: PriorityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Compact uppercase label for meta strips ("P1" / "P2" / "P3").
    var label: String { "P\(rawValue)" }

    var displayName: String {
        switch self {
        case .p1: return "High"
        case .p2: return "Medium"
        case .p3: return "Low"
        }
    }

    var glyph: String {
        switch self {
        case .p1: return "exclamationmark.3"
        case .p2: return "exclamationmark.2"
        case .p3: return "exclamationmark"
        }
    }
}

// MARK: - TaskSortMode
//
// Toggle for the Tasks list ordering. `.chronological` sorts by deadline;
// `.hierarchical` sorts by urgency (P1 → P3 → unprioritized). The actual
// comparator lives in the `[PersistedTask].sorted(by:)` helper alongside the
// model so non-view callers can reuse it.

enum TaskSortMode: String, CaseIterable, Identifiable {
    case chronological
    case hierarchical

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chronological: return "By Date"
        case .hierarchical:  return "By Priority"
        }
    }

    var glyph: String {
        switch self {
        case .chronological: return "calendar"
        case .hierarchical:  return "flag"
        }
    }
}

enum IdeaStatus: String, CaseIterable, Identifiable, Equatable, Codable {
    case thinking, inProgress, completed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thinking: return "Thinking"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        }
    }

    var icon: String {
        switch self {
        case .thinking: return "brain"
        case .inProgress: return "hammer"
        case .completed: return "checkmark.seal.fill"
        }
    }

    var shortLabel: String {
        switch self {
        case .thinking: return "Think"
        case .inProgress: return "Doing"
        case .completed: return "Done"
        }
    }
}

// MARK: - Notes pill style

enum NotesPillStyle {
    case note

    var color: Color { DesignTokens.Accent.note }
    var title: String { "NOTE" }
    var icon: String { "note.text" }
    var fillOpacity: Double { 0.18 }
    var strokeOpacity: Double { 0.32 }
}

// MARK: - New Task Draft
//
// Plain-value carrier from `NewItemSheet` back to the page. Replaces the
// previous practice of passing a fully-formed `TaskItem` struct — now that
// the persisted model is a SwiftData class, we need an intermediate.

struct NewTaskDraft {
    var title: String = ""
    var details: String = ""
    var type: TaskType = .todo
    var isDone: Bool? = nil
    /// Unified deadline for both `.todo` and `.reminder`. A todo expresses a
    /// binary actionable item with a clear due date; a reminder expresses an
    /// alert-driven item at the same moment. Legacy `startDate`/`endDate`
    /// remain on `PersistedTask` for backward-compat with archived JSON but
    /// are no longer surfaced through the draft.
    var dueDate: Date? = nil
    var ideaStatus: IdeaStatus? = nil
    var ideaTag: String? = nil
    /// Loose foreign key to `PersistedGoal.id` selected at capture time.
    /// Propagated into `PersistedTask.parentGoalID` by the page's insert
    /// path. `nil` means the task is not linked to any goal.
    var parentGoalID: UUID? = nil
}

// MARK: - New Goal Draft + units

struct NewGoalDraft {
    var title: String = ""
    var subtitle: String = ""
    var icon: String = "target"
    var tint: Color = .blue
    var unit: GoalUnit = .preset(.books)
    var currentValue: Double = 0
    var targetValue: Double = 10
}

enum UnitPreset: String, CaseIterable, Identifiable, Codable {
    // High-utility presets. `km`/`lessons`/`usd` were retired in favor of
    // `miles`/`revenue` — the legacy raw values won't decode anymore, but
    // CloudKit-stored goals fall back to `.books` via the decode-failure
    // path on `PersistedGoal.unit`.
    case books, miles, revenue, hours, sessions, gymLogs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .books:    return "Books"
        case .miles:    return "Miles"
        case .revenue:  return "Revenue ($)"
        case .hours:    return "Hours"
        case .sessions: return "Sessions"
        case .gymLogs:  return "Gym Logs"
        }
    }

    var defaultSymbol: String {
        switch self {
        case .books:    return "books"
        case .miles:    return "mi"
        case .revenue:  return "$"
        case .hours:    return "hrs"
        case .sessions: return "sessions"
        case .gymLogs:  return "logs"
        }
    }

    var allowsDecimals: Bool {
        switch self {
        case .miles, .revenue, .hours: return true
        case .books, .sessions, .gymLogs: return false
        }
    }

    var isPrefixSymbol: Bool { self == .revenue }
}

// MARK: - GoalStatus
//
// Tri-state lifecycle for goals. Decoupled from `isCompleted` (which is a
// derived from progress) so the user can explicitly retire a goal without
// claiming they finished it. Stored as a raw string on `PersistedGoal`.

enum GoalStatus: String, CaseIterable, Identifiable, Codable {
    case active
    case abandoned
    /// Retired by the 1.3 Goal→Habit migration. The numeric goal is kept in
    /// the store (data-safe) but hidden from the active workspace; its content
    /// lives on as a `PersistedHabit` loop. Distinct from `.abandoned` so the
    /// archive doesn't mislabel migrated goals as user-abandoned.
    case converted

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .active:    return "Active"
        case .abandoned: return "Abandoned"
        case .converted: return "Converted"
        }
    }
}

// MARK: - RecurrenceTemplate
//
// Pre-built recurrence patterns for the template browser sheet. Each case
// resolves to a concrete `RecurrenceRule` that gets applied to the chip
// matrix (and ultimately persisted on `PersistedHabit`). The raw value is
// the display name — it doubles as the routine card's meta-strip label
// ("WEEKDAYS", "MON, WED, FRI") and the persistence token stored in
// `PersistedHabit.templateRaw`, so renaming a case is a data migration.
//
// Templates are additive sugar over the manual chip matrix: applying one
// just writes the equivalent `RecurrenceRule`; the user can still override
// any individual chip afterwards (which detaches the template).

enum RecurrenceTemplate: String, CaseIterable, Identifiable {
    case everyDay     = "Every Day"
    case weekdays     = "Weekdays"
    case weekends     = "Weekends"
    case everyMonday  = "Every Monday"
    case everyMWF     = "Mon, Wed, Fri"
    case everyTTh     = "Tue, Thu"
    case biweekly     = "Bi-Weekly"
    case firstOfMonth = "1st of Month"

    var id: String { rawValue }

    /// Scheduled weekdays in `Calendar` numbering (1=Sun…7=Sat — the same
    /// convention as `RecurrenceRule.customDays` and the chip matrix).
    /// Empty for the two non-weekly cadences (`biweekly`, `firstOfMonth`),
    /// which the chip matrix can't express — they carry their schedule in
    /// `rule` instead.
    var days: Set<Int> {
        switch self {
        case .everyDay:     return [1, 2, 3, 4, 5, 6, 7]
        case .weekdays:     return [2, 3, 4, 5, 6]
        case .weekends:     return [1, 7]
        case .everyMonday:  return [2]
        case .everyMWF:     return [2, 4, 6]
        case .everyTTh:     return [3, 5]
        case .biweekly:     return []
        case .firstOfMonth: return []
        }
    }

    /// The concrete rule this template applies — single source of truth for
    /// what selecting the template means.
    var rule: RecurrenceRule {
        switch self {
        case .everyDay:     return .daily
        case .weekdays:     return .weekdays
        case .weekends:     return .customDays([1, 7])
        case .everyMonday:  return .weekly(weekday: 2)
        case .everyMWF:     return .customDays([2, 4, 6])
        case .everyTTh:     return .customDays([3, 5])
        case .biweekly:     return .biweekly(weekday: nil)
        case .firstOfMonth: return .monthly(day: 1)
        }
    }

    /// SF Symbol for the template browser row.
    var icon: String {
        switch self {
        case .everyDay:     return "repeat"
        case .weekdays:     return "briefcase"
        case .weekends:     return "sun.max"
        case .everyMonday:  return "calendar"
        case .everyMWF:     return "calendar.day.timeline.leading"
        case .everyTTh:     return "calendar.day.timeline.trailing"
        case .biweekly:     return "arrow.2.squarepath"
        case .firstOfMonth: return "1.circle"
        }
    }

    /// One-line explanation under the template name.
    var description: String {
        switch self {
        case .everyDay:     return "Repeats every day"
        case .weekdays:     return "Repeats Monday through Friday"
        case .weekends:     return "Repeats Saturday and Sunday"
        case .everyMonday:  return "Repeats every Monday"
        case .everyMWF:     return "Repeats Monday, Wednesday, Friday"
        case .everyTTh:     return "Repeats Tuesday and Thursday"
        case .biweekly:     return "Repeats every other week"
        case .firstOfMonth: return "Repeats on the 1st of each month"
        }
    }
}

struct GoalUnit: Equatable {
    enum Kind: Equatable {
        case preset(UnitPreset)
        case custom(label: String, symbol: String, allowsDecimals: Bool, isPrefixSymbol: Bool)
    }

    var kind: Kind

    var allowsDecimals: Bool {
        switch kind {
        case .preset(let p): return p.allowsDecimals
        case .custom(_, _, let allows, _): return allows
        }
    }

    var isPrefixSymbol: Bool {
        switch kind {
        case .preset(let p): return p.isPrefixSymbol
        case .custom(_, _, _, let prefix): return prefix
        }
    }

    var label: String {
        switch kind {
        case .preset(let p): return p.displayName
        case .custom(let label, _, _, _): return label
        }
    }

    var symbol: String {
        switch kind {
        case .preset(let p): return p.defaultSymbol
        case .custom(let label, let symbol, _, _):
            let s = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? label.trimmingCharacters(in: .whitespacesAndNewlines) : s
        }
    }

    static func preset(_ p: UnitPreset) -> GoalUnit { GoalUnit(kind: .preset(p)) }
    static func custom(label: String, symbol: String, allowsDecimals: Bool, isPrefixSymbol: Bool) -> GoalUnit {
        GoalUnit(kind: .custom(label: label, symbol: symbol, allowsDecimals: allowsDecimals, isPrefixSymbol: isPrefixSymbol))
    }
}

// MARK: - Unit option catalog (creation-sheet presets)
//
// A curated, presentation-facing catalog of measurement units surfaced in
// the Add-Goal sheet's horizontal preset picker. Each option carries a
// `defaultTarget` so selecting it pre-fills a sensible goal (e.g. Steps →
// 10,000) as soft placeholder text the user can overwrite.
//
// Persistence-agnostic: an option is materialized into the existing
// CloudKit-safe `GoalUnit.custom(...)` at create time, so no schema or
// decode path changes. The legacy `UnitPreset` enum is untouched for
// backward-compatible decoding of goals stored before this catalog existed.

struct UnitOption: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let allowsDecimals: Bool
    let isPrefixSymbol: Bool
    let defaultTarget: Double

    var goalUnit: GoalUnit {
        .custom(label: title, symbol: symbol, allowsDecimals: allowsDecimals, isPrefixSymbol: isPrefixSymbol)
    }
}

enum UnitCategory: String, CaseIterable, Identifiable {
    case focus    = "Focus & Mind"
    case physical = "Physical & Health"
    case finance  = "Finance & Growth"

    var id: String { rawValue }

    // Pre-compiled, immutable option arrays. Stored once at type load so a
    // SwiftUI redraw (which re-evaluates `category.options` for every frame
    // of a scroll) never reallocates these — eliminating per-frame work in
    // the horizontal preset tracks.
    private static let focusOptions: [UnitOption] = [
        UnitOption(id: "pages",    title: "Pages",    symbol: "pages",    allowsDecimals: false, isPrefixSymbol: false, defaultTarget: 300),
        UnitOption(id: "minutes",  title: "Minutes",  symbol: "min",      allowsDecimals: false, isPrefixSymbol: false, defaultTarget: 30),
        UnitOption(id: "hours",    title: "Hours",    symbol: "hrs",      allowsDecimals: true,  isPrefixSymbol: false, defaultTarget: 1),
        UnitOption(id: "sessions", title: "Sessions", symbol: "sessions", allowsDecimals: false, isPrefixSymbol: false, defaultTarget: 12),
    ]

    private static let physicalOptions: [UnitOption] = [
        UnitOption(id: "steps",      title: "Steps",         symbol: "steps",   allowsDecimals: false, isPrefixSymbol: false, defaultTarget: 10_000),
        UnitOption(id: "miles",      title: "Miles",         symbol: "mi",      allowsDecimals: true,  isPrefixSymbol: false, defaultTarget: 3),
        UnitOption(id: "kilometers", title: "Kilometers",    symbol: "km",      allowsDecimals: true,  isPrefixSymbol: false, defaultTarget: 5),
        UnitOption(id: "water",      title: "Glass (Water)", symbol: "glasses", allowsDecimals: false, isPrefixSymbol: false, defaultTarget: 8),
        UnitOption(id: "calories",   title: "Cal",           symbol: "cal",     allowsDecimals: false, isPrefixSymbol: false, defaultTarget: 500),
        UnitOption(id: "laps",       title: "Laps",          symbol: "laps",    allowsDecimals: false, isPrefixSymbol: false, defaultTarget: 20),
    ]

    private static let financeOptions: [UnitOption] = [
        UnitOption(id: "usd",   title: "USD ($)",     symbol: "$",     allowsDecimals: true,  isPrefixSymbol: true,  defaultTarget: 1_000),
        UnitOption(id: "eur",   title: "EUR (€)",     symbol: "€",     allowsDecimals: true,  isPrefixSymbol: true,  defaultTarget: 1_000),
        UnitOption(id: "tasks", title: "Tasks",       symbol: "tasks", allowsDecimals: false, isPrefixSymbol: false, defaultTarget: 10),
        UnitOption(id: "reps",  title: "Repetitions", symbol: "reps",  allowsDecimals: false, isPrefixSymbol: false, defaultTarget: 50),
    ]

    var options: [UnitOption] {
        switch self {
        case .focus:    return Self.focusOptions
        case .physical: return Self.physicalOptions
        case .finance:  return Self.financeOptions
        }
    }

    static let allOptions: [UnitOption] = focusOptions + physicalOptions + financeOptions

    static func option(id: String) -> UnitOption? {
        allOptions.first { $0.id == id }
    }
}

// MARK: - Legacy persisted payload (decode-only, used by MigrationService)
//
// The shape on disk has not changed. These DTOs decode the existing
// `planner-data.json` so we can hydrate the new SwiftData store.
// Encoding methods removed — there is no path to write JSON anymore.

struct PersistedAppData: Codable {
    var tasks: [TaskDTO]
    var notes: [NoteDTO]
    var goals: [GoalDTO]
}

struct TaskDTO: Codable {
    var id: UUID
    var title: String
    var details: String
    var type: TaskType
    var isDone: Bool?
    var dueDate: Date?
    var startDate: Date?
    var endDate: Date?
    var ideaStatus: IdeaStatus?
    var ideaTag: String?
}

struct NoteDTO: Codable {
    var id: UUID
    var title: String
    var details: String
}

struct GoalDTO: Codable {
    var id: UUID
    var title: String
    var subtitle: String
    var icon: String
    var tintHex: String
    var unitKind: GoalUnitKindDTO
    var currentValue: Double
    var targetValue: Double
    var lastUpdateNote: String?
    var lastUpdatedAt: Date?
}

enum GoalUnitKindDTO: Codable {
    case preset(UnitPreset)
    case custom(label: String, symbol: String, allowsDecimals: Bool, isPrefixSymbol: Bool)

    private enum CodingKeys: String, CodingKey {
        case type, preset, label, symbol, allowsDecimals, isPrefixSymbol
    }

    private enum Kind: String, Codable { case preset, custom }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .type)
        switch kind {
        case .preset:
            self = .preset(try c.decode(UnitPreset.self, forKey: .preset))
        case .custom:
            self = .custom(
                label: try c.decode(String.self, forKey: .label),
                symbol: try c.decode(String.self, forKey: .symbol),
                allowsDecimals: try c.decode(Bool.self, forKey: .allowsDecimals),
                isPrefixSymbol: try c.decode(Bool.self, forKey: .isPrefixSymbol)
            )
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .preset(let p):
            try c.encode(Kind.preset, forKey: .type)
            try c.encode(p, forKey: .preset)
        case .custom(let label, let symbol, let allowsDecimals, let isPrefixSymbol):
            try c.encode(Kind.custom, forKey: .type)
            try c.encode(label, forKey: .label)
            try c.encode(symbol, forKey: .symbol)
            try c.encode(allowsDecimals, forKey: .allowsDecimals)
            try c.encode(isPrefixSymbol, forKey: .isPrefixSymbol)
        }
    }
}

extension GoalUnitKindDTO {
    init(_ unit: GoalUnit) {
        switch unit.kind {
        case .preset(let p):
            self = .preset(p)
        case .custom(let label, let symbol, let allowsDecimals, let isPrefixSymbol):
            self = .custom(label: label, symbol: symbol, allowsDecimals: allowsDecimals, isPrefixSymbol: isPrefixSymbol)
        }
    }

    func toModel() -> GoalUnit {
        switch self {
        case .preset(let p): return .preset(p)
        case .custom(let label, let symbol, let allowsDecimals, let isPrefixSymbol):
            return .custom(label: label, symbol: symbol, allowsDecimals: allowsDecimals, isPrefixSymbol: isPrefixSymbol)
        }
    }
}

// MARK: - Color hex helpers

extension Color {
    func toHexRGBA() -> String {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X%02X",
                      Int(round(r * 255)), Int(round(g * 255)),
                      Int(round(b * 255)), Int(round(a * 255)))
        #else
        return "#FFFFFFFF"
        #endif
    }

    static func fromHexRGBA(_ hex: String) -> Color {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 8, let v = UInt64(s, radix: 16) else { return .white }
        let r = Double((v >> 24) & 0xFF) / 255.0
        let g = Double((v >> 16) & 0xFF) / 255.0
        let b = Double((v >>  8) & 0xFF) / 255.0
        let a = Double( v        & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
