import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - StarkSwipeRow
//
// Hand-built horizontal swipe primitive. Replaces native `.swipeActions`
// so every visual atom — backdrop fill, glyph color, label tracking,
// commit threshold, haptic timbre — is under our control. No system tint.
// No green, no red, no default green checkmark dance.
//
// Anatomy:
//   • Backdrop layer: near-black `Surface.cardElevated` with hairline
//     border. Glyph + uppercase tracked label, both pure white.
//   • Foreground layer: caller content, offset along the X axis.
//   • Gesture: axis-locks on first decisive horizontal motion; rubber
//     bands past an unsupported edge; commits past `triggerThreshold`;
//     springs back on release.

struct StarkSwipeAction {
    let systemImage: String
    let label: String
    let perform: () -> Void
}

struct StarkSwipeRow<Content: View>: View {

    @Environment(ThemeStore.self) private var theme

    var leading: StarkSwipeAction? = nil
    var trailing: StarkSwipeAction? = nil
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var axisLocked: Bool = false
    @State private var axisRejected: Bool = false
    @State private var hasCrossedTrigger: Bool = false

    private let triggerThreshold: CGFloat = 110
    private let spring = Animation.spring(response: 0.35, dampingFraction: 0.7)

    var body: some View {
        let p = theme.palette
        ZStack {
            backdrop(p)
                .opacity(abs(offset) > 1 ? 1 : 0)

            content()
                .background(p.rowFill) // opaque so backdrop only shows when offset
                .offset(x: offset)
                .gesture(dragGesture)
        }
        .clipped()
    }

    // MARK: Backdrop

    private func backdrop(_ p: ThemePalette) -> some View {
        HStack(spacing: 0) {
            if let leading, offset > 0 {
                glyph(leading, anchor: .leading, palette: p)
                Spacer(minLength: 0)
            } else if let trailing, offset < 0 {
                Spacer(minLength: 0)
                glyph(trailing, anchor: .trailing, palette: p)
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

    private func glyph(_ action: StarkSwipeAction, anchor: Alignment, palette p: ThemePalette) -> some View {
        let triggered = abs(offset) >= triggerThreshold
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
        .frame(minWidth: 56, alignment: anchor)
        .scaleEffect(triggered ? 1.08 : 1.0)
        .animation(spring, value: triggered)
    }

    // MARK: Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                // First pass: axis-lock to horizontal, reject vertical.
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
                if raw > 0 && leading == nil {
                    next = rubberBand(raw)
                } else if raw < 0 && trailing == nil {
                    next = -rubberBand(-raw)
                } else {
                    next = raw
                }
                offset = next

                // Light haptic the moment we cross the commit threshold (once).
                let crossed = abs(next) >= triggerThreshold
                if crossed && !hasCrossedTrigger {
                    hasCrossedTrigger = true
                    AppHaptic.tap()
                } else if !crossed {
                    hasCrossedTrigger = false
                }
            }
            .onEnded { _ in
                defer {
                    axisLocked = false
                    axisRejected = false
                    hasCrossedTrigger = false
                }
                if offset >= triggerThreshold, let leading {
                    AppHaptic.success()
                    leading.perform()
                    withAnimation(spring) { offset = 0 }
                } else if offset <= -triggerThreshold, let trailing {
                    AppHaptic.rigid()
                    trailing.perform()
                    withAnimation(spring) { offset = 0 }
                } else {
                    withAnimation(spring) { offset = 0 }
                }
            }
    }

    // Cubic rubber-band: pulls hard back toward 0 the further past the edge.
    private func rubberBand(_ x: CGFloat) -> CGFloat {
        let limit: CGFloat = 64
        return limit * (1 - 1 / (x / limit + 1))
    }
}

// MARK: - AppHaptic
//
// Single source of truth for haptic timbre across the app.

enum AppHaptic {
    static func tap() {
        guard Preferences.hapticsEnabled else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    static func success() {
        guard Preferences.hapticsEnabled else { return }
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    static func rigid() {
        guard Preferences.hapticsEnabled else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #endif
    }
}
