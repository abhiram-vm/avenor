import SwiftUI

// MARK: - Mac_SettingsView
//
// macOS `Settings` scene content. v1.0 carries a single control: the theme
// picker (all four themes). Writes through the shared `ThemeStore`, so the
// choice propagates everywhere instantly and persists via its App Group /
// UserDefaults backing — exactly like iOS Settings.

struct Mac_SettingsView: View {
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        @Bindable var theme = theme
        Form {
            Picker("Theme", selection: $theme.selected) {
                ForEach(AppThemeCase.allCases) { option in
                    Label(option.title, systemImage: option.glyph)
                        .tag(option)
                }
            }
            .pickerStyle(.menu)
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .padding(20)
    }
}
