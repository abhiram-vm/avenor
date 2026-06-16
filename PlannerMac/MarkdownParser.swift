import SwiftUI

// MARK: - MarkdownParser
//
// A self-contained CommonMark *subset* renderer: markdown string → a single
// `AttributedString` for display in a SwiftUI `Text`. Zero dependencies — a
// hand-rolled line scanner for block elements and a character scanner for
// inline spans. Anything outside the supported table passes through as plain
// text (deliberately — the editor must never "eat" unrecognized syntax).
//
// Supported (and ONLY these — see the brief's Phase 2 table):
//   Block:  # / ## / ###  headers · `- ` `* ` `1. ` lists · `> ` blockquote · `---` rule
//   Inline: **bold** __bold__ · *italic* _italic_ · `code` · [title](url) ·
//           @Mention (internal link)
//
// All color comes from the active `ThemePalette` — never a literal. Sizing is
// derived from `baseSize`, which the editor passes (15pt normal, 17pt reading
// mode) so the same renderer drives both contexts.
//
// Internal @mention links are encoded with the `avenor-mention://` scheme so
// the editor's `openURL` handler can distinguish them from real web links.
// Phase 3 supplies a `MentionResolver`; when absent (or a mention is
// unresolved) the span renders in gold to signal "not matched yet".

enum MarkdownParser {

    /// Scheme used to encode internal @mention links inside the AttributedString.
    /// The editor intercepts URLs with this scheme to navigate in-app.
    static let mentionScheme = "avenor-mention"

    static func mentionURL(for name: String) -> URL? {
        var comps = URLComponents()
        comps.scheme = mentionScheme
        comps.host = "x"
        comps.path = "/" + name
        return comps.url
    }

    /// Render markdown to a display-ready AttributedString.
    /// - Parameters:
    ///   - resolver: optional Phase-3 mention resolver. `nil` → every mention
    ///     renders gold (unresolved); a resolver decides mint vs gold per name.
    static func render(
        _ markdown: String,
        palette p: ThemePalette,
        baseSize: CGFloat = 15,
        resolver: MentionResolver? = nil
    ) -> AttributedString {
        var out = AttributedString()
        let lines = markdown.components(separatedBy: "\n")

        for (index, raw) in lines.enumerated() {
            out.append(renderBlock(raw, palette: p, baseSize: baseSize, resolver: resolver))
            if index < lines.count - 1 {
                out.append(AttributedString("\n"))
            }
        }
        return out
    }

    // MARK: Block-level

    private static func renderBlock(
        _ line: String,
        palette p: ThemePalette,
        baseSize: CGFloat,
        resolver: MentionResolver?
    ) -> AttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Horizontal rule: a line that is exactly `---` (or more dashes).
        if trimmed.count >= 3, trimmed.allSatisfy({ $0 == "-" }) {
            var rule = AttributedString(String(repeating: "─", count: 48))
            rule.font = .system(size: baseSize, weight: .regular, design: p.fontDesign)
            rule.foregroundColor = p.hairline
            return rule
        }

        // Headers: # / ## / ###
        if let (level, rest) = headerPrefix(line) {
            let sizes: [CGFloat] = [baseSize + 11, baseSize + 6, baseSize + 3]
            let weights: [Font.Weight] = [.heavy, .bold, .semibold]
            let i = level - 1
            let font = Font.system(size: sizes[i], weight: weights[i], design: p.fontDesign)
            var seg = parseInline(rest, baseFont: font, color: p.textPrimary, palette: p, baseSize: baseSize, resolver: resolver)
            // Re-assert the header font over inline spans so weight stays intact.
            seg.font = font
            return seg
        }

