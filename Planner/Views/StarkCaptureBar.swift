import SwiftUI
import os

// MARK: - StarkCaptureBar
//
// Flagship smart capture bar for the Overview Command Center. Extends the
// original terminal-style input with two presentational layers:
//
//   1. Inline syntax highlighting — token spans (dates, hashtags, priority
//      bangs) are painted with theme-adaptive foreground/background tints
//      via an AttributedString overlay. The TextField itself keeps the text
//      cursor; a transparent-text overlay carries the colour.
//
//   2. Preview shelf — a row of animated token chips slides in below the
//      field the moment a token is detected. Each chip shows an icon and a
//      concise label (formatted date, tag name, priority level). Chips
//      animate in with a spring scale+opacity entrance and out on removal.
//
// Privacy notes (matching SmartCaptureEngine contract):
//   • On submit, `clearAfterSubmit()` drops the engine's `tokens` and
//     `highlighted` references and `text` is reset to "", so ARC can
//     deallocate the backing buffers promptly. NOTE: Swift `String` is COW
//     over a managed buffer — we cannot guarantee the underlying bytes are
//     overwritten in place. Prompt reference-drop is the realistic bound;
//     true byte-zeroing would require a custom unsafe buffer, which this
//     low-sensitivity capture path does not warrant.
//   • CLIPBOARD: this bar performs ZERO clipboard access — there is no
//     `UIPasteboard` read and no `PasteButton` anywhere in this view, so
//     there is no snooping surface. If a paste affordance is added later it
//     MUST be a user-tap-gated `PasteButton` (iOS 16+), never a programmatic
//     `UIPasteboard.general.string` read (which triggers the system banner).
//   • No external calls. The entire parse/scan pipeline is on-device.
//
// Aesthetic adaptability:
//   • Highlight colours are resolved by SmartCaptureEngine.tokenColor, which
//     branches on `palette.id` for Calm Earth and Liquid Glass.
//   • The bar container switches between `.flat` (Stark/Earth) and
//     `.ultraThinMaterial` (Liquid Glass) via `palette.cardSurface`.
//   • The shelf chips inherit `palette.chromeSurface` as their background.

struct StarkCaptureBar: View {

    // MARK: Props

    /// Called on submit. Receives the trimmed raw text.
    let onSubmit: (String) -> Void

    /// External focus trigger. Set to true to programmatically focus the bar;
    /// the bar resets it to false immediately after acquiring focus.
    var shouldFocus: Binding<Bool> = .constant(false)

    // MARK: Private state

    @Environment(ThemeStore.self) private var theme
    @State private var text: String           = ""
    @State private var engine                 = SmartCaptureEngine()
    @FocusState private var isFocused: Bool

    // MARK: Body

    var body: some View {
        let p = theme.palette
        VStack(spacing: 0) {
            inputRow(p)

            // Two mutually-exclusive shelves below the field:
            //   • Pre-typing: time-aware suggestion pills the instant the bar
            //     is focused and still empty (anticipates the user).
            //   • Typing: the detected-token preview shelf.
            if isFocused, text.isEmpty {
                suggestionShelf(p)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if !engine.tokens.isEmpty {
                previewShelf(p)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: engine.tokens.count)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: isFocused)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: text.isEmpty)
        .onChange(of: shouldFocus.wrappedValue) { _, newValue in
            if newValue {
                isFocused = true
                shouldFocus.wrappedValue = false
            }
        }
    }

    // MARK: - Pre-typing contextual shelf

