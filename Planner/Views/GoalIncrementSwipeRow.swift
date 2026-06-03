import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - GoalIncrementSwipeRow
//
// Apple-Music-queue-style threshold-commit swipe. Differs from
// `StarkSwipeRow` in three deliberate ways:
//
//   1. The leading action fires **during** the drag, the instant the
//      offset crosses `commitThreshold`. No release needed.
//   2. After firing, the row springs back to zero while the user's finger
//      is still down. Continuing to drag re-arms the gesture so a user can
//      log +N in one continuous motion.
//   3. The leading glyph is a clean `+1` that scales as the user pulls,
//      pegged solid white at threshold. No label text — the meaning of the
//      swipe is intrinsic to the gesture.
//
// The trailing action keeps the standard `StarkSwipeRow` behavior (commit
// on release) since "Abandon" is a once-per-goal operation, not a repeat
// gesture.

struct GoalIncrementSwipeRow<Content: View>: View {

    @Environment(ThemeStore.self) private var theme

    /// Called once each time the user pulls past `commitThreshold` to the
    /// right. Returns `true` if the mutation actually applied (i.e. the
    /// goal wasn't already at its ceiling). Used to suppress the haptic
    /// pop when capped.
    let onIncrement: () -> Bool

    /// Optional trailing action. Behaves like a standard StarkSwipeRow
    /// trailing — fires on release past threshold.
    let trailing: StarkSwipeAction?

    /// `true` once `currentValue == targetValue`. When set, the leading
    /// glyph dims to `MAX` and the increment haptic falls back to a tap.
    let isAtCeiling: Bool

    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var axisLocked: Bool = false
    @State private var axisRejected: Bool = false
    @State private var hasFiredThisSwing: Bool = false

    private let commitThreshold: CGFloat = 125
    private let spring = Animation.spring(response: 0.32, dampingFraction: 0.72)
    private let snapback = Animation.spring(response: 0.28, dampingFraction: 0.82)

    var body: some View {
        let p = theme.palette
        ZStack {
            backdrop(p)
                .opacity(abs(offset) > 1 ? 1 : 0)

            content()
                .background(p.rowFill)
                .offset(x: offset)
                .gesture(dragGesture)
        }
        .clipped()
    }

    // MARK: Backdrop

    private func backdrop(_ p: ThemePalette) -> some View {
        HStack(spacing: 0) {
            if offset > 0 {
                incrementGlyph(p)
                Spacer(minLength: 0)
            } else if let trailing, offset < 0 {
                Spacer(minLength: 0)
                trailingGlyph(trailing, palette: p)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.chromeSurface)
        .overlay(
            Rectangle()
                .strokeBorder(p.hairline, lineWidth: 0.5)
        )
        .allowsHitTesting(false)
    }

    /// Pull-progress 0…1+ for the leading swipe. Used both as a scale input
    /// and as the "almost there" visual cue (faint glyph at 0.2, full white
    /// near 1.0).
    private var pullProgress: CGFloat {
        guard offset > 0 else { return 0 }
        return min(1.4, offset / commitThreshold)
    }

    private func incrementGlyph(_ p: ThemePalette) -> some View {
        let nearing = pullProgress
        let scale = 0.85 + min(0.35, nearing * 0.35)
        let opacity = isAtCeiling ? 0.35 : (0.45 + min(0.55, nearing * 0.6))
        return Text(isAtCeiling ? "MAX" : "+1")
            .font(.system(size: 22, weight: .heavy, design: .monospaced))
            .tracking(-0.5)
            .foregroundStyle(p.textPrimary.opacity(opacity))
            .scaleEffect(scale)
            .frame(minWidth: 56, alignment: .leading)
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.85), value: offset)
    }

    private func trailingGlyph(_ action: StarkSwipeAction, palette p: ThemePalette) -> some View {
        let triggered = abs(offset) >= commitThreshold
        return VStack(spacing: 6) {
            Image(systemName: action.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(p.textPrimary)
            Text(action.label)
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .foregroundStyle(triggered ? p.textPrimary : p.textSecondary)
        }
        .frame(minWidth: 56, alignment: .trailing)
        .scaleEffect(triggered ? 1.08 : 1.0)
        .animation(spring, value: triggered)
    }

    // MARK: Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if !axisLocked && !axisRejected {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    if dx > dy * 1.4 && dx > 8 {
                        axisLocked = true
                    } else if dy > 8 {
                        axisRejected = true
                        return
                    } else {
                        return
                    }
                }
                guard axisLocked else { return }

                let raw = value.translation.width
                var next: CGFloat
                if raw < 0 && trailing == nil {
                    next = -rubberBand(-raw)
                } else {
                    next = raw
                }
                offset = next

                // Leading swipe-through: fire the moment we cross the
                // threshold, then snap back so the user can swipe again
                // without lifting their finger. `hasFiredThisSwing` arms
                // a cooldown until they pull below ~40% of the threshold.
                if next >= commitThreshold && !hasFiredThisSwing {
                    hasFiredThisSwing = true
                    fireIncrement()
                    withAnimation(snapback) { offset = 0 }
                } else if next < commitThreshold * 0.4 {
                    hasFiredThisSwing = false
                }
            }
            .onEnded { _ in
                defer {
                    axisLocked = false
                    axisRejected = false
                    hasFiredThisSwing = false
                }
                if offset <= -commitThreshold, let trailing {
                    AppHaptic.rigid()
                    trailing.perform()
                }
                withAnimation(spring) { offset = 0 }
            }
    }

    private func fireIncrement() {
        let applied = onIncrement()
        if applied {
            // Sharp physical pop. `rigid` is the closest UIKit timbre to
            // Apple Music's queue-add tick.
            AppHaptic.rigid()
        } else {
            // Quiet acknowledgement when the gesture is valid but the goal
            // is already at its ceiling. Keeps the interaction feeling
            // responsive without lying about progress.
            AppHaptic.tap()
        }
    }

    private func rubberBand(_ x: CGFloat) -> CGFloat {
        let limit: CGFloat = 64
        return limit * (1 - 1 / (x / limit + 1))
    }
}
