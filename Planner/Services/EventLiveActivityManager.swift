import Foundation
import ActivityKit
import os

// MARK: - EventLiveActivityManager
//
// Owns the lifecycle of the Dynamic Countdown Live Activity
// (`EventCountdownAttributes`). The main app starts the activity when the
// capture parser produces a HIGH-PRIORITY, TIMED event that begins soon; the
// widget extension renders the lock-screen + Dynamic Island countdown.
//
// ⚠️ Capability requirement — this is INERT until the project has:
//      • `NSSupportsLiveActivities = YES` in the main app's Info.plist
//      • the user-facing Live Activities toggle enabled (Settings → app)
//   Without those, `areActivitiesEnabled` is false and every entry point
//   below silently no-ops. No crash, no error — see the manual setup notes.
//
// ⚠️ "Exactly 15 minutes before" limitation — a backgrounded app cannot wake
//   itself on a wall-clock schedule without a push token or BGTask. So we
//   start the activity at CAPTURE TIME when the event already falls inside
//   the next 15 minutes. Events captured earlier than that won't get a
//   countdown until a future phase wires up a scheduled trigger (BGTask /
//   push-to-start). This is intentional and documented, not a bug.

@MainActor
enum EventLiveActivityManager {

    private static let logger = Logger(subsystem: "com.remyavipindas.avenor", category: "liveactivity")

    /// Lead window: only auto-start when the event begins within this many
    /// seconds of now (and hasn't already started).
    private static let leadWindow: TimeInterval = 15 * 60

    /// Decides whether a freshly captured todo deserves a countdown and, if
    /// so, starts it. Safe to call for every capture — it gates internally.
    ///
    /// - Parameters:
    ///   - title: stripped event title for the card.
    ///   - eventStart: the todo's `dueDate` (nil ⇒ untimed ⇒ ignored).
    ///   - priority: parser priority (1 = highest … 3). Only 1–2 qualify.
    static func maybeStartCountdown(title: String, eventStart: Date?, priority: Int?) {
        guard let eventStart else { return }                  // untimed → skip
        guard let priority, priority <= 2 else { return }     // not high-priority → skip

        let lead = eventStart.timeIntervalSinceNow
        guard lead > 0, lead <= leadWindow else { return }    // outside the start window

        start(title: title, eventStart: eventStart)
    }

    /// Requests a new Live Activity. No-ops when activities are disabled or
    /// an activity for the same start instant is already live.
    static func start(title: String, eventStart: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.debug("Live Activities disabled — skipping countdown start.")
            return
        }

        // De-dupe: don't stack identical countdowns for the same event.
        let alreadyLive = Activity<EventCountdownAttributes>.activities.contains { activity in
            activity.attributes.title == title &&
            abs(activity.content.state.eventStart.timeIntervalSince(eventStart)) < 1
        }
        guard !alreadyLive else { return }

        let attributes = EventCountdownAttributes(
            title: title,
            themeRaw: currentThemeRaw(),
            accentHex: currentAccentHex()
        )
        let state = EventCountdownAttributes.ContentState(eventStart: eventStart)

        // Stale once the event begins — the system dims the activity and we
        // end it shortly after via `endExpired()`.
        let content = ActivityContent(state: state, staleDate: eventStart)

        do {
            _ = try Activity.request(attributes: attributes, content: content)
            logger.debug("Started countdown Live Activity for \"\(title, privacy: .public)\".")
        } catch {
            logger.error("Failed to start Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// IDs of activities with an in-flight `end(...)` request. Because the
    /// whole type is `@MainActor`, mutations of this set are serialized —
    /// it's the nil-coordination guard that stops `endExpired()` firing on a
    /// `.background` transition AND a near-simultaneous `.active` transition
    /// from enqueuing two terminations for the same activity (a state race).
    private static var endingIDs: Set<String> = []

    /// Ends every live countdown whose event has already started. Call on
    /// foreground/background so stale countdowns don't linger on the lock
    /// screen. Idempotent: terminal-state and in-flight activities are skipped.
    static func endExpired() {
        let now = Date.now
        for activity in Activity<EventCountdownAttributes>.activities
        where !isTerminal(activity.activityState)
           && activity.content.state.eventStart <= now {
            end(activity)
        }
    }

    /// Tears down all countdown activities (e.g. on explicit user reset).
    static func endAll() {
        for activity in Activity<EventCountdownAttributes>.activities
        where !isTerminal(activity.activityState) {
            end(activity)
        }
    }

    /// Single coordinated termination path. The `endingIDs` latch guarantees
    /// exactly one `end(...)` Task per activity even under overlapping
    /// scene-phase callbacks. The `Task` inherits the main actor, so the
    /// `endingIDs` cleanup after the `await` stays serialized.
    private static func end(_ activity: Activity<EventCountdownAttributes>) {
        guard endingIDs.insert(activity.id).inserted else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            endingIDs.remove(activity.id)
        }
    }

    /// Activities that have already finished — re-ending these is pointless
    /// and we filter them so a late phase callback can't thrash the system.
    private static func isTerminal(_ state: ActivityState) -> Bool {
        switch state {
        case .ended, .dismissed: return true
        default:                 return false
        }
    }

    // MARK: Theme bridge

    /// Reads the shared theme raw value from App Group defaults, matching
    /// the widget's palette. Falls back to "dark" (and white accent) when
    /// the App Group isn't configured yet.
    private static func currentThemeRaw() -> String {
        WidgetAppGroup.defaults?.string(forKey: WidgetAppGroup.themeSelectedKey) ?? "dark"
    }

    private static func currentAccentHex() -> String {
        "#FFFFFFFF"
    }
}
