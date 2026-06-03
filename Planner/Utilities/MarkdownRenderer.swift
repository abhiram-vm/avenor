import Foundation
import SwiftUI

// MARK: - MarkdownRenderer
//
// Plain-text → AttributedString bridge for note bodies. Phase 3 foundation:
// today this is a thin wrapper around `AttributedString(markdown:)` plus a
// small pre-processor that promotes leading `-` / `*` lines into proper
// bullet glyphs. The intent is to let users write notes the way they
// already think (`**bold**`, `*italic*`, `- item`) without surfacing any
// rich-text chrome in the editor itself.
//
// Supported today:
//   • **bold**      via SwiftUI's built-in inline markdown parser
//   • *italic*      via SwiftUI's built-in inline markdown parser
//   • `inline code` via SwiftUI's built-in inline markdown parser
//   • [link](url)   via SwiftUI's built-in inline markdown parser
//   • - item        promoted to `•  item`
//   • * item        promoted to `•  item`
//
// Anything else falls through as plain text. Failures are fail-soft: any
// markdown parse error returns the original string verbatim so the editor
// can never "lose" content.

enum MarkdownRenderer {

    /// Renders `text` to an `AttributedString` suitable for `Text(...)`.
    ///
    /// Bullet pre-processing runs line-by-line so a single malformed line
    /// can't poison the whole document. Empty lines are preserved as
    /// paragraph breaks.
    ///
    /// Marked `nonisolated` (along with its helpers) so this renderer is
    /// safe to call from any actor context — including the synchronous
    /// `Array.map` closure inside `preprocessBullets`. Without this, Swift 6
    /// strict concurrency infers `@MainActor` from the project's default
    /// global actor and rejects the call.
    nonisolated static func render(_ text: String) -> AttributedString {
        let normalized = preprocessBullets(text)

        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.allowsExtendedAttributes = true

        if let attributed = try? AttributedString(markdown: normalized, options: options) {
            return attributed
        }
        // Fail-soft: return the original text untouched.
        return AttributedString(text)
    }

    // MARK: Bullet pre-processor

    nonisolated private static func preprocessBullets(_ text: String) -> String {
        // Split preserving empty trailing lines so users keep their spacing.
        let lines = text.components(separatedBy: "\n")
        let transformed = lines.map(transformBulletLine(_:))
        return transformed.joined(separator: "\n")
    }

    nonisolated private static func transformBulletLine(_ line: String) -> String {
        // Match a line beginning with optional whitespace, then `-` or `*`,
        // then at least one whitespace character, then content.
        let leadingWhitespace = line.prefix { $0 == " " || $0 == "\t" }
        let rest = line.dropFirst(leadingWhitespace.count)

        guard let marker = rest.first, marker == "-" || marker == "*" else {
            return line
        }

        let afterMarker = rest.dropFirst()
        guard let firstAfter = afterMarker.first, firstAfter == " " || firstAfter == "\t" else {
            return line
        }

        let content = afterMarker.drop { $0 == " " || $0 == "\t" }
        // Two-space gap after the glyph keeps the bullet column tidy in
        // both proportional and monospaced text contexts.
        return "\(leadingWhitespace)•  \(content)"
    }
}
