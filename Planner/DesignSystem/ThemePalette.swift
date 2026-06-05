import SwiftUI

// MARK: - ThemePalette (Semantic Token Layer)
//
// A theme-agnostic bag of design intent. Views read from a `ThemePalette`
// instead of hardcoded `DesignTokens.*` so the same view can render in
// multiple visual languages (Stark dark/light, Calm Earth, Liquid Glass)
// without branching at the call site.
//
// Architecture:
//   • `AppThemeCase` is the user-facing enum (persisted via UserDefaults).
//   • `ThemePalette` is the rendering struct mapped from a case.
//   • `ThemedCard` / `themedCanvas` are the only view-side primitives that
//     know how to translate the palette into actual SwiftUI surfaces.
//
// Only Settings consumes this today. Other tabs still read from
// `DesignTokens` directly (Stark dark, hard-locked). A future phase walks
// each tab and swaps direct DesignTokens reads for palette reads — at
// which point every tab inherits the active theme automatically.

// MARK: Surface descriptors

/// How a card's background is composed.
enum SurfaceKind {
    /// Solid color fill — the Stark / Light / Earth path. Cheap and crisp.
    case flat(fill: Color)

    /// SwiftUI `Material` blur. `specular` adds a top-edge white→clear
    /// gradient stroke for the glossy Liquid Glass look.
    case material(Material, specular: Bool)
}

/// How the full-bleed page background is composed.
enum CanvasKind {
    case solid(Color)
    case gradient(stops: [Gradient.Stop], start: UnitPoint, end: UnitPoint)
}

// MARK: ThemePalette

struct ThemePalette: Identifiable {
    let id: AppThemeCase

    // Identity (mirrored from the case so callers don't double-dispatch).
    let displayName: String
    let glyph: String
    let colorScheme: ColorScheme

    // Surfaces
    let canvas: CanvasKind
    let cardSurface: SurfaceKind
    let cardBorder: Color
    let cardBorderWidth: CGFloat
    let cardRadius: CGFloat

    // Chrome / supporting surfaces (toolbars, swipe backdrops, row fills)
    let chromeSurface: Color    // elevated chrome (swipe backdrops, capsule bgs)
    let rowFill: Color          // opaque row backdrop — used as occluder over canvas
    let hairline: Color         // 1px separators & subtle borders
    let prominent: Color        // emphasized borders (selected states, focus rings)

    // Text
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    // Accent + interactive
    let accent: Color
    let controlTint: Color

    // Typography
    let fontDesign: Font.Design
    let displayTracking: CGFloat
    let headlineTracking: CGFloat
    let microTracking: CGFloat
}

// MARK: Factory

extension ThemePalette {

    static func make(for theme: AppThemeCase) -> ThemePalette {
        switch theme {
        case .dark:        return .starkDark
        case .light:       return .starkLight
        case .calmEarth:   return .calmEarth
        case .liquidGlass: return .liquidGlass
        }
    }

    // MARK: Stark Dark — the locked production aesthetic
    static let starkDark = ThemePalette(
        id: .dark,
        displayName: "Dark",
        glyph: "moon.fill",
        colorScheme: .dark,
        canvas: .solid(DesignTokens.Surface.canvas),
        cardSurface: .flat(fill: DesignTokens.Surface.card),
        cardBorder: DesignTokens.Stroke.hairline,
        cardBorderWidth: 1,
        cardRadius: DesignTokens.Radius.card,
        chromeSurface: DesignTokens.Surface.cardElevated,
        rowFill: DesignTokens.Surface.canvas,
        hairline: DesignTokens.Stroke.hairline,
        prominent: DesignTokens.Stroke.prominent,
        textPrimary: .white.opacity(0.92),
        textSecondary: .white.opacity(0.55),
        textTertiary: .white.opacity(0.32),
        accent: .white,
        controlTint: .white,
        fontDesign: .default,
        displayTracking: DesignTokens.Tracking.display,
        headlineTracking: DesignTokens.Tracking.headline,
        microTracking: DesignTokens.Tracking.micro
    )

