import Foundation

// MARK: - NaturalDateParser

/// Scans a short text string for a natural-language date phrase and returns
/// the detected date plus the title with the phrase removed.
///
/// Supported patterns (case-insensitive):
///   - "today", "tonight"
///   - "tomorrow"
///   - "next week"
///   - "in N days" / "in N weeks"
///   - Day names: "monday" … "sunday" → next occurrence of that weekday
enum NaturalDateParser {

    struct ParseResult: Equatable {
        /// The detected due date.
        let date: Date
        /// The original text with the date phrase stripped and whitespace normalised.
        let cleanedTitle: String
    }

    private static let weekdays = [
        "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
    ]

    /// Returns `nil` when no date phrase is found in `text`.
    static func parse(_ text: String) -> ParseResult? {
        let lower = text.lowercased()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Each pattern: (regex pattern, offset-in-days or handler)
        let patterns: [(pattern: String, resolve: (String) -> Date?)] = [
            ("\\b(tonight|today)\\b", { _ in today }),
            ("\\btomorrow\\b", { _ in cal.date(byAdding: .day, value: 1, to: today) }),
            ("\\bnext week\\b", { _ in cal.date(byAdding: .weekOfYear, value: 1, to: today) }),
            ("\\bin (\\d+) days?\\b", { match in
                guard let n = Int(match) else { return nil }
                return cal.date(byAdding: .day, value: n, to: today)
            }),
            ("\\bin (\\d+) weeks?\\b", { match in
                guard let n = Int(match) else { return nil }
                return cal.date(byAdding: .weekOfYear, value: n, to: today)
            }),
        ]

        // Day-of-week patterns
        for (index, day) in Self.weekdays.enumerated() {
            let pattern = "\\b\(day)\\b"
            if let range = lower.range(of: pattern, options: .regularExpression) {
                let currentWeekday = cal.component(.weekday, from: today) // 1=Sun … 7=Sat
                var daysAhead = index + 1 - currentWeekday
                if daysAhead <= 0 { daysAhead += 7 }
                if let date = cal.date(byAdding: .day, value: daysAhead, to: today) {
                    let cleaned = cleanTitle(text, removing: String(lower[range]))
                    return ParseResult(date: date, cleanedTitle: cleaned)
                }
            }
        }

        // Ordered patterns
        for (pattern, resolve) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let nsText = lower as NSString
            let results = regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower))
            guard let match = results.first else { continue }

            // Extract numeric capture group if present (group 1).
            let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : NSRange(location: NSNotFound, length: 0)
            let captured = captureRange.location != NSNotFound ? nsText.substring(with: captureRange) : ""

            guard let date = resolve(captured) else { continue }
            let matchRange = Range(match.range, in: lower)!
            let cleaned = cleanTitle(text, removing: String(lower[matchRange]))
            return ParseResult(date: date, cleanedTitle: cleaned)
        }

        return nil
    }

    // MARK: - Private

    private static func cleanTitle(_ text: String, removing phrase: String) -> String {
        var result = text
        // Case-insensitive removal of the matched phrase.
        if let range = result.range(of: phrase, options: .caseInsensitive) {
            result.removeSubrange(range)
        }
        // Normalise surrounding punctuation and whitespace.
        result = result
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .init(charactersIn: " ,;:"))
        return result.isEmpty ? text : result
    }
}
