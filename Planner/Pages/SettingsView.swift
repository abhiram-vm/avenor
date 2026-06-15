import SwiftUI
import SwiftData
import Combine

// MARK: - SettingsView (Token-Driven)
//
// Single-screen settings surface. Reads every visual decision from
// `theme.palette` — never from `DesignTokens` directly. That lets the
// same view render in four distinct visual languages (Stark Dark/Light,
// Calm Earth, Liquid Glass) without duplicate code paths.
//
// Sections:
//   1. Profile         — editable name + tier slot
//   2. Appearance      — 2x2 tile grid of theme previews, persisted
//   3. Preferences     — Haptics, Smart Notifications, Account Info link
//   4. Support & Legal — Help, Privacy, Rate
//   5. Footer          — build + version
//
// Only Settings is token-aware today. Other tabs still bind to the locked
// Stark `DesignTokens`. A future phase walks each tab and swaps reads.

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeStore.self) private var theme

    @AppStorage(Preferences.hapticsKey)       private var hapticsEnabled: Bool       = true
    @AppStorage(Preferences.notificationsKey) private var notificationsEnabled: Bool = true
    @AppStorage(Preferences.displayNameKey)   private var displayName: String        = ""
    @AppStorage(Preferences.proTierKey)       private var proTier: Bool              = false

    // BETA ENGINE DIAGNOSTICS — compiled into DEBUG builds and into any
    // build that defines the `INTERNAL_BETA` active-compilation flag (add it
    // to the TestFlight beta scheme's Swift flags to surface diagnostics in
    // Release-config internal betas). Stripped from the public App Store build.
    #if DEBUG || INTERNAL_BETA
    @Environment(\.modelContext) private var modelContext
    @State private var pendingBacklog: Int = 0
    private let diagnosticsTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    #endif

    var body: some View {
        let palette = theme.palette

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    header(palette)
                    profileSection(palette)
                    appearanceSection(palette)
                    preferencesSection(palette)
                    supportSection(palette)
                    #if DEBUG || INTERNAL_BETA
                    betaDiagnosticsSection(palette)
                    #endif
                    footer(palette)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
            .themedCanvas(palette)
            .navigationTitle("Settings")
            .avenorInlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .avenorTrailing) {
                    Button("Close") { dismiss() }
                        .font(palette.font(.micro))
                        .tracking(palette.microTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .preferredColorScheme(palette.colorScheme)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: theme.selected)
    }

    // MARK: Header

    private func header(_ p: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(p.font(.display))
                .tracking(p.displayTracking)
                .foregroundStyle(p.textPrimary)

            Text("Tune the workspace.")
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .foregroundStyle(p.textTertiary)
        }
    }

    // MARK: Profile

    private func profileSection(_ p: ThemePalette) -> some View {
        SettingsCard(label: "Profile", palette: p) {
            HStack(spacing: 14) {
                avatar(p)

                VStack(alignment: .leading, spacing: 6) {
                    TextField(
                        "",
                        text: $displayName,
                        prompt: Text("Display name").foregroundColor(p.textTertiary)
                    )
                    .font(p.font(.headline))
                    .tracking(p.headlineTracking)
                    .tint(p.accent)
                    .foregroundStyle(p.textPrimary)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif
                    .autocorrectionDisabled()

                    Text("Local profile · no account required")
                        .font(p.font(.micro))
                        .tracking(p.microTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(p.textTertiary)
                }

                Spacer(minLength: 0)

                tierBadge(p)
            }
        }
    }

    private func avatar(_ p: ThemePalette) -> some View {
        ZStack {
            Circle()
                .fill(p.cardBorder.opacity(0.6))
                .frame(width: 48, height: 48)
                .overlay(
                    Circle().strokeBorder(p.cardBorder, lineWidth: 1)
                )
            Text(monogram)
                .font(.system(size: 17, weight: .semibold, design: p.fontDesign))
                .foregroundStyle(p.textPrimary)
                .monospacedDigit()
        }
    }

    private var monogram: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first.map { String($0).uppercased() } ?? "•"
    }

    private func tierBadge(_ p: ThemePalette) -> some View {
        Text(proTier ? "PRO" : "FREE")
            .font(p.font(.micro))
            .tracking(p.microTracking)
            .textCase(.uppercase)
            .monospacedDigit()
            .foregroundStyle(proTier ? p.textPrimary : p.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(p.cardBorder.opacity(0.4))
            )
            .overlay(
                Capsule().strokeBorder(p.cardBorder, lineWidth: 1)
            )
    }

    // MARK: Appearance

    private func appearanceSection(_ p: ThemePalette) -> some View {
        SettingsCard(label: "Appearance", palette: p) {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(AppThemeCase.allCases) { mode in
                        ThemeOptionTile(
                            previewPalette: .make(for: mode),
                            activePalette: p,
                            isSelected: theme.selected == mode,
                            onTap: { select(mode) }
                        )
                    }
                }

            }
        }
    }

    private func select(_ mode: AppThemeCase) {
        guard theme.selected != mode else { return }
        AppHaptic.tap()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            theme.selected = mode
        }
    }

    // MARK: Preferences

    private func preferencesSection(_ p: ThemePalette) -> some View {
        SettingsCard(label: "Preferences", palette: p) {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    palette: p,
                    title: "Haptic Feedback",
                    caption: "Subtle pulses on swipes, completions, and commits.",
                    isOn: $hapticsEnabled,
                    onToggle: { AppHaptic.tap() }
                )
                hairline(p)
                SettingsToggleRow(
                    palette: p,
                    title: "Smart Notifications",
                    caption: "Local reminders fired at task deadlines.",
                    isOn: $notificationsEnabled,
                    onToggle: { AppHaptic.tap() }
                )
                hairline(p)
                NavigationLink {
                    AccountInfoView()
                } label: {
                    SettingsLinkRow(
                        palette: p,
                        title: "Account Info",
                        caption: "Local profile · iCloud sync · data export."
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Support & Legal

    private func supportSection(_ p: ThemePalette) -> some View {
        SettingsCard(label: "Support & Legal", palette: p) {
            VStack(spacing: 0) {
                NavigationLink {
                    HelpFAQView()
                } label: {
                    SettingsLinkRow(palette: p, title: "Help & FAQ", caption: nil)
                }
                .buttonStyle(.plain)

                hairline(p)

                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    SettingsLinkRow(palette: p, title: "Privacy Policy", caption: nil)
                }
                .buttonStyle(.plain)

                hairline(p)

                websiteRow(p)

                hairline(p)

                Button {
                    requestAppStoreReview()
                } label: {
                    SettingsLinkRow(palette: p, title: "Rate Avenor", caption: nil)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @Environment(\.openURL) private var openURL

    private func websiteRow(_ p: ThemePalette) -> some View {
        Button {
            AppHaptic.tap()
            if let url = URL(string: "https://avenorus.app") {
                openURL(url)
            }
        } label: {
            SettingsLinkRow(
                palette: p,
                title: "Official Website",
                caption: "Explore guides and updates at avenorus.app"
            )
        }
        .buttonStyle(.plain)
    }

    private func requestAppStoreReview() {
        AppHaptic.tap()
        #if canImport(UIKit)
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        {
            AppReviewRequester.request(in: scene)
        }
        #endif
    }

    // MARK: Beta Engine Diagnostics
    //
    // Internal-beta-only instrumentation card. Surfaces the health of the
    // widget IPC layer: whether the App Group "vault" is reachable, and how
    // many widget taps are still queued awaiting `WidgetActionApplier`. The
    // Flush button drains the queue on demand for manual smoke-testing.

    #if DEBUG || INTERNAL_BETA
    private func betaDiagnosticsSection(_ p: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Beta Engine Diagnostics")
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .foregroundStyle(p.textTertiary)

            VStack(alignment: .leading, spacing: 0) {
                vaultStatusRow(p)
                hairline(p)
                backlogRow(p)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .inputSurface(p)
        }
        .onAppear { refreshBacklog() }
        .onReceive(diagnosticsTimer) { _ in refreshBacklog() }
    }

    /// Shared Vault Status — green/CONNECTED when the App Group container is
    /// reachable, red/DISCONNECTED when the entitlement isn't configured.
    private func vaultStatusRow(_ p: ThemePalette) -> some View {
        let connected = WidgetAppGroup.defaults != nil
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Shared Vault Status")
                    .font(p.font(.headline))
                    .tracking(p.headlineTracking)
                    .foregroundStyle(p.textPrimary)
                Text(WidgetAppGroup.identifier)
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .monospacedDigit()
                    .foregroundStyle(p.textTertiary)
            }
            Spacer(minLength: 12)
            statusPill(
                connected ? "Connected" : "Disconnected",
                color: connected ? .green : .red,
                palette: p
            )
        }
        .padding(.vertical, 12)
    }

    /// Pending Queue Backlog — live counter of unapplied widget commands
    /// sitting in the App Group queue, plus the on-demand Flush action.
    private func backlogRow(_ p: ThemePalette) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pending Queue Backlog")
                    .font(p.font(.headline))
                    .tracking(p.headlineTracking)
                    .foregroundStyle(p.textPrimary)
                Text("\(pendingBacklog) command\(pendingBacklog == 1 ? "" : "s") awaiting apply")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .monospacedDigit()
                    .foregroundStyle(p.textTertiary)
            }
            Spacer(minLength: 12)
            flushButton(p)
        }
        .padding(.vertical, 12)
    }

    private func statusPill(_ title: String, color: Color, palette p: ThemePalette) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .foregroundStyle(p.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(p.cardBorder.opacity(0.4)))
        .overlay(Capsule().strokeBorder(p.cardBorder, lineWidth: 1))
    }

    private func flushButton(_ p: ThemePalette) -> some View {
        Button {
            flushQueue()
        } label: {
            Text("Flush Queue")
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .foregroundStyle(p.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .inputSurface(p, emphasized: true)
        }
        .buttonStyle(.plain)
    }

    private func refreshBacklog() {
        pendingBacklog = WidgetActionQueue.peek().count
    }

    /// Soft tactile tick, then drain + apply the queued widget commands
    /// immediately so the backlog counter drops to zero in front of the user.
    private func flushQueue() {
        AppHaptic.pop()
        WidgetActionApplier.drainAndApply(in: modelContext)
        refreshBacklog()
    }
    #endif

    // MARK: Footer

    private func footer(_ p: ThemePalette) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(footerText)
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .monospacedDigit()
                .foregroundStyle(p.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private var footerText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = (info["CFBundleShortVersionString"] as? String) ?? "—"
        let build = (info["CFBundleVersion"] as? String) ?? "—"
        return "Avenor · v\(short) (\(build))"
    }

    // MARK: Shared

    private func hairline(_ p: ThemePalette) -> some View {
        Rectangle().fill(p.cardBorder).frame(height: 0.5)
    }
}