    private func suggestionShelf(_ p: ThemePalette) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CaptureSuggestions.current(), id: \.self) { suggestion in
                    SuggestionPill(text: suggestion, palette: p) {
                        appendSuggestion(suggestion)
                    }
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
    }

    /// Appends a suggestion to the field with a trailing space, fires a
    /// tactile tap, re-scans for live preview, and KEEPS focus so the
    /// keyboard never dismisses.
    private func appendSuggestion(_ suggestion: String) {
        if text.isEmpty {
            text = suggestion + " "
        } else if text.hasSuffix(" ") {
            text += suggestion + " "
        } else {
            text += " " + suggestion + " "
        }
        AppHaptic.tap()
        engine.scan(text, palette: theme.palette)
    }

    // MARK: - Input row

    @ViewBuilder
    private func inputRow(_ p: ThemePalette) -> some View {
        HStack(spacing: 10) {
            // CLI prompt glyph
            Text(">")
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .foregroundStyle(p.textPrimary.opacity(isFocused ? 0.90 : 0.40))
                .animation(.spring(response: 0.22, dampingFraction: 0.85), value: isFocused)

            // Input + highlight overlay
            ZStack(alignment: .leading) {
                // Highlight layer (AttributedString, non-interactive)
                if !engine.tokens.isEmpty {
                    Text(engine.highlighted)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .lineLimit(1)
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Edit layer — text is clear when highlighting is active so
                // the two layers don't fight. The cursor tint stays visible.
                TextField("", text: $text, prompt: prompt(p))
                    .focused($isFocused)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(
                        engine.tokens.isEmpty
                            ? p.textPrimary
                            : Color.clear          // highlight layer takes over
                    )
                    .tint(p.textPrimary)            // cursor stays visible
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif
                    .autocorrectionDisabled()
                    .submitLabel(.return)
                    .onSubmit(submit)
                    .onChange(of: text) { _, newValue in
                        engine.scan(newValue, palette: theme.palette)
                    }
            }

            // Trailing controls
            trailingControls(p)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(barBackground(p))
        .overlay(barBorder(p))
        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: isFocused)
    }

    // MARK: - Background / border

    @ViewBuilder
    private func barBackground(_ p: ThemePalette) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: engine.tokens.isEmpty
                ? DesignTokens.Radius.small
                : DesignTokens.Radius.small,
            style: .continuous
        )
        switch p.cardSurface {
        case .flat(let fill):
            shape.fill(fill)
        case .material(let mat, _):
            shape.fill(mat)
        }
    }

    @ViewBuilder
    private func barBorder(_ p: ThemePalette) -> some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
            .strokeBorder(
                isFocused ? p.prominent : p.hairline,
                lineWidth: 0.5
            )
    }

    // MARK: - Trailing controls

    @ViewBuilder
    private func trailingControls(_ p: ThemePalette) -> some View {
        HStack(spacing: 8) {
            if !text.isEmpty {
                clearButton(p)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: text.isEmpty)
    }

    private func clearButton(_ p: ThemePalette) -> some View {
        Button {
            text = ""
            engine.clearAfterSubmit()
            AppHaptic.tap()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(p.textSecondary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(p.chromeSurface))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear capture")
    }

    // MARK: - Preview shelf

    private func previewShelf(_ p: ThemePalette) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Status glyph — morphs checkbox → loop the moment a
                // recurrence cadence is detected, signalling habit routing.
                StatusGlyph(isRecurring: engine.isRecurring, palette: p)

                ForEach(engine.tokens) { token in
                    TokenChip(token: token, palette: p)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.75)
                                    .combined(with: .opacity),
                                removal: .scale(scale: 0.75)
                                    .combined(with: .opacity)
                            )
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Prompt

    private func prompt(_ p: ThemePalette) -> Text {
        Text("CAPTURE INTENT…")
            .font(.system(size: 14, weight: .regular, design: .monospaced))
            .tracking(0.6)
            .foregroundColor(p.textTertiary)
    }

    // MARK: - Submit

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Clear engine state BEFORE clearing text — memory sanitization.
        engine.clearAfterSubmit()
        onSubmit(trimmed)
        text = ""
        AppHaptic.success()
        // Keep focus so the user can rip off multiple captures in a row.
    }
}

// MARK: - TokenChip
//
// A single animated pill in the preview shelf. Fires a light haptic on
// first appearance via `onAppear` so the user feels each token lock in.

private struct TokenChip: View {
    let token: DetectedToken
    let palette: ThemePalette

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(chipAccent)

            Text(label)
                .font(.system(size: 11, weight: .semibold, design: palette.fontDesign))
                .tracking(0.3)
                .foregroundStyle(chipAccent)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(chipAccent.opacity(0.14))
        )
        .overlay(
            Capsule()
                .strokeBorder(chipAccent.opacity(0.30), lineWidth: 0.5)
        )
        .onAppear {
            // Haptic on each new token lock-in.
            AppHaptic.tap()
        }
    }

    // MARK: Accessors

    private var icon: String {
        switch token.kind {
        case .date:       return "calendar"
        case .hashtag:    return "number"
        case .priority:   return "exclamationmark"
        case .recurrence: return "arrow.triangle.2.circlepath"   // loop
        }
    }

    private var label: String {
        switch token.kind {
        case .date(let formatted):   return formatted
        case .hashtag(let tag):      return tag
        case .priority(let level):   return "P\(level)"
        case .recurrence(let label): return label
        }
    }

    private var chipAccent: Color {
        switch token.kind {
        case .date:
            switch palette.id {
            case .calmEarth:   return Color(red: 0.28, green: 0.48, blue: 0.22)
            case .liquidGlass: return Color(red: 0.45, green: 0.90, blue: 0.72)
            default:           return Color(red: 0.35, green: 0.82, blue: 0.66)
            }
        case .hashtag:
            switch palette.id {
            case .calmEarth:   return Color(red: 0.68, green: 0.46, blue: 0.26)
            case .liquidGlass: return Color(red: 0.72, green: 0.65, blue: 0.95)
            default:           return Color(red: 0.60, green: 0.72, blue: 0.95)
            }
        case .priority:
            return Color(red: 0.96, green: 0.66, blue: 0.28)
        case .recurrence:
            switch palette.id {
            case .calmEarth:   return Color(red: 0.42, green: 0.40, blue: 0.62)
            case .liquidGlass: return Color(red: 0.78, green: 0.72, blue: 0.98)
            default:           return Color(red: 0.66, green: 0.62, blue: 0.92)
            }
        }
    }
}