        // Blockquote: `> text` → mint vertical bar + secondary text.
        if line.hasPrefix(">") {
            let content = String(line.dropFirst().drop(while: { $0 == " " }))
            var bar = AttributedString("▎  ")
            bar.font = .system(size: baseSize, weight: .regular, design: p.fontDesign)
            bar.foregroundColor = quoteBarColor(p)
            let body = parseInline(content, baseFont: .system(size: baseSize, weight: .regular, design: p.fontDesign), color: p.textSecondary, palette: p, baseSize: baseSize, resolver: resolver)
            var seg = bar
            seg.append(body)
            return seg
        }

        // Unordered list: `- ` or `* `
        if let marker = unorderedMarker(line) {
            let content = String(line.dropFirst(marker).drop(while: { $0 == " " }))
            var bullet = AttributedString("   •  ")
            bullet.font = .system(size: baseSize, weight: .regular, design: p.fontDesign)
            bullet.foregroundColor = p.textSecondary
            let body = parseInline(content, baseFont: .system(size: baseSize, weight: .regular, design: p.fontDesign), color: p.textPrimary, palette: p, baseSize: baseSize, resolver: resolver)
            var seg = bullet
            seg.append(body)
            return seg
        }

        // Ordered list: `1. text`
        if let (number, rest) = orderedPrefix(line) {
            let content = rest.drop(while: { $0 == " " })
            var lead = AttributedString("   \(number).  ")
            lead.font = .system(size: baseSize, weight: .regular, design: p.fontDesign)
            lead.foregroundColor = p.textSecondary
            let body = parseInline(String(content), baseFont: .system(size: baseSize, weight: .regular, design: p.fontDesign), color: p.textPrimary, palette: p, baseSize: baseSize, resolver: resolver)
            var seg = lead
            seg.append(body)
            return seg
        }

