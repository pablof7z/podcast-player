// PodcastTypes.generated.swift
// Generated — historically authored by the codegen pipeline below; that
// pipeline does not exist in the tree yet (no `dump_projection_schemas`
// binary), so this file is hand-maintained from
// `apps/nmp-app-podcast/src/ffi/projections.rs` and
// `apps/nmp-app-podcast/src/ffi/snapshot.rs` until the codegen lands.
// Keep the camelCase shape in sync with the snake_case Rust source — the
// runtime decoder uses `.convertFromSnakeCase` so the rename is implicit.
//
// Intended regeneration command (once the dumper exists):
//
//   cargo run -p nmp-app-podcast --features codegen-schema \
//       --bin dump_projection_schemas \
//     | cargo run -p nmp-codegen -- gen swift
//
// Source of truth: apps/nmp-app-podcast/src/ffi/snapshot.rs

import Foundation

/// Top-level snapshot emitted by the Rust podcast kernel on every podcast
/// projection tick (pulled via `nmp_app_podcast_snapshot`).
struct PodcastUpdate: Codable {
    var running: Bool = false
    var rev: Int = 0
    var schemaVersion: Int = 0
    var library: [PodcastSummary] = []
    var nowPlaying: PlayerState? = nil
    var activeAccount: AccountSummary? = nil
    var toast: String? = nil
    var searchResults: [PodcastSummary] = []
    /// NIP-F4 Nostr podcast discovery results.
    var nostrResults: [NostrShowSummary]? = nil
    /// Ordered list of episode ids waiting in the playback queue
    /// ("Up Next"). Mutated kernel-side via `podcast.player.enqueue`,
    /// `dequeue`, `clear_queue`, and `play_next`.
    var queue: [String] = []
    /// App-settings projection. Defaults to the fresh-install state so the
    /// iOS shell can read `snapshot.settings.hasCompletedOnboarding` directly
    /// without an optional-chained `if let`. The Rust side omits the key when
    /// it equals the default, so legacy payloads decode cleanly.
    var settings: SettingsSnapshot = SettingsSnapshot()
}

/// App-settings projection emitted alongside `PodcastUpdate`.
///
/// The default value (`hasCompletedOnboarding == false`) is what the wire
/// payload encodes when the Rust kernel skip-serializes an empty settings
/// snapshot — older binaries on `Codable` decode see this as a fresh install.
struct SettingsSnapshot: Codable, Equatable, Hashable {
    var hasCompletedOnboarding: Bool = false
}

/// Narrow projection for a subscribed podcast (one library grid/list cell).
/// Episode rows are embedded so the show-detail view doesn't need a second pull.
struct PodcastSummary: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var title: String
    var episodeCount: Int = 0
    var unplayedCount: Int = 0
    var artworkUrl: String? = nil
    var feedUrl: String? = nil
    var author: String? = nil
    var episodes: [EpisodeSummary] = []
}

/// One episode row embedded in `PodcastSummary.episodes`.
struct EpisodeSummary: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var title: String
    var podcastId: String? = nil
    var podcastTitle: String? = nil
    var durationSecs: Double? = nil
    var artworkUrl: String? = nil
    /// Unix seconds from `Episode::pub_date`.
    var publishedAt: Int? = nil
    /// On-disk path to the downloaded enclosure when one exists. `nil`
    /// means the episode has not been downloaded yet. Populated by the
    /// Rust `PodcastStore::local_path_for` on each snapshot tick.
    var downloadPath: String? = nil
    /// Show notes / episode description from the RSS feed. `nil` when
    /// the underlying `Episode::description` is empty so the host can
    /// hide the show-notes section without rendering an empty container.
    var description: String? = nil
    /// Plain-text transcript. Populated after a successful
    /// `podcast.fetch_transcript` dispatch; `nil` when not yet fetched
    /// or when no publisher transcript is available for this episode.
    var transcript: String? = nil
    /// Chapter markers projected after a successful `podcast.fetch_chapters`.
    var chapters: [ChapterSummary]? = nil
    /// Persisted playback position in seconds. `nil` when the episode has
    /// not been started (or the user has rewound to 0). Populated by the
    /// Rust `PodcastStore::position_for` on each snapshot tick; drives the
    /// "Resume at X:XX" indicator in the iOS shell.
    var playbackPositionSecs: Double? = nil
}

/// Narrow chapter projection for full-player chapter rail rendering.
struct ChapterSummary: Codable, Equatable, Hashable {
    var startSecs: Double
    var endSecs: Double? = nil
    var title: String
    var imageUrl: String? = nil
    var url: String? = nil
}

/// NIP-F4 podcast discovery result row.
struct NostrShowSummary: Codable, Identifiable, Equatable, Hashable {
    var eventId: String
    var authorPubkey: String
    var title: String
    var description: String? = nil
    var feedUrl: String? = nil
    var artworkUrl: String? = nil
    var categories: [String]? = nil

    var id: String { eventId }
}

/// Active player state (present only when an episode is loaded).
struct PlayerState: Codable {
    var episodeId: String? = nil
    var url: String? = nil
    var positionSecs: Double = 0
    var durationSecs: Double? = nil
    var isPlaying: Bool = false
    var isBuffering: Bool = false
    var bufferingFraction: Double = 0
    var speed: Double = 1
    var volume: Double = 1
}

/// Active Nostr identity (present only when an account is loaded).
struct AccountSummary: Codable {
    var npub: String
    var displayName: String? = nil
    var mode: String
    var pictureUrl: String? = nil
}
