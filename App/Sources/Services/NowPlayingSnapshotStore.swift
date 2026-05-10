import Foundation
import os.log

// MARK: - NowPlayingSnapshot (app side)

/// Shape of the metadata blob the widget consumes from the App Group
/// `UserDefaults`. Wire-compatible with the widget-side `NowPlayingSnapshot`
/// (same field names, same `Codable` semantics) — the widget defines its own
/// copy because the two targets don't share Swift types.
struct NowPlayingSnapshot: Codable, Equatable, Sendable {
    var episodeTitle: String
    var showName: String
    var imageURLString: String?
    /// Last persisted playhead in seconds.
    var position: TimeInterval
    /// Total duration in seconds. Zero when unknown.
    var duration: TimeInterval
    /// Wall-clock when the snapshot was written. Lets the widget show a
    /// "stale" treatment if needed (currently unused).
    var updatedAt: Date
    /// Title of the chapter containing the playhead, when the episode has
    /// navigable chapters. Optional so existing on-disk snapshots written
    /// by older app builds decode without migration.
    var chapterTitle: String?
    /// Whether the engine is currently playing (or buffering, which the
    /// UI treats as playing). Surfaces on the widget as a tiny play /
    /// pause glyph so the user can tell from a glance whether something
    /// is actually rolling. Optional + defaults to `false` so older
    /// snapshots decode without flagging "playing" incorrectly.
    var isPlaying: Bool?
}

// MARK: - NowPlayingSnapshotStore

/// App-side writer for the widget's `NowPlayingSnapshot`. Backed by the App
/// Group's shared `UserDefaults`, so reads from the widget extension see the
/// most recent write.
///
/// The store deliberately doesn't read — the widget extension owns reads on
/// its side. Keeping write/read isolated to their respective targets means
/// neither side needs to know about the other's lifecycle.
@MainActor
enum NowPlayingSnapshotStore {

    nonisolated private static let logger = Logger.app("NowPlayingSnapshot")

    /// App Group identifier — must match `Project.swift`'s `appGroupID` and the
    /// entitlements on both targets. Hard-coded here (rather than read from
    /// `Info.plist`) so the call site is synchronous and can't fail.
    static let appGroupID = "group.com.podcastr.app"

    /// `UserDefaults` key holding the encoded `NowPlayingSnapshot`. Stored as
    /// `Data` (JSON) so adding/removing fields doesn't fight the keyed-archive
    /// type checks `UserDefaults` does for individual values.
    static let defaultsKey = "now-playing-snapshot.v1"

    /// Writes `snapshot` into the App Group defaults. No-op when the App
    /// Group isn't reachable (simulator misconfig, missing entitlement).
    static func write(_ snapshot: NowPlayingSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            logger.error("App Group defaults unavailable for suite \(appGroupID, privacy: .public)")
            return
        }
        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: defaultsKey)
        } catch {
            logger.error("Failed to encode NowPlayingSnapshot: \(error, privacy: .public)")
        }
    }

    /// Clears the snapshot. Called when playback stops entirely so the widget
    /// reverts to its empty state on the next timeline refresh.
    static func clear() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.removeObject(forKey: defaultsKey)
    }
}