        // Default paragraph.
        return parseInline(line, baseFont: .system(size: baseSize, weight: .regular, design: p.fontDesign), color: p.textPrimary, palette: p, baseSize: baseSize, resolver: resolver)
    }

    /// Mint-ish bar for blockquotes. Uses the brand mint so the quote rule
    /// reads as an intentional accent across all four themes.
    private static func quoteBarColor(_ p: ThemePalette) -> Color {
        Mac_Accent.mint
    }

    private static func headerPrefix(_ line: String) -> (Int, String)? {
        if line.hasPrefix("### ") { return (3, String(line.dropFirst(4))) }
        if line.hasPrefix("## ")  { return (2, String(line.dropFirst(3))) }
        if line.hasPrefix("# ")   { return (1, String(line.dropFirst(2))) }
        return nil
    }

    private static func unorderedMarker(_ line: String) -> Int? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") { return 1 }
        return nil
    }

    private static func orderedPrefix(_ line: String) -> (Int, Substring)? {
        // Match leading digits followed by ". "
        var digits = ""
        var idx = line.startIndex
        while idx < line.endIndex, line[idx].isNumber {
            digits.append(line[idx])
            idx = line.index(after: idx)
        }
        guard !digits.isEmpty, let n = Int(digits) else { return nil }
        guard idx < line.endIndex, line[idx] == "." else { return nil }
        let afterDot = line.index(after: idx)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        return (n, line[afterDot...])
    }

    // MARK: Inline scanner

    private static func parseInline(
        _ s: String,
        baseFont: Font,
        color: Color,
        palette p: ThemePalette,
        baseSize: CGFloat,
        resolver: MentionResolver?
    ) -> AttributedString {
        var result = AttributedString()
        let chars = Array(s)
        var i = 0
        var plainStart = 0

        func emitPlain(upTo end: Int) {
            guard end > plainStart else { return }
            var run = AttributedString(String(chars[plainStart..<end]))
            run.font = baseFont
            run.foregroundColor = color
            result.append(run)
        }

        func matches(_ marker: String, at pos: Int) -> Bool {
            let m = Array(marker)
            guard pos + m.count <= chars.count else { return false }
            for k in 0..<m.count where chars[pos + k] != m[k] { return false }
            return true
        }

        /// Find the index of `marker` starting at/after `from`; returns nil if absent.
        func find(_ marker: String, from: Int) -> Int? {
            var j = from
            while j < chars.count {
                if matches(marker, at: j) { return j }
                j += 1
            }
            return nil
        }

        while i < chars.count {
            let c = chars[i]

            // Inline code: `...`
            if c == "`" {
                if let close = find("`", from: i + 1) {
                    emitPlain(upTo: i)
                    let inner = String(chars[(i + 1)..<close])
                    var run = AttributedString(inner)
                    run.font = .system(size: baseSize * 0.94, weight: .regular, design: .monospaced)
                    run.foregroundColor = p.textPrimary
                    run.backgroundColor = p.chromeSurface
                    result.append(run)
                    i = close + 1
                    plainStart = i
                    continue
                }
            }

            // Bold: **...** or __...__
            for marker in ["**", "__"] where matches(marker, at: i) {
                if let close = find(marker, from: i + marker.count) {
                    emitPlain(upTo: i)
                    let inner = String(chars[(i + marker.count)..<close])
                    var run = AttributedString(inner)
                    run.font = .system(size: baseSize, weight: .bold, design: p.fontDesign)
                    run.foregroundColor = color
                    result.append(run)
                    i = close + marker.count
                    plainStart = i
                    break
                }
            }
            if plainStart == i { /* advanced by bold */ continue }

            // Italic: *...* or _..._  (single marker, not part of ** / __)
            for marker in ["*", "_"] where chars[i] == Character(marker) {
                // Skip if this is actually a double marker (handled above).
                if i + 1 < chars.count && chars[i + 1] == Character(marker) { break }
                if let close = find(marker, from: i + 1) {
                    emitPlain(upTo: i)
                    let inner = String(chars[(i + 1)..<close])
                    var run = AttributedString(inner)
                    run.font = Font.system(size: baseSize, weight: .regular, design: p.fontDesign).italic()
                    run.foregroundColor = color
                    result.append(run)
                    i = close + 1
                    plainStart = i
                    break
                }
            }
            if plainStart == i { continue }

            // Link: [title](url)
            if c == "[", let closeBracket = find("]", from: i + 1),
               closeBracket + 1 < chars.count, chars[closeBracket + 1] == "(",
               let closeParen = find(")", from: closeBracket + 2) {
                emitPlain(upTo: i)
                let title = String(chars[(i + 1)..<closeBracket])
                let urlStr = String(chars[(closeBracket + 2)..<closeParen])
                var run = AttributedString(title)
                run.font = baseFont
                run.foregroundColor = Mac_Accent.mint
                run.underlineStyle = .single
                if let url = URL(string: urlStr) { run.link = url }
                result.append(run)
                i = closeParen + 1
                plainStart = i
                continue
            }

            // Mention: @Word (letters / digits / _)
            if c == "@" {
                var j = i + 1
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" {
                    j += 1
                }
                if j > i + 1 {
                    emitPlain(upTo: i)
                    let name = String(chars[(i + 1)..<j])
                    let resolved = resolver?.isResolved(name) ?? false
                    var run = AttributedString("@" + name)
                    run.font = .system(size: baseSize, weight: .medium, design: p.fontDesign)
                    run.foregroundColor = resolved ? Mac_Accent.mint : MarkdownPalette.unresolvedGold
                    if let url = mentionURL(for: name) { run.link = url }
                    result.append(run)
                    i = j
                    plainStart = i
                    continue
                }
            }

            i += 1
        }

        emitPlain(upTo: chars.count)
        return result
    }
}

// MARK: - MarkdownPalette
//
// Literals that don't belong to the four themes but ARE part of the markdown
// spec's fixed semantic vocabulary. Gold (#FBBF24) is mandated by the brief
// for unresolved @mentions across every theme — it's a status color, not a
// theme color, so it lives here rather than in `ThemePalette`.

enum MarkdownPalette {
    /// `#FBBF24` — unresolved-mention signal. Theme-independent by design.
    static let unresolvedGold = Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255)
}
