import SwiftUI

// MARK: - KineticMotion
//
// The "Fluid Complete" gesture system for task cards. Three tactile phases:
//
//   Phase 1 — Compression: touch-down compresses the card to 0.97 with a
//             snappy spring, giving physical resistance under the thumb.
//   Phase 2 — Tactile Pop: on a valid release, a medium impact haptic fires
//             through the app's single haptic source (`AppHaptic`).
//   Phase 3 — Theme-Aware Dissolve: the card exits with a motion language
//             specific to the active theme, then calls `onTrigger()` so the
//             parent removes / completes the underlying model.
//
// Design intent: premium minimalism. Every transition is a physics-based
// spring (never `.linear`/`.easeIn`), interruptions resolve additively, and
// a single `didTrigger` latch makes rapid repeated taps idempotent — no
// double-fire, no mid-frame glitch.

// MARK: - Spring profiles

/// Centralized premium spring profiles. Kept here (not in DesignTokens.Motion)
/// because these are interaction-tuned for the Fluid Complete gesture
/// specifically — the existing `snappy`/`smooth` tokens stay untouched.
enum KineticSpring {
    /// Touch-down resistance. Fast, slightly underdamped for a tactile bite.
    static let compression = Animation.spring(response: 0.2,  dampingFraction: 0.6)
    /// Exit dissolve + all layout changes. The flagship premium curve.
    static let dissolve    = Animation.spring(response: 0.35, dampingFraction: 0.73, blendDuration: 0)
}

// MARK: - Haptic extension
//
// Routes the "Tactile Pop" through the existing single haptic source so it
// still respects `Preferences.hapticsEnabled`. We pre-warm the generator on
// touch-down so the impact lands with zero latency on release.

extension AppHaptic {
    #if canImport(UIKit)
    private static let popGenerator = UIImpactFeedbackGenerator(style: .medium)
    #endif

    /// Prepare the impact engine on touch-down to remove first-fire latency.
    static func prepare() {
        guard Preferences.hapticsEnabled else { return }
        #if canImport(UIKit)
        popGenerator.prepare()
        #endif
    }

    /// Phase 2 — the localized medium impact burst on completion trigger.
    static func pop() {
        guard Preferences.hapticsEnabled else { return }
        #if canImport(UIKit)
        popGenerator.impactOccurred()
        #endif
    }
}

// MARK: - TaskCompletionModifier

/// The reusable Fluid Complete behavior. Apply via `.taskCompletionStyle(...)`.
///
/// - Parameters:
///   - isCompleted: Drives whether the gesture is armed. A completed card is
///     inert; flipping this back to `false` resets the internal phase so the
///     same view can be reused (e.g. on an undo).
///   - theme: Selects the Phase-3 dissolve language.
///   - onTrigger: Fired once, at the END of the dissolve, so the parent's
///     removal animation never fights this modifier's exit.
struct TaskCompletionModifier: ViewModifier {

    let isCompleted: Bool
    let theme: AppThemeCase
    let onTrigger: () -> Void

    private enum Phase { case idle, compressed, dissolving }

    @State private var phase: Phase = .idle
    @State private var dissolveProgress: CGFloat = 0
    /// Idempotency latch — guarantees exactly one trigger per completion.
    @State private var didTrigger = false
    /// Set when the press turns into a scroll/swipe so release won't commit.
    @State private var cancelled = false

    func body(content: Content) -> some View {
        content
            // Phase 3 (Calm Earth): warm olive bleed from center outward.
            .overlay(oliveBleed)
            // Phase 1 compression + Phase 3 dispersion scale.
            .scaleEffect(scale)
            // Phase 3 (Light / Earth): slip / slide on exit.
            .offset(exitOffset)
            // Phase 3 (Liquid Glass): frost blur expands 20 → 0 on dissolve.
            .blur(radius: glassBlur)
            // Phase 3 (all): opacity dissolve.
            .opacity(dissolveOpacity)
            .contentShape(Rectangle())
            .gesture(pressGesture)
            .onChange(of: isCompleted) { _, completed in
                if !completed { resetForReuse() }
            }
    }

    // MARK: Gesture

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !didTrigger, !isCompleted else { return }

