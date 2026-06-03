import SwiftUI
import WidgetKit

// MARK: - WidgetTheme
//
// Widget-side mirror of the main app's `ThemePalette`. Self-contained
// (no cross-target imports of DesignTokens/ThemePalette) so the widget
// bundle stays minimal and compiles independently.
//
// The widget reads the user's selected theme from shared App Group
// UserDefaults (`group.com.avenor.planner`, key `theme.selected.v2`)
// every time iOS asks for a timeline. The main app reloads timelines
// whenever the user picks a new theme so the lock-screen visuals stay
// in sync with the in-app palette.

// MARK: WidgetThemeID

/// Raw values match `AppThemeCase` exactly so the two enums can round-trip
/// through UserDefaults without a translation layer.
enum WidgetThemeID: String {
    case dark
    case light
    case calmEarth
    case liquidGlass

    /// Falls back to `.dark` when the persisted value is missing, unknown,
    /// or the App Group isn't reachable from the widget process. The `.dark`
    /// case is the deliberate, hardcoded debug fallback — `.starkDark` is a
    /// known-good opaque-black palette that guarantees text contrast against
    /// the rendered canvas no matter what the system widget default is.
    static func current() -> WidgetThemeID {
        guard let defaults = WidgetAppGroup.defaults else {
            // App Group entitlement misconfigured or not reachable from the
            // widget process. Hard-default to dark so the widget never
            // renders against the system white fallback background.
            return .dark
        }
        // Cross-process flush — see `WidgetPalette.current()` for the
        // rationale. Widget IPC is exactly the case `synchronize()` is
        // still documented to support.
        defaults.synchronize()
        guard let raw = defaults.string(forKey: WidgetAppGroup.themeSelectedKey) else {
            return .dark
        }
        return WidgetThemeID(rawValue: raw) ?? .dark
    }
}

// MARK: Surface descriptors

enum WidgetCanvas {
    case solid(Color)
    case gradient(stops: [Gradient.Stop], start: UnitPoint, end: UnitPoint)
}

enum WidgetCardSurface {
    case flat(Color)
    case material(Material, specular: Bool)
}

// MARK: WidgetPalette

struct WidgetPalette {
    let id: WidgetThemeID

    // Surfaces
    let canvas: WidgetCanvas
    let cardSurface: WidgetCardSurface
    let cardBorder: Color
    let cardRadius: CGFloat

    // Chrome
    let hairline: Color
    let chromeSurface: Color

    // Text
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    // Accent
    let accent: Color

    // Typography
    let fontDesign: Font.Design
    let displayTracking: CGFloat
    let headlineTracking: CGFloat
    let microTracking: CGFloat
    let colorScheme: ColorScheme
}

// MARK: Factory

extension WidgetPalette {

    /// Reads the active theme from the App Group and materializes a palette.
    /// Any decode/lookup failure short-circuits directly to `.starkDark` —
    /// the opaque-black palette is the known-good debug fallback so the
    /// widget never blanks out against the system white background.
    static func current() -> WidgetPalette {
        guard let defaults = WidgetAppGroup.defaults else { return .starkDark }
        // Force the App Group suite to drop any in-process cache and
        // re-read from disk. Without this the widget process can serve a
        // stale value from the previous timeline tick even after the main
        // app writes a new theme + reloads timelines. `synchronize()` is
        // the documented bridge for cross-process UserDefaults reads —
        // its single-process deprecation does not apply to widget IPC.
        defaults.synchronize()
        guard let raw = defaults.string(forKey: WidgetAppGroup.themeSelectedKey),
              let id = WidgetThemeID(rawValue: raw)
        else { return .starkDark }
        return .make(for: id)
    }

    static func make(for id: WidgetThemeID) -> WidgetPalette {
        switch id {
        case .dark:        return .starkDark
        case .light:       return .starkLight
        case .calmEarth:   return .calmEarth
        case .liquidGlass: return .liquidGlass
        }
    }

    // MARK: Stark Dark

    static let starkDark = WidgetPalette(
        id: .dark,
        canvas: .solid(Color(red: 0.039, green: 0.039, blue: 0.047)),  // #0A0A0C
        cardSurface: .flat(Color(red: 0.063, green: 0.063, blue: 0.075)), // #101013
        cardBorder: .white.opacity(0.08),
        cardRadius: 16,
        hairline: .white.opacity(0.08),
        chromeSurface: Color(red: 0.078, green: 0.078, blue: 0.090),   // #141417
        textPrimary: .white.opacity(0.92),
        textSecondary: .white.opacity(0.55),
        textTertiary: .white.opacity(0.32),
        accent: .white,
        fontDesign: .default,
        displayTracking: -0.6,
        headlineTracking: -0.1,
        microTracking: 0.8,
        colorScheme: .dark
    )

    // MARK: Stark Light

