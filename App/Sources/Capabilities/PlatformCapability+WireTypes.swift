import Foundation

// MARK: - PlatformCapability wire types (Swift mirrors of the Rust schema)
//
// Lifted out of `PlatformCapability.swift` so the capability file stays
// under the soft 300-line limit (AGENTS.md). The types remain top-level —
// the tests + the iOS observers reference them as `WidgetSnapshot`,
// `HandoffState`, `HandoffUserInfoKey` directly, so moving them changes
// nothing for callers.
//
// Source of truth (Rust):
//   - `apps/nmp-app-podcast/src/ffi/snapshot.rs` — `WidgetSnapshot`
//   - `apps/podcast-core/src/types/handoff.rs`   — `HandoffState`
//
// Tests pinning the JSON shape: `PlatformCapabilityWireTests.swift`.

/// Swift mirror of `apps/nmp-app-podcast/src/ffi/snapshot.rs`
/// `WidgetSnapshot`. Hand-mirrored (not generated) until the
/// `dump_projection_schemas` codegen catches up — keep the field
/// names + `Codable` semantics in lock-step with the Rust source.
///
/// The widget extension decodes the JSON payload this struct
/// encodes; the extension defines its own copy of the type because
/// the two targets don't share Swift sources.
///
/// IMPORTANT — NO explicit `CodingKeys`. This type is embedded in
/// `PodcastUpdate`, which `KernelBridge` decodes with
/// `keyDecodingStrategy = .convertFromSnakeCase`. That strategy rewrites the
/// wire keys (`is_playing` → `isPlaying`) *before* key lookup, so the
/// synthesized camelCase keys are exactly what's required. Declaring explicit
/// snake_case `CodingKeys` here double-converts and makes every key miss — the
/// required `isPlaying` then throws `keyNotFound` and fails the **entire**
/// `PodcastUpdate` decode on every push/pull frame (the live regression caught
/// in PR #366 review: the library froze at "No episodes yet"). Property names
/// must be the camelCase the strategy produces, including its acronym
/// lowercasing: `artwork_url` → `artworkUrl` (not `artworkURL`).
struct WidgetSnapshot: Codable, Equatable {
    var nowPlayingEpisodeTitle: String?
    var nowPlayingPodcastTitle: String?
    var nowPlayingArtworkUrl: String?
    /// Active chapter title at the playhead, preferred over the show
    /// name on the medium widget. `nil` for chapter-less episodes.
    var nowPlayingChapterTitle: String?
    var isPlaying: Bool
    /// `0.0..=1.0`; pre-computed by Rust so the widget can render
    /// a ring without dividing by a possibly-zero duration.
    var positionFraction: Float
    /// Current playhead in seconds — paired with `durationSecs` so the
    /// widget renders the exact "−MM:SS remaining" label the player shows.
    var positionSecs: Double
    /// Track duration in seconds; `0` until the capability reports it.
    var durationSecs: Double
    var unplayedCount: Int
}

/// Swift mirror of `apps/podcast-core/src/types/handoff.rs`
/// `HandoffState`. The Rust side guarantees `activityType` is
/// one of the known string ids; `isKnownActivityType` performs
/// the defensive check on the iOS side (D6 — unknown wire data
/// is dropped, not thrown).
struct HandoffState: Codable, Equatable {
    /// `io.f7z.podcast.playing` — playback in progress.
    static let activityPlaying = "io.f7z.podcast.playing"
    /// `io.f7z.podcast.browsing` — non-player surface foregrounded.
    static let activityBrowsing = "io.f7z.podcast.browsing"

    var activityType: String
    var episodeID: String?
    var podcastID: String?
    var positionSecs: Double?

    enum CodingKeys: String, CodingKey {
        case activityType = "activity_type"
        case episodeID = "episode_id"
        case podcastID = "podcast_id"
        case positionSecs = "position_secs"
    }

    /// `true` when `activityType` matches one of the platform
    /// capability's known activity ids.
    var isKnownActivityType: Bool {
        switch activityType {
        case Self.activityPlaying, Self.activityBrowsing:
            return true
        default:
            return false
        }
    }
}

/// `userInfo` keys the iOS executor populates on a donated
/// `NSUserActivity`. The receiving side (the same app on another
/// device) reads back via these keys.
///
/// Field names mirror `HandoffState`'s snake-case `CodingKeys`
/// because the kernel's wire shape is the contract; tests in
/// `PlatformCapabilityWireTests` pin this equivalence.
enum HandoffUserInfoKey {
    static let episodeID = "episode_id"
    static let podcastID = "podcast_id"
    static let positionSecs = "position_secs"
}
