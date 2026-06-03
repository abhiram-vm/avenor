import Foundation
import SwiftUI

// MARK: - SmartCaptureEngine
//
// Real-time token scanner that runs on every keystroke inside StarkCaptureBar.
// Distinct from CaptureParser only in cadence: this layer fires per-keystroke
// to drive the live preview, where `CaptureParser.parse` fires once on submit
// to build the persisted intent. Both share the same `TaskDraftBuilder`
// extraction pass via `CaptureParser.build(_:now:)`, so the inline preview
// and the committed parse are guaranteed to agree byte-for-byte.
//
// Privacy contract:
//   • All processing is synchronous, on-device, in-memory. No logging.
//   • `clearAfterSubmit()` zeroes both published properties immediately
//     after the bar hands the text off, preventing stale strings from
//     lingering in the @Observable graph.
//   • No NSLinguisticTagger, no NLP framework, no network round-trips.
//
// Performance:
//   Each `scan(_:palette:)` call is O(n) over the input string (a single
//   capture-bar entry is typically < 120 chars). No debounce — the bar's
//   .onChange drives this synchronously within the existing render cycle.

// MARK: - DetectedToken

/// A single recognized chip inside the preview shelf.
struct DetectedToken: Identifiable, Equatable {

    enum Kind: Equatable {
        /// A resolved calendar date or time. `formatted` is the chip label
        /// (e.g. "Mon, Jun 2", "9:00 AM", or "Tue, Jun 3 · 6:30 AM").
        case date(formatted: String)
        /// Hashtag → idea intent. `tag` is uppercased, max 10 chars.
        case hashtag(tag: String)
        /// Trailing bang priority. `level` is 1 (highest, `!!!`)…3 (`!`).
        case priority(level: Int)
        /// Recurrence cadence → habit intent. `label` is the human cadence
        /// ("Every day", "Every Monday"). Drives the checkbox→loop morph.
        case recurrence(label: String)
    }

    let kind: Kind

    /// STABLE identity derived from the token's semantic *value*, NOT a
    /// random UUID. This is critical: `scan()` rebuilds the array on every
    /// keystroke, so a per-instance UUID would make `ForEach` tear down and
    /// re-insert every chip each frame — causing per-keystroke view churn
    /// and re-firing `onAppear` haptics on each character. With a value-
    /// derived id, an unchanged token keeps its identity across keystrokes,
    /// so chips persist and the lock-in haptic fires exactly once.
    var id: String {
        switch kind {
        case .date(let formatted): return "date:\(formatted)"
        case .hashtag(let tag):    return "tag:\(tag)"
        case .priority(let level): return "pri:\(level)"
        case .recurrence(let label): return "rec:\(label)"
        }
    }

    init(kind: Kind) {
        self.kind = kind
    }
}

// MARK: - SmartCaptureEngine

@Observable
final class SmartCaptureEngine {

    // MARK: Published outputs

    /// Current token list consumed by the preview shelf.
    private(set) var tokens: [DetectedToken] = []

    /// Attributed string consumed by the highlight overlay in StarkCaptureBar.
    private(set) var highlighted: AttributedString = AttributedString("")

    /// `true` when a recurrence cadence is currently detected. Drives the
    /// capture bar's status-glyph morph (checkbox → loop) so the user sees
    /// Avenor recognize the input as a habit before they hit return.
    var isRecurring: Bool {
        tokens.contains {
            if case .recurrence = $0.kind { return true }
            return false
        }
    }

    // MARK: - API

    /// Call inside `.onChange(of: text)`. Routes the input through the
    /// shared `CaptureParser.build` pass, then translates the builder's
    /// match metadata into UI tokens and a highlighted attributed string.
    func scan(_ text: String, palette: ThemePalette) {
        guard !text.isEmpty else {
            tokens      = []
            highlighted = AttributedString("")
            return
        }

        let builder = CaptureParser.build(text)
        tokens      = makeTokens(from: builder)
        // Highlighting paints each builder span INDEPENDENTLY (date, time,
        // hashtag, priority). It deliberately does NOT consume the shelf's
        // combined date+time chip span — unioning those spans would paint
        // the words between two non-adjacent tokens (e.g. "buy milk" in
        // "tomorrow buy milk @5pm"). See `buildAttributedString`.
        highlighted = buildAttributedString(text, builder: builder, palette: palette)
    }

    /// Zero all state immediately after the capture bar submits text.
    /// Call this from the bar's submit path BEFORE the text binding is
    /// cleared, so the @Observable graph never holds a stale payload.
    func clearAfterSubmit() {
        tokens      = []
        highlighted = AttributedString("")
    }

    // MARK: - Translate builder → UI tokens