    // MARK: Stark Light — clean off-white variant
    static let starkLight = ThemePalette(
        id: .light,
        displayName: "Light",
        glyph: "sun.max.fill",
        colorScheme: .light,
        canvas: .solid(Color(red: 0.976, green: 0.976, blue: 0.976)),  // #F9F9F9
        cardSurface: .flat(fill: .white),
        cardBorder: Color.black.opacity(0.08),
        cardBorderWidth: 1,
        cardRadius: DesignTokens.Radius.card,
        chromeSurface: Color(red: 0.93, green: 0.93, blue: 0.93),
        rowFill: Color(red: 0.976, green: 0.976, blue: 0.976),
        hairline: Color.black.opacity(0.08),
        prominent: Color.black.opacity(0.14),
        textPrimary: Color(red: 0.10, green: 0.11, blue: 0.13),        // deep slate
        textSecondary: Color(red: 0.35, green: 0.38, blue: 0.42),
        textTertiary: Color(red: 0.55, green: 0.58, blue: 0.62),
        accent: Color(red: 0.10, green: 0.11, blue: 0.13),
        controlTint: Color(red: 0.10, green: 0.11, blue: 0.13),
        fontDesign: .default,
        displayTracking: DesignTokens.Tracking.display,
        headlineTracking: DesignTokens.Tracking.headline,
        microTracking: DesignTokens.Tracking.micro
    )

    // MARK: Calm Earth — warm cream + olive, rounded typography
    static let calmEarth = ThemePalette(
        id: .calmEarth,
        displayName: "Calm Earth",
        glyph: "leaf.fill",
        colorScheme: .light,
        canvas: .solid(Color(red: 0.957, green: 0.929, blue: 0.871)),  // warm cream
        cardSurface: .flat(fill: Color(red: 0.984, green: 0.961, blue: 0.910)),
        cardBorder: Color(red: 0.40, green: 0.40, blue: 0.27).opacity(0.18),
        cardBorderWidth: 1,
        cardRadius: 20,
        chromeSurface: Color(red: 0.930, green: 0.898, blue: 0.835),   // deeper cream
        rowFill: Color(red: 0.957, green: 0.929, blue: 0.871),
        hairline: Color(red: 0.40, green: 0.40, blue: 0.27).opacity(0.12),
        prominent: Color(red: 0.40, green: 0.40, blue: 0.27).opacity(0.22),
        textPrimary: Color(red: 0.20, green: 0.24, blue: 0.18),        // deep forest
        textSecondary: Color(red: 0.36, green: 0.42, blue: 0.30),      // muted olive
        textTertiary: Color(red: 0.52, green: 0.55, blue: 0.42),       // sage
        accent: Color(red: 0.36, green: 0.46, blue: 0.28),             // deep olive
        controlTint: Color(red: 0.36, green: 0.46, blue: 0.28),
        fontDesign: .rounded,
        displayTracking: -0.4,
        headlineTracking: 0,
        microTracking: 1.0
    )

    // MARK: Liquid Glass — lavender→teal gradient + ultra-thin material
    static let liquidGlass = ThemePalette(
        id: .liquidGlass,
        displayName: "Liquid Glass",
        glyph: "sparkles",
        colorScheme: .dark,
        canvas: .gradient(
            stops: [
                .init(color: Color(red: 0.58, green: 0.50, blue: 0.86), location: 0.0), // lavender
                .init(color: Color(red: 0.45, green: 0.55, blue: 0.80), location: 0.5),
                .init(color: Color(red: 0.30, green: 0.58, blue: 0.74), location: 1.0)  // muted teal
            ],
            start: .topLeading,
            end: .bottomTrailing
        ),
        cardSurface: .material(.ultraThinMaterial, specular: true),
        cardBorder: .white.opacity(0.20),
        cardBorderWidth: 1,
        cardRadius: 22,
        chromeSurface: Color.white.opacity(0.10),
        rowFill: Color(red: 0.44, green: 0.53, blue: 0.78),             // gradient mid-tone
        hairline: Color.white.opacity(0.16),
        prominent: Color.white.opacity(0.28),
        textPrimary: .white.opacity(0.95),
        textSecondary: .white.opacity(0.72),
        textTertiary: .white.opacity(0.50),
        accent: .white,
        controlTint: .white,
        fontDesign: .rounded,
        displayTracking: -0.5,
        headlineTracking: -0.1,
        microTracking: 0.8
    )
}

