import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Mac_DesignKit
//
// Shared editorial primitives for the Mac visual layer. Everything here is
// theme-aware (reads a `ThemePalette`) and motion-aware (honors
// `accessibilityReduceMotion`). The only hardcoded color literals in the Mac
// target live in `Mac_Accent` — mint `#6EE7A8` (capture / focus identity) and
// violet `#7C3AED` (ideas / backlinks). Every other value traces to
// `ThemePalette` or `DesignTokens`.

// MARK: Brand literals
//
// `Mac_Accent.mint` is declared in Mac_ContentView.swift (the historical home);
// violet is added here so the two brand literals sit together conceptually.
extension Mac_Accent {
    /// Deep violet — ideas, idea type indicators, the backlinks panel.
    static let violet = Color(red: 124 / 255, green: 58 / 255, blue: 237 / 255)
}

// MARK: - Film grain
//
// A single monochrome noise tile generated once via CoreImage and rendered with
// an `.overlay` blend at a whisper opacity, giving the whole window a film-like
// texture that matches the iOS aesthetic. Theme-agnostic: overlay blend against
// mid-gray noise lightens/darkens by tiny deltas regardless of canvas color.
// Applied ONCE at the `Mac_ContentView` root — never per pane.

enum Mac_GrainTexture {
    /// Lazily built, process-wide cached. `nil` only if CoreImage is unavailable.
    static let tile: Image? = build()

    private static func build() -> Image? {
        let side = 200
        let extent = CGRect(x: 0, y: 0, width: side, height: side)
        guard let noise = CIFilter.randomGenerator().outputImage else { return nil }
        // Strip color → grayscale grain; keep neutral brightness so overlay is balanced.
        let mono = noise.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0,
            kCIInputBrightnessKey: 0.0,
            kCIInputContrastKey: 1.0
        ])
        let cropped = mono.cropped(to: extent)
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = ctx.createCGImage(cropped, from: extent) else { return nil }
        return Image(decorative: cg, scale: 1)
    }
}

struct Mac_FilmGrain: View {
    var opacity: Double = 0.035

    var body: some View {
        if let tile = Mac_GrainTexture.tile {
            tile
                .resizable(resizingMode: .tile)
                .opacity(opacity)
                .blendMode(.overlay)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Blur-fade pane transition
//
// The pane crossfade: opacity + a 4pt → 0 blur, 0.2s easeOut. Reduce-motion
// collapses it to a plain opacity crossfade.

private struct Mac_BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

extension AnyTransition {
    /// Opacity crossfade combined with a blur-in. Use with `.id(_:)` + an
    /// `.animation(_, value:)` on the switching value.
    static var macBlurFade: AnyTransition {
        .opacity.combined(with: .modifier(
            active: Mac_BlurModifier(radius: 4),
            identity: Mac_BlurModifier(radius: 0)
        ))
    }
}

// MARK: - Editorial display title
//
// The cinematic hero used by every primary pane. Enormous tight-tracked type
// (default 88pt), the title broken across lines with intent by the caller
// ("To\nday"), with an asymmetric meta column floated to the trailing side:
// a Space-Mono-feel ALL-CAPS label above a mint accent callout. The type
// dominates the left; the meta and live count hang off the right — deliberate
// spatial tension, never centered beneath.

struct Mac_DisplayTitle: View {
    @Environment(ThemeStore.self) private var theme

    /// Title text. Embed `\n` to break lines with intent.
    let title: String
    /// ALL-CAPS micro label (e.g. "MON · JUN 16"). Rendered top-right.
    var metaLabel: String? = nil
    /// Mint live-data callout (e.g. "12 ACTIVE"). Rendered under the meta label.
    var accentCallout: String? = nil
    /// Display point size — intentionally large.
    var size: CGFloat = 88

    var body: some View {
        let p = theme.palette
        HStack(alignment: .lastTextBaseline, spacing: 16) {
            Text(title)
                .font(.system(size: size, weight: .heavy, design: p.fontDesign))
                .tracking(size * -0.05)
                .lineSpacing(-size * 0.16)
                .foregroundStyle(p.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if metaLabel != nil || accentCallout != nil {
                VStack(alignment: .trailing, spacing: 8) {
                    if let metaLabel {
                        Text(metaLabel)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(2.2)
                            .textCase(.uppercase)
                            .foregroundStyle(p.textTertiary)
                    }
                    if let accentCallout {
                        Text(accentCallout)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1.6)
                            .textCase(.uppercase)
                            .foregroundStyle(Mac_Accent.mint)
                    }
                }
                .padding(.bottom, size * 0.16)
            }
        }
    }
}

// MARK: - Cinematic empty state
//
// The big dim editorial empty state per the brief: enormous low-opacity Inter
// over a small mint detail mark. Distinct from the Stark micro empty state —
// used where a pane has nothing to show and the silence should feel composed.

struct Mac_CinematicEmpty: View {
    @Environment(ThemeStore.self) private var theme

    let headline: String
    var footnote: String? = nil

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 22) {
            // The mint detail — a short accent rule, the "one moment".
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Mac_Accent.mint)
                .frame(width: 40, height: 3)

            Text(headline)
                .font(.system(size: 46, weight: .heavy, design: p.fontDesign))
                .tracking(-2)
                .foregroundStyle(p.textPrimary.opacity(0.14))
                .fixedSize(horizontal: false, vertical: true)

            if let footnote {
                Text(footnote)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(p.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