    static let starkLight = WidgetPalette(
        id: .light,
        canvas: .solid(Color(red: 0.976, green: 0.976, blue: 0.976)),  // #F9F9F9
        cardSurface: .flat(.white),
        cardBorder: .black.opacity(0.08),
        cardRadius: 16,
        hairline: .black.opacity(0.08),
        chromeSurface: Color(red: 0.93, green: 0.93, blue: 0.93),
        textPrimary: Color(red: 0.10, green: 0.11, blue: 0.13),
        textSecondary: Color(red: 0.35, green: 0.38, blue: 0.42),
        textTertiary: Color(red: 0.55, green: 0.58, blue: 0.62),
        accent: Color(red: 0.10, green: 0.11, blue: 0.13),
        fontDesign: .default,
        displayTracking: -0.6,
        headlineTracking: -0.1,
        microTracking: 0.8,
        colorScheme: .light
    )

    // MARK: Calm Earth

    static let calmEarth = WidgetPalette(
        id: .calmEarth,
        canvas: .solid(Color(red: 0.957, green: 0.929, blue: 0.871)),  // warm cream
        cardSurface: .flat(Color(red: 0.984, green: 0.961, blue: 0.910)),
        cardBorder: Color(red: 0.40, green: 0.40, blue: 0.27).opacity(0.18),
        cardRadius: 20,
        hairline: Color(red: 0.40, green: 0.40, blue: 0.27).opacity(0.12),
        chromeSurface: Color(red: 0.930, green: 0.898, blue: 0.835),
        textPrimary: Color(red: 0.20, green: 0.24, blue: 0.18),
        textSecondary: Color(red: 0.36, green: 0.42, blue: 0.30),
        textTertiary: Color(red: 0.52, green: 0.55, blue: 0.42),
        accent: Color(red: 0.36, green: 0.46, blue: 0.28),
        fontDesign: .rounded,
        displayTracking: -0.4,
        headlineTracking: 0,
        microTracking: 1.0,
        colorScheme: .light
    )

    // MARK: Liquid Glass

    static let liquidGlass = WidgetPalette(
        id: .liquidGlass,
        canvas: .gradient(
            stops: [
                .init(color: Color(red: 0.58, green: 0.50, blue: 0.86), location: 0.0),
                .init(color: Color(red: 0.45, green: 0.55, blue: 0.80), location: 0.5),
                .init(color: Color(red: 0.30, green: 0.58, blue: 0.74), location: 1.0)
            ],
            start: .topLeading,
            end: .bottomTrailing
        ),
        cardSurface: .material(.ultraThinMaterial, specular: true),
        cardBorder: .white.opacity(0.20),
        cardRadius: 22,
        hairline: .white.opacity(0.16),
        chromeSurface: .white.opacity(0.10),
        textPrimary: .white.opacity(0.95),
        textSecondary: .white.opacity(0.72),
        textTertiary: .white.opacity(0.50),
        accent: .white,
        fontDesign: .rounded,
        displayTracking: -0.5,
        headlineTracking: -0.1,
        microTracking: 0.8,
        colorScheme: .dark
    )
}

// MARK: Typography

enum WidgetTypographyRole {
    case display, title, headline, body, caption, micro
}

extension WidgetPalette {
    func font(_ role: WidgetTypographyRole) -> Font {
        switch role {
        case .display:  return .system(size: 36, weight: .bold,     design: fontDesign)
        case .title:    return .system(size: 22, weight: .semibold, design: fontDesign)
        case .headline: return .system(size: 14, weight: .semibold, design: fontDesign)
        case .body:     return .system(size: 13, weight: .regular,  design: fontDesign)
        case .caption:  return .system(size: 12, weight: .regular,  design: fontDesign)
        case .micro:    return .system(size: 10, weight: .semibold, design: fontDesign)
        }
    }
}

// MARK: - WidgetThemedCard
//
// Mirrors the main app's `ThemedCard`. Resolves to a flat fill for Stark
// themes and an `ultraThinMaterial` for Liquid Glass, with an optional
// specular top-edge highlight.

struct WidgetThemedCard<Content: View>: View {
    let palette: WidgetPalette
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: palette.cardRadius, style: .continuous)
        content
            .background(background(shape: shape))
            .overlay(shape.strokeBorder(palette.cardBorder, lineWidth: 1))
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

// MARK: - Container background

/// View used as the widget's `containerBackground`. Renders the palette's
/// canvas (solid or gradient) full-bleed behind all widget content.
///
/// Wrapped in a ZStack with an explicit `frame(maxWidth:maxHeight:)` so the
/// resolved color/gradient is guaranteed to occupy the entire container —
/// some iOS builds otherwise treat a bare `Color` as zero-sized and fall
/// back to the system widget default (which is what produces white-on-white
/// when the palette text colors are also white).
struct WidgetCanvasView: View {
    let palette: WidgetPalette

    var body: some View {
        ZStack {
            switch palette.canvas {
            case .solid(let color):
                color
                    .ignoresSafeArea(.all)
            case .gradient(let stops, let start, let end):
                LinearGradient(stops: stops, startPoint: start, endPoint: end)
                    .ignoresSafeArea(.all)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.all)
    }
}
