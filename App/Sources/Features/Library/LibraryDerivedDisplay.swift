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
    /// Strips simple HTML tags and collapses whitespace.
    var plainTextSummary: String {
        let stripped = description.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        let collapsed = stripped.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// View-model adapter for `DownloadStatusCapsule`. Translates the two
    /// real lifecycle enums (`DownloadState` × `TranscriptState`) into the
    /// single capsule status used by the row.
    var displayDownloadStatus: DownloadStatus {
        switch downloadState {
        case .failed:
            return .failed
        case .downloading(let progress, _):
            return .downloading(progress: progress)
        case .downloaded:
            switch transcriptState {
            case .ready:
                return .downloaded(transcribed: true)
            case .transcribing(let progress):
                return .transcribing(progress: progress)
            case .queued, .fetchingPublisher:
                return .transcriptionQueued(position: 1)
            case .failed:
                return .failed
            case .none:
                return .downloaded(transcribed: false)
            }
        case .queued, .notDownloaded:
            return .none
        }
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
