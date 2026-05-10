import SwiftUI

// MARK: - HomeDatelineComponents

/// The four parts that compose the small-caps dateline at the top of Home,
/// surfaced as a value type so the composition rule is testable independent
/// of the SwiftUI render layer.
///
/// Example: `TUESDAY · MAY 5 · 4 NEW · 1 CONTRADICTION`
struct HomeDatelineComponents: Equatable, Sendable {
    /// Weekday name uppercased — e.g. `"TUESDAY"`.
    let weekday: String
    /// Month + day — e.g. `"MAY 5"`.
    let monthDay: String
    /// Count of unplayed episodes published in the last 24h.
    let newCount: Int
    /// Count of `ThreadingTopic`s with `contradictionCount > 0`.
    let contradictionCount: Int

    /// Joined small-caps line ready for rendering.
    var rendered: String {
        var parts = ["\(weekday)", "\(monthDay)"]
        if newCount > 0 {
            parts.append("\(newCount) NEW")
        }
        if contradictionCount > 0 {
            let label = contradictionCount == 1 ? "CONTRADICTION" : "CONTRADICTIONS"
            parts.append("\(contradictionCount) \(label)")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Pure derivation

enum HomeDateline {

    /// Compose the dateline tokens from the live store + a clock.
    /// Pure function — no environment access — so the tests can pin a
    /// timezone, locale, and "now" without spinning up a SwiftUI view.
    static func components(
        episodes: [Episode],
        topics: [ThreadingTopic],
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> HomeDatelineComponents {
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.calendar = calendar
        weekdayFormatter.locale = locale
        weekdayFormatter.dateFormat = "EEEE"

        let monthDayFormatter = DateFormatter()
        monthDayFormatter.calendar = calendar
        monthDayFormatter.locale = locale
        monthDayFormatter.dateFormat = "MMM d"

        let weekday = weekdayFormatter.string(from: now).uppercased(with: locale)
        let monthDay = monthDayFormatter.string(from: now).uppercased(with: locale)

        // Unplayed in the last 24h. We count `!played` episodes whose
        // `pubDate` is within the trailing 24-hour window — the brief asks
        // for "count of unplayed episodes from last 24h" which we read as
        // recent-by-publish-date, not last-fetched.
        let cutoff = now.addingTimeInterval(-86_400)
        let newCount = episodes.reduce(0) { acc, ep in
            (!ep.played && ep.pubDate >= cutoff && ep.pubDate <= now) ? acc + 1 : acc
        }

        let contradictionCount = topics.reduce(0) { acc, topic in
            topic.contradictionCount > 0 ? acc + 1 : acc
        }

        return HomeDatelineComponents(
            weekday: weekday,
            monthDay: monthDay,
            newCount: newCount,
            contradictionCount: contradictionCount
        )
    }
}

// MARK: - View

/// Small-caps editorial dateline rendered above the Home title. Wraps the
/// pure derivation so the view layer never recomposes the string itself.
struct HomeDatelineView: View {
    let components: HomeDatelineComponents

    var body: some View {
        Text(components.rendered)
            .font(.system(.caption, design: .default).weight(.semibold))
            .tracking(1.6)
            .foregroundStyle(.secondary)
            .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts: [String] = ["\(components.weekday), \(components.monthDay)"]
        if components.newCount > 0 {
            parts.append("\(components.newCount) new")
        }
        if components.contradictionCount > 0 {
            let label = components.contradictionCount == 1 ? "contradiction" : "contradictions"
            parts.append("\(components.contradictionCount) \(label)")
        }
        return parts.joined(separator: ", ")
    }
}
