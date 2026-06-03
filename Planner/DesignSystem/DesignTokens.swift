import SwiftUI

// MARK: - DesignTokens
//
// Direction: "Sophisticated Stark" — an editorial, near-black canvas with
// crisp flat surfaces, hairline borders, and intentional desaturated accents.
// Inspired by Linear, Things 3, and modern bento-grid productivity tools.
//
// Token namespaces (Spacing / Radius / Stroke / Accent / Typography /
// Motion / Background) and view extensions (`.cardSurface()`, `.rowSurface()`,
// `.chipSurface()`, `.fieldSurface()`) are preserved verbatim so existing
// call sites continue to compile without modification.

enum DesignTokens {

    // MARK: Spacing
    enum Spacing {
        static let hairline: CGFloat = 0.5

        // Inside a card
        static let cardInset: CGFloat = 18
        static let cardSpacing: CGFloat = 14

        // Between cards
        static let stack: CGFloat = 16
        static let stackLarge: CGFloat = 28

        // Outer page padding
        static let pageHorizontal: CGFloat = 20
        static let pageTop: CGFloat = 12
        static let pageBottom: CGFloat = 40
    }

    // MARK: Radii
    //
    // Tighter, more architectural radii than the glass era. Cards sit closer
    // to a rectangle; chips remain capsules for legibility.
    enum Radius {
        static let chip: CGFloat = 999      // capsule
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let card: CGFloat = 16
        static let sheet: CGFloat = 24
    }

    // MARK: Stroke
    //
    // Hairline whites at low opacity. These are the load-bearing element of
    // the aesthetic — they replace the blurred materials as the source of
    // separation between surfaces.
    enum Stroke {
        static let hairline   = Color.white.opacity(0.06)
        static let prominent  = Color.white.opacity(0.10)
        static let interactive = Color.white.opacity(0.16)
    }

    // MARK: Accent colors
    //
    // Monochrome core (crisp white on near-black). Semantic accents are
    // clinical, desaturated, and used only to *identify* task type —
    // never for decoration.
    enum Accent {
        static let primary = Color.white

        static let todo     = Color(red: 0.62, green: 0.84, blue: 0.71) // clinical mint
        static let reminder = Color(red: 0.86, green: 0.66, blue: 0.42) // clay amber
        static let idea     = Color(red: 0.74, green: 0.72, blue: 0.84) // pale slate-lilac
        static let note     = Color(red: 0.56, green: 0.68, blue: 0.82) // cold slate blue

        static let success  = Color(red: 0.56, green: 0.82, blue: 0.66)
        static let warning  = Color(red: 0.88, green: 0.68, blue: 0.42)
    }

    // MARK: Surface fills
    //
    // Pitch-black card fills with a faint internal lift, so cards read as
    // *darker* than the canvas — the inversion that gives Linear its weight.
    enum Surface {
        static let canvas       = Color(red: 0.039, green: 0.039, blue: 0.047) // #0A0A0C
        static let card         = Color(red: 0.063, green: 0.063, blue: 0.075) // #101013
        static let cardElevated = Color(red: 0.078, green: 0.078, blue: 0.090) // #141417
        static let field        = Color(red: 0.055, green: 0.055, blue: 0.067) // #0E0E11
    }

    // MARK: Typography
    //
    // Editorial scale: Display / Title / Headline / Body / Caption / Micro.
    // Pair fonts with the call-site modifiers below (`.displayStyle()` etc.)
    // to apply tracking + line-spacing consistently.
    enum Typography {
        /// 32pt bold — tab page heroes ("Today", "Notes"). Tight tracking.
        static let display  = Font.system(size: 32, weight: .bold, design: .default)

        /// 22pt semibold — section heads.
        static let title    = Font.system(size: 22, weight: .semibold, design: .default)

        /// 16pt semibold — row titles.
        static let headline = Font.system(size: 16, weight: .semibold, design: .default)

        /// 15pt regular — body copy.
        static let body     = Font.system(size: 15, weight: .regular, design: .default)

        /// 13pt regular — supporting copy.
        static let caption  = Font.system(size: 13, weight: .regular, design: .default)

        /// 11pt semibold — tracked uppercase labels (pill text, etc.).
        static let micro    = Font.system(size: 11, weight: .semibold, design: .default)
    }

