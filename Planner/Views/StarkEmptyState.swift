import SwiftUI

// MARK: - StarkEmptyState (Sophisticated Stark)
//
// Ultra-minimal empty state. Text only. No glyphs, no shapes, no cards.
// Two stacked micro-tracked uppercase lines, the second dimmer than the
// first, both monospaced when the caller chooses to use digits.
//
// The intent is restraint: when a list has nothing in it, the page should
// feel like the list itself is silent — not a poster announcing emptiness.
//
//   "NO ACTION ITEMS DUE TODAY"
//   "SWIPE LEFT TO START A NEW ONE."

struct StarkEmptyState: View {
    @Environment(ThemeStore.self) private var theme

    let headline: String
    let footnote: String?

    init(_ headline: String, footnote: String? = nil) {
        self.headline = headline
        self.footnote = footnote
    }

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 6) {
            Text(headline)
                .font(p.font(.micro))
                .tracking(p.microTracking)
                .textCase(.uppercase)
                .monospacedDigit()
                .foregroundStyle(p.textSecondary)

            if let footnote {
                Text(footnote)
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .monospacedDigit()
                    .foregroundStyle(p.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 48)
    }
}

#Preview {
    ZStack {
        DesignTokens.Background.canvas.ignoresSafeArea()
        VStack(spacing: 24) {
            StarkEmptyState("No action items due today.")
            StarkEmptyState("Empty.", footnote: "Tap + to capture your first item.")
        }
        .padding(.horizontal, 24)
    }
    .environment(ThemeStore())
    .preferredColorScheme(.dark)
}
