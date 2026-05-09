import Foundation

/// Helpers for rendering an `Episode.description` value, which may be HTML,
/// plain text, or a mix. We do the cheap thing: strip tags for the body text
/// surface, and decode the most common HTML entities so apostrophes and dashes
/// don't show up as `&amp;rsquo;` to the reader.
///
/// We deliberately avoid `NSAttributedString(data:options:.html…)` here:
/// it requires a main-thread WebKit pass that's both expensive and prone to
/// crashing under SwiftUI preview snapshots. A future pass can swap in a
/// proper attributed renderer once the in-app HTML→AttributedString utility
/// in `Design/MarkdownView.swift` is generalized.
enum EpisodeShowNotesFormatter {

    /// Plain-text projection of an episode description. Tag stripping +
    /// entity decoding + whitespace normalization.
    static func plainText(from raw: String) -> String {
        let stripped = stripTags(raw)
        let decoded = decodeEntities(stripped)
        return collapseWhitespace(decoded)
    }

    private static func stripTags(_ input: String) -> String {
        var inTag = false
        var out = ""
        out.reserveCapacity(input.count)
        for c in input {
            if c == "<" { inTag = true; continue }
            if c == ">" { inTag = false; continue }
            if !inTag { out.append(c) }
        }
        return out
    }

    private static let entityMap: [String: String] = [
        "&amp;": "&",
        "&lt;": "<",
        "&gt;": ">",
        "&quot;": "\"",
        "&apos;": "'",
        "&nbsp;": " ",
        "&rsquo;": "\u{2019}",
        "&lsquo;": "\u{2018}",
        "&rdquo;": "\u{201D}",
        "&ldquo;": "\u{201C}",
        "&hellip;": "\u{2026}",
        "&mdash;": "\u{2014}",
        "&ndash;": "\u{2013}"
    ]

    private static func decodeEntities(_ input: String) -> String {
        var out = input
        for (entity, replacement) in entityMap {
            out = out.replacingOccurrences(of: entity, with: replacement)
        }
        return out
    }

    private static func collapseWhitespace(_ input: String) -> String {
        let lines = input
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n\n")
    }
}