    // MARK: Tracking
    //
    // Centralized letter-spacing. Negative on large titles, positive on
    // tracked micro labels. Used by the typography view extensions.
    enum Tracking {
        static let display: CGFloat = -0.6
        static let title:   CGFloat = -0.3
        static let headline: CGFloat = -0.1
        static let body:    CGFloat = 0
        static let micro:   CGFloat = 0.8
    }

    // MARK: Motion
    enum Motion {
        /// Quick — chips, toggles, taps.
        static let snappy = Animation.spring(response: 0.26, dampingFraction: 0.88)
        /// Smooth — row expansions, sheet transitions.
        static let smooth = Animation.spring(response: 0.34, dampingFraction: 0.80)
    }

    // MARK: Background
    //
    // Uniform near-black canvas — no gradient, no orbs. `stops` is retained
    // (as a flat two-stop gradient) for any consumer still reading from it,
    // but the visual result is a single rich black.
    enum Background {
        static let canvas = Surface.canvas

        static let stops: [Gradient.Stop] = [
            .init(color: Surface.canvas, location: 0.00),
            .init(color: Surface.canvas, location: 1.00),
        ]

        // Retained for API compatibility; both fully transparent so any
        // legacy orb overlay renders as a no-op.
        static let orbA = Color.clear
        static let orbB = Color.clear
    }
}

// MARK: - Surface modifiers
//
// Crisp flat fills + hairline strokes. No materials, no blur. The whole
// point of "Sophisticated Stark" is that separation comes from precise
// tonal steps, not from translucency.

extension View {
    /// Primary card — pitch-black fill, hairline stroke.
    func cardSurface(radius: CGFloat = DesignTokens.Radius.card) -> some View {
        self
            .padding(DesignTokens.Spacing.cardInset)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(DesignTokens.Surface.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(DesignTokens.Stroke.hairline, lineWidth: 1)
            )
    }

    /// Nested row inside a card — slightly lifted fill, tighter radius.
    func rowSurface(radius: CGFloat = DesignTokens.Radius.medium) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(DesignTokens.Surface.cardElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(DesignTokens.Stroke.hairline, lineWidth: 1)
            )
    }

    /// Capsule chip — flat fill, optional semantic tint.
    func chipSurface(tint: Color? = nil) -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    tint?.opacity(0.14) ?? DesignTokens.Surface.cardElevated
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    tint?.opacity(0.36) ?? DesignTokens.Stroke.hairline,
                    lineWidth: 1
                )
            )
    }

    /// Compact input field surface.
    func fieldSurface(radius: CGFloat = DesignTokens.Radius.medium) -> some View {
        self
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(DesignTokens.Surface.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(DesignTokens.Stroke.hairline, lineWidth: 1)
            )
    }
}

// MARK: - Typography modifiers
//
// Editorial pairing: tracking + line spacing applied at the call site so
// every Text in the app reads from a single source of truth.

extension Text {
    /// Display: tight tracking, structural feel. Use for tab heroes.
    func displayStyle() -> some View {
        self
            .font(DesignTokens.Typography.display)
            .tracking(DesignTokens.Tracking.display)
            .lineSpacing(2)
            .foregroundStyle(DesignTokens.Accent.primary)
    }

    func titleStyle() -> some View {
        self
            .font(DesignTokens.Typography.title)
            .tracking(DesignTokens.Tracking.title)
            .lineSpacing(2)
    }

    func headlineStyle() -> some View {
        self
            .font(DesignTokens.Typography.headline)
            .tracking(DesignTokens.Tracking.headline)
    }

    func bodyStyle() -> some View {
        self
            .font(DesignTokens.Typography.body)
            .lineSpacing(3)
            .foregroundStyle(.white.opacity(0.78))
    }

    func captionStyle() -> some View {
        self
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(.white.opacity(0.55))
    }

    /// Micro: tracked uppercase label. Apply `.textCase(.uppercase)` at site
    /// if desired — left optional so non-label uses (counts) stay readable.
    func microStyle() -> some View {
        self
            .font(DesignTokens.Typography.micro)
            .tracking(DesignTokens.Tracking.micro)
            .foregroundStyle(.white.opacity(0.62))
    }
}
