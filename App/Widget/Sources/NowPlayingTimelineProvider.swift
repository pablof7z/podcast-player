import Foundation
import WidgetKit

// MARK: - WidgetSnapshot (widget side)

/// Wire-compatible mirror of the kernel-owned `WidgetSnapshot`
/// (`apps/nmp-app-podcast/src/ffi/projections/platform.rs`). The widget
/// extension compiles separately from the app target (it can't share the
/// app-side mirror in `PlatformCapability+WireTypes.swift`), so it keeps its
/// own copy. It mirrors the app side exactly: **no explicit `CodingKeys`**, and
/// `readCurrent()` decodes with `.convertFromSnakeCase`. Property names are the
/// camelCase the strategy produces from the snake_case wire keys — including
/// the acronym lowercasing (`artwork_url` → `artworkUrl`). Keeping both mirrors
/// structurally identical avoids drift; see the app-side note for why explicit
/// snake_case `CodingKeys` are a decode-breaking footgun under the bridge's
/// strategy.
struct WidgetSnapshot: Codable, Equatable {
    var nowPlayingEpisodeTitle: String?
    var nowPlayingPodcastTitle: String?
    var nowPlayingArtworkUrl: String?
    /// Active chapter title at the playhead, preferred over the show name.
    var nowPlayingChapterTitle: String?
    var isPlaying: Bool
    /// Pre-computed `0.0..=1.0` progress fraction (kernel-clamped).
    var positionFraction: Float
    /// Current playhead in seconds — paired with `durationSecs` for the
    /// "−MM:SS remaining" label.
    var positionSecs: Double
    /// Track duration in seconds; `0` until the capability reports it.
    var durationSecs: Double
    /// Unplayed episodes across subscribed shows — drives the "N to listen"
    /// badge / empty-state line.
    var unplayedCount: Int

    /// `true` when an episode is loaded (the kernel populates a title only when
    /// something is playing). A badge-only snapshot (nothing playing, unplayed
    /// count > 0) has no episode title and renders the empty state with a count.
    var hasNowPlaying: Bool {
        guard let title = nowPlayingEpisodeTitle else { return false }
        return !title.isEmpty
    }
}

// MARK: - NowPlayingEntry

/// Single timeline entry the Now Playing widget renders against. `nil`
/// `snapshot` means the App Group key is absent (the kernel cleared it) — the
/// widget shows its empty state instead of stale metadata.
struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

// MARK: - NowPlayingTimelineProvider

/// Reads the latest `WidgetSnapshot` out of the App Group's shared
/// `UserDefaults` on every timeline refresh. The app side calls
/// `WidgetCenter.shared.reloadAllTimelines()` after each snapshot write, so the
/// 60s system fallback is just a backstop for when the app is suspended.
struct NowPlayingTimelineProvider: TimelineProvider {

    /// Must match `PlatformCapability.appGroupID` on the app side.
    static let appGroupID = "group.com.podcastr.app"
    /// Must match `PlatformCapability.widgetSnapshotKey` on the app side.
    static let defaultsKey = "nmp.widget.snapshot.v1"

    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(NowPlayingEntry(date: .now, snapshot: readCurrent()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let entry = NowPlayingEntry(date: .now, snapshot: readCurrent())
        // Re-poll after 60s — the app pushes reloads on every snapshot write,
        // so this is the upper bound on staleness when the app is suspended.
        let nextFire = Date().addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(nextFire)))
    }

    /// Decodes the snapshot from App Group `UserDefaults`. Returns `nil` when
    /// the suite is unavailable, the key is missing, or the JSON fails to
    /// decode — all of which collapse into "show empty state".
    private func readCurrent() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID),
              let data = defaults.data(forKey: Self.defaultsKey)
        else { return nil }
        // The app side writes this payload with `.convertToSnakeCase` and the
        // type carries no explicit `CodingKeys`, so decode with the matching
        // `.convertFromSnakeCase` strategy (mirrors the bridge's decoder config).
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
