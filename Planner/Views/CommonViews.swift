import SwiftUI

// MARK: - AppBackground
//
// Replaces the previous opacity-orb background. Deep gradient + two
// slow-drifting blurred orbs, driven by `TimelineView` so the motion is
// genuinely passive — no `@State`, no manual timers, and the system pauses
// it when the app is backgrounded. Honors `Reduce Motion`.

struct AppBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // `Color.clear` accepts the parent's proposed size, so this view
        // never inflates to the orbs' intrinsic 520pt. The orbs live in a
        // clipped overlay — they paint outside the safe area but cannot
        // push siblings (like the ScrollView) wider than the screen.
        Color.clear
            .overlay {
                LinearGradient(
                    stops: DesignTokens.Background.stops,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .overlay {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let driftA = reduceMotion ? 0 : sin(t / 14.0)
                    let driftB = reduceMotion ? 0 : cos(t / 18.0)

                    ZStack {
                        Circle()
                            .fill(DesignTokens.Background.orbA)
                            .blur(radius: 90)
                            .frame(width: 460, height: 460)
                            .offset(x: 160 + CGFloat(driftA) * 18,
                                    y: -260 + CGFloat(driftB) * 14)

                        Circle()
                            .fill(DesignTokens.Background.orbB)
                            .blur(radius: 110)
                            .frame(width: 520, height: 520)
                            .offset(x: -180 + CGFloat(driftB) * 20,
                                    y: 280 + CGFloat(driftA) * 16)
                    }
                }
            }
            .clipped()           // orbs cannot expand the layout
            .ignoresSafeArea()   // gradient still bleeds edge-to-edge
            .allowsHitTesting(false)
    }
}

// MARK: - GlassCard
//
// Backed by `.regularMaterial` (via the `cardSurface()` modifier) instead
// of `Color.white.opacity(...)`. API unchanged, so existing call sites
// keep working — but they now get vibrancy, dynamic contrast, and free
// support for `Reduce Transparency` from the system.

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder _ content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

// MARK: - GlassPlusIcon
//
// Toolbar "+" action used by every tab. 36×36 hit target with a thin
// material backing — reads cleanly over the gradient.

struct GlassPlusIcon: View {
    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(DesignTokens.Accent.primary)
            .frame(width: 36, height: 36)
            .background(Circle().fill(.thinMaterial))
            .overlay(Circle().strokeBorder(DesignTokens.Stroke.hairline, lineWidth: 1))
            .contentShape(Circle())
            .accessibilityLabel("Add")
    }
}

// MARK: - ThemedBackground (legacy shim)
//
// Older sheet code (e.g. goal sheets) used `ThemedBackground(t: theme.t)`.
// We keep that signature so we don't have to touch every call site, but
// it now delegates to `AppBackground`. The `t` parameter is ignored in
// Phase 1 — light-mode support returns in a later phase.

struct ThemedBackground: View {
    let t: ThemeTokens
    var body: some View { AppBackground() }
}
