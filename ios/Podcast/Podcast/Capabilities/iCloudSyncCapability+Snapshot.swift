import Foundation

// MARK: - SettingsKVSnapshot
//
// Decoupled snapshot of the kernel-side fields the iCloud sync capability
// mirrors. Defined here (not on `SettingsSnapshot`) so the capability does
// not need to wait for `pr-settings-projection` to land the playback fields
// on the projection. The snapshot poll constructs one of these from
// whatever subset of fields the current `SettingsSnapshot` exposes; missing
// fields stay `nil` and are simply skipped on the outbound path.

/// Plain-data view of the subset of settings the iCloud capability mirrors.
/// Fields are optional because the `SettingsSnapshot` projection may not yet
/// carry every field on every binary — a `nil` field is a "kernel hasn't
/// projected this yet, skip" signal.
struct SettingsKVSnapshot: Equatable {
    var speed: Double?
    var skipForwardSecs: Int?
    var skipBackwardSecs: Int?
    var autoSkipAds: Bool?
    var streamingOnly: Bool?

    /// All-`nil` snapshot. Returned by the `PodcastUpdate` bridge when the
    /// active kernel projection does not (yet) carry any of the playback
    /// fields the capability syncs.
    static let empty = SettingsKVSnapshot()

    /// Seed the capability's `lastWritten` map with this snapshot's present
    /// fields. Used during inbound merges so the next outbound diff does
    /// not re-emit the value we just applied.
    func write(to lastWritten: inout [String: AnyHashable]) {
        if let speed {
            lastWritten[iCloudSyncCapability.Key.speed] = AnyHashable(speed)
        }
        if let v = skipForwardSecs {
            lastWritten[iCloudSyncCapability.Key.skipForwardSecs] = AnyHashable(v)
        }
        if let v = skipBackwardSecs {
            lastWritten[iCloudSyncCapability.Key.skipBackwardSecs] = AnyHashable(v)
        }
        if let v = autoSkipAds {
            lastWritten[iCloudSyncCapability.Key.autoSkipAds] = AnyHashable(v)
        }
        if let v = streamingOnly {
            lastWritten[iCloudSyncCapability.Key.streamingOnly] = AnyHashable(v)
        }
    }
}

// MARK: - PodcastUpdate bridge
//
// Maps the current kernel `PodcastUpdate` into the subset of fields this
// capability mirrors to iCloud. Today the snapshot only exposes playback
// speed (via `nowPlaying.speed`, which is the live player rate). The other
// three fields — skip intervals, auto-skip-ads, streaming-only — land on
// the `SettingsSnapshot` projection in `pr-settings-projection`; until
// that PR merges this extension returns `nil` for them, which the
// capability's outbound path skips.
//
// When the settings projection lands, expand the bridge with the
// projection fields (e.g. `update.settings.skipForwardSecs`). The
// capability itself is already wired — this is the single site that
// needs to change.

extension SettingsKVSnapshot {
    /// Build a snapshot from the current kernel `PodcastUpdate`. The
    /// playback speed comes from the live player state, which is the
    /// authoritative value the user just selected via the speed chip.
    /// Fields the snapshot does not yet carry stay `nil`; the
    /// capability's outbound path treats `nil` as "skip this key".
    static func from(podcastUpdate update: PodcastUpdate) -> SettingsKVSnapshot {
        SettingsKVSnapshot(
            speed: update.nowPlaying?.speed,
            // The next three are projected via `SettingsSnapshot` once
            // `pr-settings-projection` lands the fields.
            skipForwardSecs: nil,
            skipBackwardSecs: nil,
            autoSkipAds: nil,
            streamingOnly: nil)
    }
}