// MARK: - SettingsCard
//
// Section wrapper. The visible "card" is a `ThemedCard` so its surface
// (flat / material / specular) is driven entirely by the palette. The
// label above stays in micro-tracked uppercase across themes — the only
// thing that shifts is the font design (`.default` ⇄ `.rounded`).

struct SettingsCard<Content: View>: View {
    let label: String
    let palette: ThemePalette
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(palette.font(.micro))
                .tracking(palette.microTracking)
                .textCase(.uppercase)
                .foregroundStyle(palette.textTertiary)

            ThemedCard(palette: palette) {
                VStack(alignment: .leading, spacing: 0) {
                    content
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
            }
        }
    }
}

// MARK: - SettingsRow primitives

/// Generic two-line row: title + optional caption. Reads colors and font
/// design from the supplied palette so call sites stay theme-agnostic.
struct SettingsRow: View {
    let palette: ThemePalette
    let title: String
    let caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(palette.font(.headline))
                .tracking(palette.headlineTracking)
                .foregroundStyle(palette.textPrimary)

            if let caption {
                Text(caption)
                    .font(palette.font(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
        }
    }
}

struct SettingsToggleRow: View {
    let palette: ThemePalette
    let title: String
    let caption: String?
    @Binding var isOn: Bool
    var onToggle: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            SettingsRow(palette: palette, title: title, caption: caption)
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(palette.controlTint)
                .onChange(of: isOn) { _, _ in onToggle?() }
        }
        .padding(.vertical, 10)
    }
}

