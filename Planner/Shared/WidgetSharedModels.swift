import Foundation
import SwiftUI
#if os(iOS)
import ActivityKit
#endif

// MARK: - WidgetSharedModels
//
// Plain `Codable` snapshots written by the main app into App Group
// UserDefaults under `group.com.avenor.planner`. The widget extension
// decodes them on every timeline refresh. No SwiftData here — keeps the
// widget bundle minimal, fast, and decoupled from the persistence layer.
//
// ⚠️ TARGET MEMBERSHIP — this file MUST be a member of BOTH targets:
//      • Planner (main app)         — produces snapshots
//      • AvenorWidget (extension)   — consumes snapshots
// In Xcode: select this file → File Inspector → Target Membership → tick both.

public enum WidgetAppGroup {
    public static let identifier = "group.com.avenor.planner"

    public static let todayPayloadKey = "widget.todayPayload.v1"
    public static let goalsPayloadKey = "widget.goalsPayload.v1"

    /// Active routine (habit) loops for the day, surfaced in the medium
    /// interactive widget's left column.
    public static let routinePayloadKey = "widget.routinePayload.v1"

    /// Append-only queue of interactions performed FROM the widget (e.g. a
    /// task checkbox tap). The widget process cannot safely open the live
    /// SwiftData store, so each tap is journaled here and the main app
    /// drains + applies it on next foreground. See `WidgetActionQueue`.
    public static let pendingActionsKey = "widget.pendingActions.v1"

    /// Shared theme selection. Both the main app and the widget extension
    /// read/write this key — that's how the widget stays visually in lockstep
    /// with the user's chosen palette. Raw value matches `AppThemeCase`.
    public static let themeSelectedKey = "theme.selected.v2"

    public static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}

// MARK: Today Glance payload

public struct TodayWidgetItem: Codable, Identifiable, Hashable {
    public let id: UUID
    public let title: String
    public let typeRaw: String        // "todo" | "reminder" | "idea"
    public let dueDate: Date?
    public let ideaTag: String?

    public init(id: UUID, title: String, typeRaw: String, dueDate: Date?, ideaTag: String?) {
        self.id = id
        self.title = title
        self.typeRaw = typeRaw
        self.dueDate = dueDate
        self.ideaTag = ideaTag
    }
}

public struct TodayWidgetPayload: Codable {
    public let items: [TodayWidgetItem]   // ordered by deadline, ascending
    public let totalDueToday: Int
    public let generatedAt: Date

    public init(items: [TodayWidgetItem], totalDueToday: Int, generatedAt: Date = .now) {
        self.items = items
        self.totalDueToday = totalDueToday
        self.generatedAt = generatedAt
    }

    /// Mock data for widget gallery preview ONLY. Never falls back here
    /// from real timeline reads — `readToday()` returns `.empty` instead,
    /// so missing/undecodable payloads render the "Nothing scheduled."
    /// empty state in production widgets.
    public static let placeholder = TodayWidgetPayload(
        items: [
            TodayWidgetItem(id: UUID(), title: "Ship Stark refactor", typeRaw: "todo", dueDate: .now, ideaTag: "AVENOR"),
            TodayWidgetItem(id: UUID(), title: "Submit App Store note", typeRaw: "reminder", dueDate: .now.addingTimeInterval(3600), ideaTag: nil),
            TodayWidgetItem(id: UUID(), title: "Sketch widget grid", typeRaw: "todo", dueDate: .now.addingTimeInterval(7200), ideaTag: "WIDGETS"),
        ],
        totalDueToday: 3
    )

    /// Real production fallback. Empty list, zero count — surfaces the
    /// "Nothing scheduled." state on the home screen instead of leaking
    /// mock content from `.placeholder`.
    public static let empty = TodayWidgetPayload(items: [], totalDueToday: 0)
}

// MARK: Goal payload

public struct GoalWidgetItem: Codable, Identifiable, Hashable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    public let currentValueText: String
    public let targetValueText: String
    public let progress: Double            // 0...1
    public let tintHex: String

    public init(id: UUID, title: String, subtitle: String, currentValueText: String, targetValueText: String, progress: Double, tintHex: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.currentValueText = currentValueText
        self.targetValueText = targetValueText
        self.progress = progress
        self.tintHex = tintHex
    }
}