// MARK: - Typography helpers
//
// Sites read these instead of `DesignTokens.Typography.*` when they want
// to honor the active palette's `fontDesign`. Sizes mirror DesignTokens
// 1:1 so the visual rhythm stays consistent across themes.

extension ThemePalette {
    /// Solid color suitable for sheet `presentationBackground`. Falls back
    /// to `rowFill` when the canvas itself is a gradient, since sheets need
    /// an opaque single-color surface.
    var sheetBackground: Color {
        switch canvas {
        case .solid(let c): return c
        case .gradient:     return rowFill
        }
    }

    func font(_ role: TypographyRole) -> Font {
        switch role {
        case .display:  return .system(size: 32, weight: .bold,     design: fontDesign)
        case .title:    return .system(size: 22, weight: .semibold, design: fontDesign)
        case .headline: return .system(size: 16, weight: .semibold, design: fontDesign)
        case .body:     return .system(size: 15, weight: .regular,  design: fontDesign)
        case .caption:  return .system(size: 13, weight: .regular,  design: fontDesign)
        case .micro:    return .system(size: 11, weight: .semibold, design: fontDesign)
        }
    }
}

enum TypographyRole {
    case display, title, headline, body, caption, micro
}

// MARK: - View primitives

extension View {
    /// Apply the palette's canvas as the view's background. Use on the
    /// outermost container of a themed surface.
    @ViewBuilder
    func themedCanvas(_ palette: ThemePalette) -> some View {
        switch palette.canvas {
        case .solid(let color):
            self.background(color.ignoresSafeArea())
        case .gradient(let stops, let start, let end):
            self.background(
                LinearGradient(stops: stops, startPoint: start, endPoint: end)
                    .ignoresSafeArea()
            )
        }
    }
}

extension ThemePalette {
    /// Standalone full-bleed canvas layer (solid or gradient) for composing
    /// the background as an explicit sibling at the base of a `ZStack`.
    /// Mirrors the `themedCanvas` modifier — single source of truth for the
    /// page backdrop across every tab.
    @ViewBuilder
    var canvasView: some View {
        switch canvas {
        case .solid(let color):
            color.ignoresSafeArea()
        case .gradient(let stops, let start, let end):
            LinearGradient(stops: stops, startPoint: start, endPoint: end)
                .ignoresSafeArea()
        }
    }
}

/// Hairline row divider shared by every list surface. Reads the active
/// palette from the environment so it stays theme-correct without a param.
struct RowSeparator: View {
    @Environment(ThemeStore.self) private var theme
    var body: some View {
        Rectangle()
            .fill(theme.palette.hairline)
            .frame(height: 0.5)
    }
}

/// Themed card. Switches between flat fills and `Material` based on the
/// palette's `cardSurface`. The specular highlight is an additive top-edge
/// stroke that only renders for `.material(_, specular: true)` — gives the
/// Liquid Glass theme its glossy gloss without affecting Stark surfaces.
struct ThemedCard<Content: View>: View {
    let palette: ThemePalette
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: palette.cardRadius, style: .continuous)
        content
            .background(background(shape: shape))
            .overlay(shape.strokeBorder(palette.cardBorder, lineWidth: palette.cardBorderWidth))
            .overlay(specularHighlight(shape: shape))
            .clipShape(shape)
    }

    @ViewBuilder
    private func background(shape: RoundedRectangle) -> some View {
        switch palette.cardSurface {
        case .flat(let fill):
            shape.fill(fill)
        case .material(let material, _):
            shape.fill(material)
        }
    }

    @ViewBuilder
    private func specularHighlight(shape: RoundedRectangle) -> some View {
        if case .material(_, let specular) = palette.cardSurface, specular {
            shape
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.55),
                            .white.opacity(0.10),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
    }
}
