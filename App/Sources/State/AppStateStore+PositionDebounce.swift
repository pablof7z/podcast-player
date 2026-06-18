import Foundation

// MARK: - AppStateStore + Position (render-only helpers)
//
// The Rust kernel is the sole owner of ep.position_secs persistence.
// `audio_report.rs:apply_writeback` writes position on every Playing tick
// and flushes to disk on pause/stop/sleep/end and on a ~10 s interval
// during continuous playback (POSITION_FLUSH_DELTA_SECS).
//
// Swift does NOT mirror position back to disk. The old positionCache /
// positionFlushTask / flushPendingPositions / setEpisodePlaybackPosition
// machinery has been removed (PR #572 / issue #561 M1.6). Swift is now
// purely render-only for position:
//
//   • `kernel.nowPlaying.positionSecs` is the live playhead for the scrubber.
//   • `episode.playbackPosition` (from ep.position_secs via toEpisode) is the
//     last kernel-persisted resume point shown on the episode row.
//   • `episode(id:)` applies the live kernel position as a floor when the
//     episode is currently loaded — render-only, never written to disk.
//
// The background flush observer, positionCache, and the old
// synchronousPositionFlushForUITests flag have been removed (PR #572).
// The UITestSeeder --UITestSeedRelaunch path preserves podcasts.json so
// the kernel's own persisted position survives the relaunch, proving the
// end-to-end single-source-of-truth contract.

extension AppStateStore {

    /// Folds the live kernel position into a list of episodes for display.
    /// No-op when nothing is playing. This is a render-only overlay — no
    /// data is written to disk. Callers that only need the playing episode's
    /// position should read `kernel.nowPlaying.positionSecs` directly.
    func applyingLivePosition(_ episodes: [Episode]) -> [Episode] {
        guard let np = kernel?.nowPlaying,
              np.isPlaying,
              let idStr = np.episodeId,
              let playingID = UUID(uuidString: idStr),
              np.positionSecs > 0
        else { return episodes }
        guard episodes.contains(where: { $0.id == playingID }) else { return episodes }
        return episodes.map { episode in
            guard episode.id == playingID,
                  np.positionSecs > episode.playbackPosition
            else { return episode }
            var copy = episode
            copy.playbackPosition = np.positionSecs
            return copy
        }
    }
}