                // If the finger travels, the user is scrolling or swiping —
                // release the resistance and disarm so the parent ScrollView
                // / StarkSwipeRow owns the gesture.
                let moved = abs(value.translation.width) > 10
                          || abs(value.translation.height) > 10
                if moved {
                    if phase == .compressed {
                        withAnimation(KineticSpring.compression) { phase = .idle }
                    }
                    cancelled = true
                    return
                }

                if phase == .idle, !cancelled {
                    AppHaptic.prepare()
                    withAnimation(KineticSpring.compression) { phase = .compressed }
                }
            }
            .onEnded { _ in
                defer { cancelled = false }
                guard phase == .compressed, !cancelled, !didTrigger, !isCompleted else {
                    if phase == .compressed {
                        withAnimation(KineticSpring.compression) { phase = .idle }
                    }
                    return
                }
                commit()
            }
    }

    private func commit() {
        didTrigger = true
        AppHaptic.pop()                                  // Phase 2

        // Phase 3 — single interruptible spring drives every theme's exit.
        withAnimation(KineticSpring.dissolve) {
            phase = .dissolving
            dissolveProgress = 1
        } completion: {
            onTrigger()                                  // parent commits removal
        }
    }

    private func resetForReuse() {
        didTrigger = false
        cancelled  = false
        withAnimation(KineticSpring.dissolve) {
            phase = .idle
            dissolveProgress = 0
        }
    }

    // MARK: Derived visual state

    private var scale: CGFloat {
        switch phase {
        case .idle:       return 1.0
        case .compressed: return 0.97
        case .dissolving: return theme == .liquidGlass ? 1.04 : 1.0  // gentle dispersion
        }
    }

    private var dissolveOpacity: Double {
        phase == .dissolving ? 0 : 1
    }

    private var exitOffset: CGSize {
        guard phase == .dissolving else { return .zero }
        switch theme {
        case .light: return CGSize(width: 0,  height: 28)   // slip downward
        case .calmEarth: return CGSize(width: 56, height: 0) // slide away after bleed
        default: return .zero
        }
    }

    /// Liquid Glass only: blur starts at 20 the instant dissolve begins and
    /// resolves to 0 as `dissolveProgress` springs 0 → 1.
    private var glassBlur: CGFloat {
        guard theme == .liquidGlass, phase == .dissolving else { return 0 }
        return 20 * (1 - dissolveProgress)
    }

    // MARK: Calm Earth olive bleed

    @ViewBuilder
    private var oliveBleed: some View {
        if theme == .calmEarth, phase == .dissolving {
            GeometryReader { geo in
                let diameter = max(geo.size.width, geo.size.height) * 2.4
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.36, green: 0.46, blue: 0.28).opacity(0.85),
                                Color(red: 0.36, green: 0.46, blue: 0.28).opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: diameter / 2
                        )
                    )
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(dissolveProgress)              // bleed outward
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .clipped()
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

// MARK: - View extension

extension View {
    /// Apply the Fluid Complete gesture to a task card (or its checkbox
    /// hit-target). See `TaskCompletionModifier` for phase semantics.
    func taskCompletionStyle(isCompleted: Bool,
                             theme: AppThemeCase,
                             onTrigger: @escaping () -> Void) -> some View {
        modifier(TaskCompletionModifier(isCompleted: isCompleted,
                                        theme: theme,
                                        onTrigger: onTrigger))
    }
}

// MARK: - CompletionCheckbox
//
// Companion glyph for the Light theme's Phase-3 "checkbox morphs into a solid
// filled circle" detail. The card-level slip/fade is handled by the modifier;
// this view morphs the mark itself. Drop it into the row's leading slot.

struct CompletionCheckbox: View {
    let isCompleted: Bool
    let palette: ThemePalette

    var body: some View {
        ZStack {
            // Empty state: hairline rounded square (Stark/Light) or ring.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(palette.prominent, lineWidth: 1.5)
                .opacity(isCompleted ? 0 : 1)
                .scaleEffect(isCompleted ? 0.6 : 1)

            // Filled state: solid circle with check — the morph target.
            Circle()
                .fill(palette.controlTint)
                .opacity(isCompleted ? 1 : 0)
                .scaleEffect(isCompleted ? 1 : 0.6)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.sheetBackground)
                        .opacity(isCompleted ? 1 : 0)
                )
        }
        .frame(width: 22, height: 22)
        .animation(KineticSpring.dissolve, value: isCompleted)
    }
}