public struct GoalsWidgetPayload: Codable {
    public let goals: [GoalWidgetItem]
    public let generatedAt: Date

    public init(goals: [GoalWidgetItem], generatedAt: Date = .now) {
        self.goals = goals
        self.generatedAt = generatedAt
    }

    public static let placeholder = GoalsWidgetPayload(
        goals: [
            GoalWidgetItem(
                id: UUID(),
                title: "Read 20 books",
                subtitle: "2026",
                currentValueText: "7 books",
                targetValueText: "20 books",
                progress: 7.0 / 20.0,
                tintHex: "#FFFFFFFF"
            )
        ]
    )
}

// MARK: Codable IO

public enum WidgetSnapshotIO {
    public static func writeToday(_ payload: TodayWidgetPayload) {
        guard let defaults = WidgetAppGroup.defaults else { return }
        if let data = try? JSONEncoder.iso.encode(payload) {
            defaults.set(data, forKey: WidgetAppGroup.todayPayloadKey)
        }
    }

    public static func readToday() -> TodayWidgetPayload {
        guard
            let defaults = WidgetAppGroup.defaults,
            let data = defaults.data(forKey: WidgetAppGroup.todayPayloadKey),
            let payload = try? JSONDecoder.iso.decode(TodayWidgetPayload.self, from: data)
        else { return .empty }
        return payload
    }

    public static func writeGoals(_ payload: GoalsWidgetPayload) {
        guard let defaults = WidgetAppGroup.defaults else { return }
        if let data = try? JSONEncoder.iso.encode(payload) {
            defaults.set(data, forKey: WidgetAppGroup.goalsPayloadKey)
        }
    }

    public static func readGoals() -> GoalsWidgetPayload {
        guard
            let defaults = WidgetAppGroup.defaults,
            let data = defaults.data(forKey: WidgetAppGroup.goalsPayloadKey),
            let payload = try? JSONDecoder.iso.decode(GoalsWidgetPayload.self, from: data)
        else { return .placeholder }
        return payload
    }
}

// MARK: Color hex bridge
//
// Mirrors the app's `Color.fromHexRGBA`. Kept here so the widget extension
// compiles without importing the main app's Models.swift.

