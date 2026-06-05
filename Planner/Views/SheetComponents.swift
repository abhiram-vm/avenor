import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - SheetComponents
//
// Shared editorial primitives for the Phase-4 creation sheets (Add Task /
// Add Goal). Every primitive reads from an injected `ThemePalette` so the
// same view renders across Stark Dark/Light, Calm Earth, and Liquid Glass.
//
// Design intent: spacious floating cards, capitalized tracked section
// labels, tactile pill selectors (Pillar-1 compression physics), inline
// date disclosure (no full-screen system calendar), and an adaptive
// primary CTA that stays faded until the form is valid.

// MARK: - SectionLabel

/// Uppercase, tracked metadata label that heads a structural section
/// ("SECTION TITLE", "DUE DATE", "TARGET GOAL").
struct SectionLabel: View {
    let text: String
    let palette: ThemePalette

    init(_ text: String, palette: ThemePalette) {
        self.text = text
        self.palette = palette
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: palette.fontDesign))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(palette.textSecondary)
    }
}

// MARK: - InputSurface

/// Wraps a control in the theme's input chrome. For Liquid Glass this is a
/// translucent `.ultraThinMaterial` with a faint top specular; for the flat
/// themes it's the palette's `chromeSurface`. `filled: false` keeps the
/// surface clear (used by inline disclosure rows that sit on a card).
private struct InputSurface: ViewModifier {
    let palette: ThemePalette
    let radius: CGFloat
    let filled: Bool
    let emphasized: Bool

    private var isGlass: Bool {
        if case .material = palette.cardSurface { return true }
        return false
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(fill(shape))
            .overlay(
                shape.strokeBorder(
                    emphasized ? palette.prominent : palette.hairline,
                    lineWidth: isGlass ? 0.75 : 0.5
                )
            )
            .overlay(specular(shape))
            .clipShape(shape)
    }

    @ViewBuilder
    private func fill(_ shape: RoundedRectangle) -> some View {
        if !filled {
            shape.fill(Color.clear)
        } else if isGlass {
            shape.fill(.ultraThinMaterial)
        } else {
            shape.fill(palette.chromeSurface)
        }
    }