    /// Produces an ordered token list from a `TaskDraftBuilder`. Tokens
    /// appear in builder-discovery order, which is: priority → hashtag →
    /// time → date. The shelf renders chips in this order, giving a
    /// stable, predictable layout regardless of how the user typed them.
    private func makeTokens(from builder: TaskDraftBuilder) -> [DetectedToken] {
        var out: [DetectedToken] = []

        // Recurrence leads — it's the highest-signal chip (it changes the
        // destination container) and pairs with the status-glyph morph.
        if let recurrence = builder.recurrence {
            out.append(DetectedToken(kind: .recurrence(label: recurrence.rule.label)))
        }
        if let priority = builder.priority {
            out.append(DetectedToken(kind: .priority(level: priority.level)))
        }
        if let hashtag = builder.hashtag {
            out.append(DetectedToken(kind: .hashtag(tag: hashtag.tag)))
        }

        // Date + time chips. If both are present, we emit a single combined
        // chip whose label reads "Mon, Jun 2 · 6:30 AM". Otherwise, emit
        // whichever channel locked in. The chip is display-only — its
        // identity is value-derived, so it persists across keystrokes.
        switch (builder.hasDate, builder.hasTime) {
        case (true, true):
            out.append(DetectedToken(kind: .date(formatted: combinedDateTimeLabel(builder: builder))))
        case (true, false):
            out.append(DetectedToken(kind: .date(formatted: dateOnlyLabel(builder))))
        case (false, true):
            out.append(DetectedToken(kind: .date(formatted: timeOnlyLabel(builder))))
        case (false, false):
            break
        }

        return out
    }

    // MARK: - Label formatters

    private func combinedDateTimeLabel(builder: TaskDraftBuilder) -> String {
        guard let resolved = builder.resolvedDate() else { return "—" }
        let day  = resolved.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let time = resolved.formatted(date: .omitted, time: .shortened)
        return "\(day) · \(time)"
    }

    private func dateOnlyLabel(_ builder: TaskDraftBuilder) -> String {
        guard let resolved = builder.resolvedDate() else { return "—" }
        return resolved.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func timeOnlyLabel(_ builder: TaskDraftBuilder) -> String {
        guard let resolved = builder.resolvedDate() else { return "—" }
        return resolved.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Attributed string builder

    private func buildAttributedString(_ text: String,
                                       builder: TaskDraftBuilder,
                                       palette: ThemePalette) -> AttributedString {
        var attr = AttributedString(text)
        attr.font            = .system(size: 14, weight: .regular, design: .monospaced)
        attr.foregroundColor = palette.textPrimary

        // Paint each span independently against the SAME source string the
        // AttributedString was built from. Never union — that would bleed
        // colour onto intervening words.
        paint(&attr, text: text, range: builder.dateRange,       kind: .date(formatted: ""),     palette: palette)
        paint(&attr, text: text, range: builder.timeRange,       kind: .date(formatted: ""),     palette: palette)
        paint(&attr, text: text, range: builder.hashtag?.range,  kind: .hashtag(tag: ""),        palette: palette)
        paint(&attr, text: text, range: builder.priority?.range, kind: .priority(level: 0),      palette: palette)
        paint(&attr, text: text, range: builder.recurrence?.range, kind: .recurrence(label: ""), palette: palette)
        return attr
    }

    /// Applies the token tint to a single source range, if present. Guards
    /// the `Range<String.Index>` → `AttributedString` index conversion so a
    /// stale range silently no-ops rather than crashing.
    private func paint(_ attr: inout AttributedString,
                       text: String,
                       range: Range<String.Index>?,
                       kind: DetectedToken.Kind,
                       palette: ThemePalette) {
        guard let range,
              range.lowerBound >= text.startIndex,
              range.upperBound <= text.endIndex,
              let attrRange = Range(range, in: attr) else { return }
        let fg = tokenColor(kind, palette: palette)
        attr[attrRange].foregroundColor = fg
        attr[attrRange].backgroundColor = fg.opacity(0.15)
    }

    // MARK: - Theme-adaptive token colors

    private func tokenColor(_ kind: DetectedToken.Kind, palette: ThemePalette) -> Color {
        switch kind {
        case .date:
            switch palette.id {
            case .calmEarth:   return Color(red: 0.28, green: 0.48, blue: 0.22)   // deep olive
            case .liquidGlass: return Color(red: 0.45, green: 0.90, blue: 0.72)   // cool teal
            default:           return Color(red: 0.35, green: 0.82, blue: 0.66)   // clinical mint
            }
        case .hashtag:
            switch palette.id {
            case .calmEarth:   return Color(red: 0.68, green: 0.46, blue: 0.26)   // warm clay
            case .liquidGlass: return Color(red: 0.72, green: 0.65, blue: 0.95)   // lavender
            default:           return Color(red: 0.60, green: 0.72, blue: 0.95)   // pale slate-lilac
            }
        case .priority:
            // Amber reads across every palette — signals urgency without
            // clashing with the date/tag channels.
            return Color(red: 0.96, green: 0.66, blue: 0.28)
        case .recurrence:
            // Indigo — a distinct "loop / ongoing" hue, separate from the
            // date (mint/teal) and tag (lilac) channels.
            switch palette.id {
            case .calmEarth:   return Color(red: 0.42, green: 0.40, blue: 0.62)   // muted plum
            case .liquidGlass: return Color(red: 0.78, green: 0.72, blue: 0.98)   // bright periwinkle
            default:           return Color(red: 0.66, green: 0.62, blue: 0.92)   // indigo
            }
        }
    }
}