// MARK: - CaptureSuggestions
//
// Time-aware pre-typing suggestions. Pure function of the current hour — no
// state, no storage, on-device. Surfaced the moment the bar gains focus.

enum CaptureSuggestions {
    /// Morning (6–12): focus-forward. Afternoon (12–18): mid-day rhythms.
    /// Evening/Night (18–6): wind-down / prep.
    static func current(now: Date = .now,
                        calendar: Calendar = .autoupdatingCurrent) -> [String] {
        let hour = calendar.component(.hour, from: now)
        switch hour {
        case 6..<12:  return ["Gym", "@9am", "#work"]
        case 12..<18: return ["Review", "Evening run", "#admin"]
        default:      return ["Journal", "Read", "Tomorrow"]
        }
    }
}

// MARK: - SuggestionPill
//
// A tappable pre-typing suggestion. Theme-adaptive: flat chrome fill on
// Stark/Earth, frosted material with a subtle inner highlight on Liquid Glass.

private struct SuggestionPill: View {
    let text: String
    let palette: ThemePalette
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.system(size: 12, weight: .medium, design: palette.fontDesign))
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(pillBackground)
                .overlay(Capsule().strokeBorder(palette.hairline, lineWidth: 0.5))
                .overlay(innerHighlight)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Insert \(text)")
    }

    @ViewBuilder
    private var pillBackground: some View {
        switch palette.cardSurface {
        case .flat:
            Capsule().fill(palette.chromeSurface)
        case .material(let material, _):
            Capsule().fill(material)
        }
    }

    /// Liquid Glass only — a top-edge white→clear gradient stroke for the
    /// frosted "inner highlight" sheen.
    @ViewBuilder
    private var innerHighlight: some View {
        if case .material(_, let specular) = palette.cardSurface, specular {
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.45), .white.opacity(0.05), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.7
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - StatusGlyph
//
// The preview shelf's leading status icon. Crossfades checkbox → loop via a
// symbol-replace content transition when a recurrence cadence is detected,
// visually confirming the capture will route to a habit, not a task.

private struct StatusGlyph: View {
    let isRecurring: Bool
    let palette: ThemePalette

    var body: some View {
        Image(systemName: isRecurring ? "arrow.triangle.2.circlepath" : "checkmark.square")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isRecurring ? recurringTint : palette.textSecondary)
            .frame(width: 26, height: 26)
            .background(Circle().fill(palette.chromeSurface))
            .contentTransition(.symbolEffect(.replace))
            .animation(.spring(response: 0.30, dampingFraction: 0.72), value: isRecurring)
            .accessibilityLabel(isRecurring ? "Habit" : "Task")
    }

    private var recurringTint: Color {
        switch palette.id {
        case .calmEarth:   return Color(red: 0.42, green: 0.40, blue: 0.62)
        case .liquidGlass: return Color(red: 0.78, green: 0.72, blue: 0.98)
        default:           return Color(red: 0.66, green: 0.62, blue: 0.92)
        }
    }
}

// MARK: - Preview

#Preview("Stark Dark — no tokens") {
    ZStack {
        DesignTokens.Background.canvas.ignoresSafeArea()
        VStack(spacing: 16) {
            StarkCaptureBar { Logger(subsystem: "com.remyavipindas.avenor", category: "capture").debug("submit: \($0, privacy: .public)") }
        }
        .padding(20)
    }
    .environment(ThemeStore())
    .preferredColorScheme(.dark)
}

#Preview("Stark Dark — with tokens") {
    // Simulates the user having typed "Review docs tomorrow #work !!!"
    // by pre-seeding the text via a wrapper view.
    PreviewWrapper()
        .environment(ThemeStore())
        .preferredColorScheme(.dark)
}

#Preview("Calm Earth — with tokens") {
    let store = ThemeStore()
    store.selected = .calmEarth
    return PreviewWrapper().environment(store)
}

#Preview("Liquid Glass — with tokens") {
    let store = ThemeStore()
    store.selected = .liquidGlass
    return PreviewWrapper().environment(store)
}

/// Helper only used in previews to pre-fill the bar.
private struct PreviewWrapper: View {
    @Environment(ThemeStore.self) private var theme
    var body: some View {
        ZStack {
            switch theme.palette.canvas {
            case .solid(let c):
                c.ignoresSafeArea()
            case .gradient(let stops, let start, let end):
                LinearGradient(stops: stops, startPoint: start, endPoint: end)
                    .ignoresSafeArea()
            }
            VStack(spacing: 24) {
                StarkCaptureBar { _ in }
                    .padding(.horizontal, 20)
                Text("TYPE: \"Review docs tomorrow #work !!!\"")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(theme.palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
}
