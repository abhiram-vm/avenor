import SwiftUI

// MARK: - Mac_SettingsView
//
// macOS `Settings` scene content. Dark, minimal, editorial — part of the app,
// not a system dialog. The single control is the theme picker, rendered as four
// live preview tiles (each shows that theme's actual canvas + accent), not a
// `Picker`. Selecting one remorphs the whole app instantly via the shared
// `ThemeStore` (App Group / UserDefaults backed), exactly like iOS Settings.

struct Mac_SettingsView: View {
    @Environment(ThemeStore.self) private var theme

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        @Bindable var theme = theme
        let p = theme.palette
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Appearance")
                    .font(.system(size: 34, weight: .heavy, design: p.fontDesign))
                    .tracking(-1.4)
                    .foregroundStyle(p.textPrimary)
                Text("Theme")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(2.0)
                    .textCase(.uppercase)
                    .foregroundStyle(p.textTertiary)
            }

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(AppThemeCase.allCases) { option in
                    ThemeSwatchTile(
                        option: option,
                        selected: theme.selected == option,
                        onSelect: { theme.selected = option }
                    )
                }
            }
        }
        .padding(28)
        .frame(width: 460)
        .themedCanvas(p)
    }
}

// MARK: - ThemeSwatchTile
//
// A live preview tile: the theme's real canvas behind a mint + accent swatch
// pair, the name in mono caps, a mint border + check when selected.

private struct ThemeSwatchTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let option: AppThemeCase
    let selected: Bool
    var onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        let preview = ThemePalette.make(for: option)
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)

        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                // Live canvas preview with a mint + theme-accent swatch pair.
                ZStack(alignment: .bottomLeading) {
                    preview.canvasView
                    HStack(spacing: 6) {
                        Circle().fill(Mac_Accent.mint).frame(width: 12, height: 12)
                        Circle().fill(preview.accent).frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(preview.hairline, lineWidth: 1))
                    }
                    .padding(10)
                }
                .frame(height: 76)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )

                HStack(spacing: 6) {
                    Text(option.title)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(selected ? Mac_Accent.mint : .white.opacity(0.55))
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Mac_Accent.mint)
                    }
                }
            }
            .padding(10)
            .background(shape.fill(.white.opacity(hovering ? 0.05 : 0.02)))
            .overlay(
                shape.strokeBorder(selected ? Mac_Accent.mint : .white.opacity(0.08),
                                   lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selected)
    }
}
