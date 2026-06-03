import SwiftUI
import Observation
import WidgetKit

// MARK: - ThemeStore
//
// `@Observable` theme container. `selected` is persisted to the App
// Group UserDefaults suite (`group.com.avenor.planner`) via the `didSet`
// observer so the widget extension reads the exact same value the main
// app wrote. Every write also nudges WidgetKit to reload timelines so
// the lock-screen palette flips the moment the user picks a new theme.
//
// Views consume `palette` (semantic tokens) for theme-aware surfaces;
// `t` remains for the small set of legacy sites still on the old
// `ThemeTokens` shape. New work should always read `palette`.

@Observable
final class ThemeStore {

    /// UserDefaults key. Versioned so a future schema change can migrate
    /// without colliding with the prior value. Bumped to v2 in Phase 6 to
    /// clear any preview-contaminated v1 values (pre-Phase-6 builds were
    /// dark-only, so no real user ever persisted anything but `.dark` to
    /// v1 — the reset is effectively free).
    ///
    /// Shared with the widget extension via `WidgetAppGroup.themeSelectedKey`
    /// — both sides agree on this exact string.
    @ObservationIgnored
    private let storageKey = WidgetAppGroup.themeSelectedKey

    var selected: AppThemeCase {
        didSet {
            guard oldValue != selected else { return }
            // Never persist from inside a Preview process — Xcode previews
            // share UserDefaults with the simulator, so a preview that
            // sets `.liquidGlass` would otherwise override the user's real
            // selection on the next live launch.
            guard !Self.isRunningInPreview else { return }
            WidgetAppGroup.defaults?.set(selected.rawValue, forKey: storageKey)
            // Defensive (and technically legacy on iOS 12+): force the App
            // Group suite to flush its in-memory write to its backing plist
            // before the widget process next reads it. iOS normally
            // coalesces writes asynchronously, which has produced cases
            // where the widget's first timeline tick after a theme switch
            // still reads the old value. `synchronize()` is the documented
            // escape hatch for cross-process UserDefaults handoff, even
            // though it's been formally deprecated for single-process use.
            WidgetAppGroup.defaults?.synchronize()
            // Ask WidgetKit to rebuild every active timeline so the new
            // palette ships to the lock screen / home screen immediately.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    var t: ThemeTokens { .tokens(for: selected) }

    /// Semantic token bundle for the active theme. New code (Settings,
    /// future re-skinned tabs) reads from this instead of `DesignTokens`
    /// directly so theme switching propagates through one read.
    var palette: ThemePalette { .make(for: selected) }

    init() {
        // Previews always start in `.dark` — they should never inherit a
        // persisted value from another preview run.
        if Self.isRunningInPreview {
            self.selected = .dark
            return
        }

        // One-shot migration: prior builds wrote to `UserDefaults.standard`
        // under the same key. If the App Group suite is empty but standard
        // defaults has a value, copy it across so existing users keep their
        // selection on the first launch that ships with the widget.
        let group = WidgetAppGroup.defaults
        if group?.string(forKey: WidgetAppGroup.themeSelectedKey) == nil,
           let legacy = UserDefaults.standard.string(forKey: WidgetAppGroup.themeSelectedKey) {
            group?.set(legacy, forKey: WidgetAppGroup.themeSelectedKey)
        }

        // Live launches: rehydrate the persisted selection. Missing or
        // unparseable values deterministically fall back to `.dark`.
        if let raw = group?.string(forKey: storageKey),
           let parsed = AppThemeCase(rawValue: raw) {
            self.selected = parsed
        } else {
            self.selected = .dark
        }
    }

    /// Xcode injects this when rendering SwiftUI previews. Used to keep
    /// preview side-effects out of the live UserDefaults store.
    @ObservationIgnored
    private static let isRunningInPreview: Bool =
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

// MARK: - Preferences
//
// Lightweight, non-observable accessor for boolean prefs that live in
// UserDefaults. Used by `AppHaptic` and `NotificationManager` to gate
// side-effects without dragging in SwiftUI's property-wrapper machinery.
// The Settings view binds to these same keys via `@AppStorage` so reads
// and writes stay in lockstep.
//
// Defaults are true for both — first-time launches feel "alive" out of
// the box. Users opt out, not in.

enum Preferences {
    static let hapticsKey       = "pref.hapticsEnabled"
    static let notificationsKey = "pref.notificationsEnabled"
    static let displayNameKey   = "profile.displayName"
    static let proTierKey       = "profile.proTier"

    static var hapticsEnabled: Bool {
        get { (UserDefaults.standard.object(forKey: hapticsKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: hapticsKey) }
    }

    static var notificationsEnabled: Bool {
        get { (UserDefaults.standard.object(forKey: notificationsKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: notificationsKey) }
    }
}
