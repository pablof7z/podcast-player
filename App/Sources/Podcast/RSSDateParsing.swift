import Foundation

/// RFC 822 / RFC 1123 date parsing for RSS `<pubDate>`.
///
/// Lifted out of `RSSParser` to keep it under the 300-line soft cap. Kept as
/// an enum-namespace because none of these helpers need state.
enum DateParsing {

    /// Parses common RFC 822 / RFC 1123 forms emitted by RSS publishers. The
    /// spec is `EEE, dd MMM yyyy HH:mm:ss zzz`, but in the wild we see
    /// missing-second, two-digit-year, and offset-only variants. We try a
    /// fixed cascade in `en_US_POSIX` to keep the result locale-stable.
    static func parseRFC822(_ s: String) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for fmt in rfc822Formats {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "GMT")
            f.dateFormat = fmt
            if let date = f.date(from: trimmed) { return date }
        }
        // Last-ditch: ISO 8601 (some Atom-flavored feeds emit it under <pubDate>).
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: trimmed)
    }

    /// RFC 822 / 1123 cascade. Ordered most-strict to most-tolerant so the
    /// earliest match wins.
    private static let rfc822Formats: [String] = [
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "EEE, d MMM yyyy HH:mm:ss zzz",
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm:ss Z",
        "dd MMM yyyy HH:mm:ss zzz",
        "EEE, dd MMM yyyy HH:mm zzz",
        "EEE, dd MMM yyyy HH:mm:ss",
    ]
}