    @ViewBuilder
    private func specular(_ shape: RoundedRectangle) -> some View {
        if isGlass, filled {
            shape
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .white.opacity(0.05), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    func inputSurface(_ palette: ThemePalette,
                      radius: CGFloat = DesignTokens.Radius.small,
                      filled: Bool = true,
                      emphasized: Bool = false) -> some View {
        modifier(InputSurface(palette: palette, radius: radius, filled: filled, emphasized: emphasized))
    }
}

// MARK: - SheetTextField

/// Themed text field with editorial chrome. Supports vertical growth,
/// monospaced digits (for numeric entry), and keyboard/autocap config.
struct SheetTextField: View {
    let placeholder: String
    @Binding var text: String
    var palette: ThemePalette
    var axis: Axis = .horizontal
    var lineLimit: ClosedRange<Int>? = nil
    var autocapitalization: TextInputAutocapitalization = .sentences
    var keyboard: UIKeyboardType = .default
    var monospaced: Bool = false

    var body: some View {
        Group {
            if axis == .vertical, let lineLimit {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(lineLimit)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textInputAutocapitalization(autocapitalization)
        .keyboardType(keyboard)
        .font(monospaced
              ? .system(size: 15, weight: .regular, design: .monospaced)
              : palette.font(.body))
        .monospacedDigit()
        .foregroundStyle(palette.textPrimary)
        .tint(palette.controlTint)
        .padding(12)
        .inputSurface(palette)
    }
}

// MARK: - KineticButtonStyle
//
// Drives the Pillar-1 compression physics from the native button press
// state (`configuration.isPressed`) instead of a hand-rolled
// `DragGesture(minimumDistance: 0)`.
//
// Why this matters: a zero-distance drag gesture greedily claims the touch
// the instant a finger lands, which (a) starves an enclosing horizontal
// `ScrollView` of its pan — causing the choppy/locked preset tracks — and
// (b) is unreliable for taps, because SwiftUI does not guarantee `onChanged`
// fires before `onEnded` on a fast tap (so the "Create" action could
// silently never run). A real `Button` cooperates with scrolling and fires
// reliably; the style only paints the press feedback.
struct KineticButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(KineticSpring.compression, value: configuration.isPressed)
    }
}

// MARK: - KineticPill

/// A selectable pill that compresses under the thumb (Pillar-1
/// `KineticSpring.compression`) and fires a soft `AppHaptic.pop()` on tap.
/// Built on a native `Button` so it never steals the enclosing
/// `ScrollView`'s pan gesture.
struct KineticPill: View {
    let title: String
    let isSelected: Bool
    let palette: ThemePalette
    var fillWidth: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            AppHaptic.pop()
            action()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: palette.fontDesign))
                .tracking(palette.microTracking)
                .lineLimit(1)
                .foregroundStyle(isSelected ? palette.textPrimary : palette.textTertiary)
                .frame(maxWidth: fillWidth ? .infinity : nil)
                .padding(.horizontal, fillWidth ? 8 : 16)
                .frame(minHeight: 40)
                .inputSurface(palette, filled: isSelected, emphasized: isSelected)
                .contentShape(Rectangle())
        }
        .buttonStyle(KineticButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - DayLetterPill
//
// Compact circular day token for the multi-day selection matrix. Renders the
// absolute first letter of a weekday; the active state fills with
// `palette.accent` and inverts the glyph for contrast. Equal-width via an
// expanding frame so a row of seven reads as a clean grid.

struct DayLetterPill: View {
    let letter: String
    let isSelected: Bool
    let palette: ThemePalette
    let action: () -> Void

    var body: some View {
        Button {
            AppHaptic.pop()
            action()
        } label: {
            Text(letter)
                .font(.system(size: 13, weight: .bold, design: palette.fontDesign))
                .foregroundStyle(isSelected ? palette.rowFill : palette.textTertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    Circle().fill(isSelected ? palette.accent : palette.chromeSurface)
                )
                .overlay(
                    Circle().strokeBorder(isSelected ? Color.clear : palette.hairline, lineWidth: 0.5)
                )
                .contentShape(Circle())
        }
        .buttonStyle(KineticButtonStyle())
        .accessibilityLabel(letter)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - InlineDateDrawer

/// A collapsible date/time disclosure. A toggle arms the deadline; once
/// armed, a tappable summary row expands a graphical picker inline (no
/// full-screen system sheet). Animates with `DesignTokens.Motion.smooth`.
struct InlineDateDrawer: View {
    let title: String
    @Binding var isEnabled: Bool
    @Binding var date: Date
    let palette: ThemePalette

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $isEnabled.animation(DesignTokens.Motion.smooth)) {
                SectionLabel(title, palette: palette)
            }
            .tint(palette.controlTint)

            if isEnabled {
                summaryRow
                if expanded {
                    DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .tint(palette.controlTint)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .onChange(of: isEnabled) { _, on in
            if !on { withAnimation(DesignTokens.Motion.smooth) { expanded = false } }
        }
    }

    private var summaryRow: some View {
        Button {
            AppHaptic.tap()
            withAnimation(DesignTokens.Motion.smooth) { expanded.toggle() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(palette.font(.body))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .inputSurface(palette)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PrimaryActionButton

/// Full-width pinned CTA. Faded + inert until `enabled`; animates its
/// unlock with `DesignTokens.Motion.smooth`. Compresses + pops on tap.
/// Native `Button` underneath so the tap always commits.
struct PrimaryActionButton: View {
    let title: String
    let enabled: Bool
    let palette: ThemePalette
    let action: () -> Void

    var body: some View {
        Button {
            AppHaptic.pop()
            action()
        } label: {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: palette.fontDesign))
                .tracking(palette.headlineTracking)
                .foregroundStyle(enabled ? palette.sheetBackground : palette.textTertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
                        .fill(enabled ? palette.controlTint : palette.chromeSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
                        .strokeBorder(palette.hairline, lineWidth: enabled ? 0 : 0.5)
                )
                .opacity(enabled ? 1 : 0.45)
                .contentShape(Rectangle())
        }
        .buttonStyle(KineticButtonStyle(pressedScale: 0.97))
        .disabled(!enabled)
        .animation(DesignTokens.Motion.smooth, value: enabled)
        .accessibilityLabel(Text(title))
    }
}