public extension Color {
    static func fromWidgetHex(_ hex: String) -> Color {
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

// MARK: - Routine (habit) payload
//
// Mirrors `PersistedHabit` into the widget snapshot. Only the fields the
// medium interactive widget renders are carried — title, cadence label,
// streak, today's completion state, and tint.

public struct HabitWidgetItem: Codable, Identifiable, Hashable {
    public let id: UUID
    public let title: String
    public let cadenceLabel: String      // "Every day", "Weekdays", …
    public let streakCount: Int
    public let isCompletedToday: Bool
    public let tintHex: String

    public init(id: UUID, title: String, cadenceLabel: String, streakCount: Int, isCompletedToday: Bool, tintHex: String) {
        self.id = id
        self.title = title
        self.cadenceLabel = cadenceLabel
        self.streakCount = streakCount
        self.isCompletedToday = isCompletedToday
        self.tintHex = tintHex
    }
}

public struct RoutineWidgetPayload: Codable {
    public let habits: [HabitWidgetItem]   // active (non-archived) loops, ordered
    public let generatedAt: Date

    public init(habits: [HabitWidgetItem], generatedAt: Date = .now) {
        self.habits = habits
        self.generatedAt = generatedAt
    }

    public static let placeholder = RoutineWidgetPayload(habits: [
        HabitWidgetItem(id: UUID(), title: "Read 20 pages", cadenceLabel: "Every day", streakCount: 12, isCompletedToday: false, tintHex: "#8CD9C7FF"),
        HabitWidgetItem(id: UUID(), title: "Cold shower",   cadenceLabel: "Every morning", streakCount: 4, isCompletedToday: true, tintHex: "#EBBC85FF")
    ])

    public static let empty = RoutineWidgetPayload(habits: [])
}

// MARK: - Pending action queue
//
// The widget extension cannot mutate the live SwiftData store directly
// (the store lives in the main app's sandbox, not the App Group). So an
// interactive tap appends a `WidgetPendingAction` to a small JSON array in
// App Group UserDefaults; the main app drains and applies it on next
// foreground via `WidgetActionApplier`. The widget UI updates optimistically
// + reloads its own timeline so the tap LOOKS instant.

public struct WidgetPendingAction: Codable, Identifiable, Hashable {
    public enum Kind: String, Codable {
        case completeTask    // flip PersistedTask.isDone -> true
        case toggleHabit     // PersistedHabit.toggleToday()
    }

    public let id: UUID
    public let kind: Kind
    public let targetID: UUID
    public let createdAt: Date

    public init(id: UUID = UUID(), kind: Kind, targetID: UUID, createdAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.targetID = targetID
        self.createdAt = createdAt
    }
}

public enum WidgetActionQueue {
    /// Append a new action. Reads the current array, appends, writes back.
    /// Cross-process safe enough for a single-writer-at-a-time widget tap;
    /// `synchronize()` flushes for the main app's next read.
    public static func enqueue(_ action: WidgetPendingAction) {
        guard let defaults = WidgetAppGroup.defaults else { return }
        var current = read(from: defaults)
        current.append(action)
        if let data = try? JSONEncoder.iso.encode(current) {
            defaults.set(data, forKey: WidgetAppGroup.pendingActionsKey)
            defaults.synchronize()
        }
    }

    /// Non-destructive read of the queue. The widget entry view uses this
    /// to render an OPTIMISTIC overlay (a tapped-but-not-yet-applied task
    /// shows as checked) so the Home Screen tap looks instant before the
    /// main app drains the queue.
    public static func peek() -> [WidgetPendingAction] {
        guard let defaults = WidgetAppGroup.defaults else { return [] }
        return read(from: defaults)
    }

    /// Returns all queued actions and clears the queue atomically (read,
    /// then immediately overwrite with empty). Called by the main app.
    public static func drainAll() -> [WidgetPendingAction] {
        guard let defaults = WidgetAppGroup.defaults else { return [] }
        let actions = read(from: defaults)
        guard !actions.isEmpty else { return [] }
        defaults.removeObject(forKey: WidgetAppGroup.pendingActionsKey)
        defaults.synchronize()
        return actions
    }

    private static func read(from defaults: UserDefaults) -> [WidgetPendingAction] {
        guard let data = defaults.data(forKey: WidgetAppGroup.pendingActionsKey),
              let actions = try? JSONDecoder.iso.decode([WidgetPendingAction].self, from: data)
        else { return [] }
        return actions
    }
}

// MARK: - Routine snapshot IO

public extension WidgetSnapshotIO {
    static func writeRoutine(_ payload: RoutineWidgetPayload) {
        guard let defaults = WidgetAppGroup.defaults else { return }
        if let data = try? JSONEncoder.iso.encode(payload) {
            defaults.set(data, forKey: WidgetAppGroup.routinePayloadKey)
        }
    }

    static func readRoutine() -> RoutineWidgetPayload {
        guard
            let defaults = WidgetAppGroup.defaults,
            let data = defaults.data(forKey: WidgetAppGroup.routinePayloadKey),
            let payload = try? JSONDecoder.iso.decode(RoutineWidgetPayload.self, from: data)
        else { return .empty }
        return payload
    }
}

// MARK: - Live Activity attributes
//
// Shared between the main app (which starts/updates/ends the activity via
// `EventLiveActivityManager`) and the widget extension (which renders the
// lock-screen + Dynamic Island UI). MUST be a member of BOTH targets.
//
// iOS-only: ActivityKit is unavailable on macOS, so this type compiles out of
// the Mac target. No macOS code path references it.

#if os(iOS)
public struct EventCountdownAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// The wall-clock moment the event begins. Drives the native
        /// `Text(timerInterval:)` ticking countdown with zero per-second
        /// process wakeups.
        public var eventStart: Date

        public init(eventStart: Date) {
            self.eventStart = eventStart
        }
    }

    /// Stripped event title ("Presentation").
    public let title: String
    /// Raw `WidgetThemeID` value so the activity can match the app palette.
    public let themeRaw: String
    /// Accent hex (RGBA) for the theme-colored loop glyph / keyline.
    public let accentHex: String

    public init(title: String, themeRaw: String, accentHex: String) {
        self.title = title
        self.themeRaw = themeRaw
        self.accentHex = accentHex
    }
}
#endif

// MARK: - Shared JSON coders (exposed for queue + payload IO)

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