struct SettingsLinkRow: View {
    let palette: ThemePalette
    let title: String
    let caption: String?

    var body: some View {
        HStack(spacing: 14) {
            SettingsRow(palette: palette, title: title, caption: caption)
            Spacer(minLength: 12)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold, design: palette.fontDesign))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - ThemeOptionTile
//
// A live miniature of the theme it represents — uses that theme's own
// palette to render its preview surface, glyph, and label. The selection
// indicator (border promotion + checkmark) reads from the *active*
// palette so it always contrasts with the current page background.

struct ThemeOptionTile: View {
    let previewPalette: ThemePalette
    let activePalette: ThemePalette
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ThemedCard(palette: previewPalette) {
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: previewPalette.glyph)
                            .font(.system(size: 16, weight: .semibold, design: previewPalette.fontDesign))
                            .foregroundStyle(previewPalette.textPrimary)
                        Spacer(minLength: 0)
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(previewPalette.accent)
                                .symbolRenderingMode(.hierarchical)
                        }
                    }

                    Text(previewPalette.displayName)
                        .font(.system(size: 13, weight: .semibold, design: previewPalette.fontDesign))
                        .tracking(previewPalette.microTracking)
                        .foregroundStyle(previewPalette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    miniaturePreview
                }
                .padding(14)
            }
            .overlay(
                RoundedRectangle(cornerRadius: previewPalette.cardRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? activePalette.accent.opacity(0.85) : .clear,
                        lineWidth: isSelected ? 1.5 : 0
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.26, dampingFraction: 0.88), value: isSelected)
    }

    /// Three stacked rectangles inside the tile — a tiny visual signature
    /// of the theme's text + accent hierarchy. Cheaper and more readable
    /// than a full "fake row" preview.
    private var miniaturePreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(previewPalette.textPrimary).frame(width: 38, height: 4)
            Capsule().fill(previewPalette.textSecondary).frame(width: 56, height: 3)
            Capsule().fill(previewPalette.accent).frame(width: 22, height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Detail destinations

struct AccountInfoView: View {
    var body: some View {
        ThemedDetailScaffold(title: "Account") {
            Text("""
            Avenor is fully local. There is no account to sign in to. Your data lives in SwiftData on this device and, if iCloud is enabled in iOS Settings, syncs through your private CloudKit container.

            To export, screenshot or use the Files app — a JSON export is coming in a later release.
            """)
        }
    }
}

struct WidgetConfigurationView: View {
    var body: some View {
        ThemedDetailScaffold(title: "Widgets") {
            Text("""
            Avenor ships two widgets: Today Glance and Goal Progress.

            To add one:
              1.  Long-press the home screen.
              2.  Tap +, search "Avenor".
              3.  Pick a size and tap Add Widget.

            Widgets refresh on every app foreground transition and roughly every 15 minutes in the background.
            """)
        }
    }
}

struct HelpFAQView: View {
    var body: some View {
        ThemedDetailScaffold(title: "Help & FAQ") {
            Text("Documentation is coming. For now, sweep right to complete, left to remove, and hold a goal to scrub its value.")
        }
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ThemedDetailScaffold(title: "Privacy") {
            Text("""
            Avenor stores your tasks, notes, and goals on-device using SwiftData. If you enable iCloud, the same data syncs through your private CloudKit container — Apple-encrypted, never visible to us.

            No analytics, no third-party SDKs, no advertising identifiers. The app does not collect or transmit personal information.
            """)
        }
    }
}

/// Themed scaffold for detail pages reached from Settings. Same canvas,
/// same typography, palette-driven — so navigation feels native to the
/// active theme without a per-page rebuild.
struct ThemedDetailScaffold<Content: View>: View {
    @Environment(ThemeStore.self) private var theme
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        let p = theme.palette
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(p.font(.title))
                    .tracking(-0.3)
                    .foregroundStyle(p.textPrimary)

                content
                    .font(p.font(.body))
                    .lineSpacing(4)
                    .foregroundStyle(p.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .themedCanvas(p)
        .navigationTitle(title)
        .avenorInlineNavTitle()
        .preferredColorScheme(p.colorScheme)
    }
}

// MARK: - AppReviewRequester

#if canImport(UIKit)
import StoreKit

enum AppReviewRequester {
    static func request(in scene: UIWindowScene) {
        SKStoreReviewController.requestReview(in: scene)
    }
}
#endif

#Preview("Stark Dark") {
    SettingsView()
        .environment(ThemeStore())
}

#Preview("Liquid Glass") {
    let store = ThemeStore()
    store.selected = .liquidGlass
    return SettingsView().environment(store)
}

#Preview("Calm Earth") {
    let store = ThemeStore()
    store.selected = .calmEarth
    return SettingsView().environment(store)
}
