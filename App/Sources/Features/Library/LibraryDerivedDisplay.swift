import Foundation
import SwiftUI

// MARK: - PodcastSubscription display helpers

extension PodcastSubscription {

    /// Stable per-show accent hue derived from the feed URL string. We hash
    /// the bytes so the same subscription always reads with the same tint
    /// across launches even before artwork is loaded and a real dominant-color
    /// pass becomes available.
    var accentHue: Double {
        let bytes = feedURL.absoluteString.utf8
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return Double(hash % 360) / 360.0
    }

    /// Mid-luminance accent color derived from `accentHue`. Reads on both
    /// light and dark backgrounds.
    var accentColor: Color {
        Color(hue: accentHue, saturation: 0.65, brightness: 0.78)
    }

    /// SF Symbol used as an artwork stand-in until `imageURL` is loaded.
    /// Picked from a curated bank using `accentHue` so the symbol stays
    /// stable per-feed.
    var artworkSymbol: String {
        let bank = [
            "waveform",
            "mic.fill",
            "headphones",
            "antenna.radiowaves.left.and.right",
            "leaf.fill",
            "atom",
            "books.vertical.fill",
            "brain.head.profile",
            "rectangle.stack.fill",
            "graduationcap.fill",
            "building.columns.fill",
            "chart.line.uptrend.xyaxis"
        ]
        let idx = Int((accentHue * Double(bank.count)).rounded(.down)) % bank.count
        return bank[abs(idx)]
    }
}

// MARK: - Episode display helpers

extension Episode {

    /// `true` when the user has never started this episode.
    var isUnplayed: Bool {
        !played && playbackPosition < 0.0001
    }

    /// `true` when the user has listened to this episode at all but has not
    /// finished it.
    var isInProgress: Bool {
        guard !played else { return false }
        guard let total = duration, total > 0 else { return playbackPosition > 0 }
        let fraction = playbackPosition / total
        return fraction > 0.0001 && fraction < 0.999
    }

    /// Listening progress in `0...1`. `0` if never played; `1` if completed.
    /// Returns `0` when duration is unknown so the UI doesn't draw a half-
    /// rendered crescent for episodes the publisher didn't tag.
    var playbackProgress: Double {
        if played { return 1 }
        guard let total = duration, total > 0 else { return 0 }
        return min(1, max(0, playbackPosition / total))
    }

    /// Pretty duration string for display: "2h 14m" or "47m".
    /// Returns "—" when duration is unknown.
    var formattedDuration: String {
        guard let total = duration, total > 0 else { return "—" }
        let seconds = Int(total)
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    /// Plain-text summary suitable for a one-or-two-line row preview.
    /// Strips HTML tags, decodes the common entities (so curly quotes /
    /// em-dashes / ellipses don't render as `&rsquo;` etc.), and collapses
    /// every whitespace run — including the paragraph breaks the formatter
    /// inserts — into a single space so the preview fits the row's
    /// `lineLimit(2)` cleanly.
    ///
    /// Uses `components(separatedBy:.whitespacesAndNewlines).joined(separator:)`
    /// instead of `replacingOccurrences(of: "\\s+", options: .regularExpression)`
    /// — the previous shape compiled a regex on every row render (and this
    /// runs for every row in a long episode list), while the new shape is
    /// pure UTF-16 scanning that's also Unicode-whitespace-aware via
    /// `CharacterSet`. The filter-empty + join steps also handle leading
    /// and trailing whitespace, so the explicit `trimmingCharacters` call
    /// at the tail is no longer needed.
    var plainTextSummary: String {
        EpisodeShowNotesFormatter.plainText(from: description)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// MARK: - Subscription stats from a store

extension AppStateStore {

    /// Episodes the user has not played for the given subscription.
    ///
    /// O(1) dict lookup against `unplayedCountByShow`. The 10k-episode
    /// reduce that used to dominate `LibraryView`'s grid render path is
    /// gone — see `AppStateStore+EpisodeProjections.swift`.
    func unplayedCount(forSubscription id: UUID) -> Int {
        unplayedCountByShow[id] ?? 0
    }

    /// `true` when at least one episode for the subscription has any
    /// download in flight or already on disk.
    ///
    /// O(1) Set membership against `hasDownloadedByShow`.
    func hasDownloadedEpisode(forSubscription id: UUID) -> Bool {
        hasDownloadedByShow.contains(id)
    }

    /// `true` when at least one episode for the subscription has a ready
    /// transcript. Drives the Library "Transcribed" filter chip.
    ///
    /// O(1) Set membership against `hasTranscribedByShow`.
    func hasTranscribedEpisode(forSubscription id: UUID) -> Bool {
        hasTranscribedByShow.contains(id)
    }
}
