import Foundation
import UIKit

// MARK: - AppStateStore + PositionDebounce (render-only position cache)
//
// **Role after the kernel single-source-of-truth migration.**
// The Rust kernel is the sole owner of ep.position_secs persistence.
// `audio_report.rs:apply_writeback` writes position on every Playing tick
// and flushes to disk on pause/stop. Swift does NOT mirror position back
// to the kernel (`kernelPersistPosition` is no longer called from here).
//
// This file's remaining job is **render-only**: the audio engine ticks at
// ≤4 Hz while playback runs and `KernelModel.onPositionTick` forwards the
// kernel-reported position here via `setEpisodePlaybackPosition`. The
// `positionCache` keeps the live playhead in memory so UI reads (`episode(id:)`,
// `inProgressEpisodes`, `recentEpisodes`) always see the current scrubber
// position without waiting for a full `@Observable` write on every tick.
//
// Flushing the cache into `self.episodes` (so the position lands in the
// observable store for downstream consumers) is still debounced:
//
//   - **Eager-first:** the very first position update after a flush is
//     written immediately — a crash 0.5 sec after playback starts must
//     not lose all UI-side progress state.
//   - **Trailing debounce (5 s):** subsequent rapid updates queue in the
//     cache; the Task fires 5 s after the last update.
//   - **Max-interval cap (30 s):** the eager-first gate re-opens after
//     30 s so continuous playback gets at most one `self.episodes` write
//     per 30 s.
//
// **Hard flush events** (need cache in self.episodes *now*):
//   - `markEpisodePlayed(_:)` — played-true mutation must see the latest pos.
//   - `UIApplication.didEnterBackgroundNotification` — force-quit window.
//   - `clearAllData()` — cache holds positions for episodes about to be wiped.
//
// Kernel persistence guarantee: the kernel flushes ep.position_secs to
// podcasts.json on every Paused/Stopped/SleepTimerFired event AND on a
// coarse ≥POSITION_FLUSH_DELTA_SECS (30 s) interval during Playing. A cold
// relaunch reads that file; no Swift mirror-back is needed or correct.

extension AppStateStore {

    // MARK: - Tunables

    /// Trailing debounce window. After the last `setEpisodePlaybackPosition`
    /// call, wait this long before writing the cache to disk. Long enough
    /// that a tight 1 Hz loop never fires it; short enough that pausing
    /// mid-episode lands the position on disk before the user puts the phone
    /// down.
    static var positionDebounceInterval: TimeInterval { 5 }

    /// Maximum time the cache may hold an unwritten position during
    /// continuous playback. Once this elapses, the next
    /// `setEpisodePlaybackPosition` re-opens the eager-first gate and writes
    /// straight to disk. 30 sec matches the task's "≤ 30 sec lost on crash"
    /// guarantee.
    static var positionMaxInterval: TimeInterval { 30 }

    // MARK: - Public entry points

    /// Records a playback-position update. Cheap: writes to an in-memory
    /// cache and either fires an eager save (first update / max-interval
    /// elapsed) or schedules a trailing-debounce flush.
    ///
    /// Idempotent on no-op: if the cached value already equals `position`
    /// we skip the bookkeeping entirely so the engine's coalesced ticks
    /// don't double-touch the cache.
    func setEpisodePlaybackPosition(_ id: UUID, position: TimeInterval) {
        guard let idx = self.episodes.firstIndex(where: { $0.id == id }) else {
            positionCache.removeValue(forKey: id)
            return
        }

        // Effective current position is whichever is more recent: cache
        // wins if it's been touched since the last flush, else fall back
        // to the persisted record.
        let liveCurrent = positionCache[id] ?? self.episodes[idx].playbackPosition
        guard liveCurrent != position else { return }


        positionCache[id] = position

        let now = Date()
        let dueForEager: Bool
        if Self.synchronousPositionFlushForUITests {
            // Under --UITestSeed every tick writes synchronously so a SIGKILL
            // force-quit at any point during playback still preserves the
            // latest position. The normal 30s max-interval cap is irrelevant
            // here because `flushToDiskNow` in `flushPendingPositions` already
            // bypasses the background-Task path — the only additional cost is
            // calling `flushPendingPositions` on every tick instead of every
            // 30s, which is acceptable for a UI test.
            dueForEager = true
        } else if let last = lastPositionFlush {
            dueForEager = now.timeIntervalSince(last) >= Self.positionMaxInterval
        } else {
            // No save has happened yet for any episode — write immediately
            // so a crash 200 ms into playback still preserves *some*
            // progress.
            dueForEager = true
        }

        if dueForEager {
            flushPendingPositions()
        } else {
            schedulePositionDebounce()
        }
    }

    /// Drains the position cache into `self.episodes` and lets the existing
    /// `state.didSet` save the file. Safe to call from any path that needs
    /// the cache on disk synchronously (background notification, mark-played,
    /// clearAllData, episode-end). Idempotent on empty cache.
    func flushPendingPositions() {
        positionFlushTask?.cancel()
        positionFlushTask = nil

        guard !positionCache.isEmpty else {
            // Even with nothing pending, refresh `lastPositionFlush` so the
            // eager-first gate stays on its 30s cadence after an explicit
            // flush event (background, mark-played).
            lastPositionFlush = Date()
            return
        }

        // Build the mutation in one pass against a working copy so we hit
        // `state.didSet` exactly once — N cached entries become a single
        // 8 MB save, not N saves.
        var working = self.episodes
        var mutated = false
        for (id, position) in positionCache {
            guard let idx = working.firstIndex(where: { $0.id == id }) else { continue }
            if working[idx].playbackPosition != position {
                working[idx].playbackPosition = position
                mutated = true
            }
        }

        // The Rust kernel persists ep.position_secs directly from audio reports
        // (audio_report.rs apply_writeback). Swift does not mirror position back
        // into the kernel — that was a split-brain write path. The kernel is now
        // the single source of truth for position persistence; Swift's cache here
        // is render-only (feeds episode(id:) so the UI shows a live playhead).
        positionCache.removeAll(keepingCapacity: true)
        lastPositionFlush = Date()

        if mutated {
            performMutationBatch {
                self.episodes = working
                // Historical compatibility hook: in-progress projections are
                // Rust-owned now, but mutation paths still call the no-op shim.
                invalidateEpisodeProjections()
            }
        }
        // Under --UITestSeed the background write Task can be killed before it
        // runs (the test runner sends SIGKILL immediately after app.terminate()).
        // Write synchronously here unconditionally (not guarded by `mutated`) so
        // SQLite is durably updated before any force-quit, even when
        // applyKernelSnapshotOnlyState already folded the same position into
        // self.episodes via performMutationBatch (making mutated=false). All other
        // writes keep their background-Task behaviour to avoid throttling the 4 Hz
        // kernel tick on the main thread.
        if Self.synchronousPositionFlushForUITests {
            var snapshot = state
            snapshot.episodes = self.episodes
            persistence.flushToDiskNow(snapshot)
        }
    }

    // MARK: - Cache-fold reads
    //
    // Folded into the existing `episode(id:)` / `inProgressEpisodes` /
    // `recentEpisodes` getters in `AppStateStore+Episodes.swift` via these
    // helpers. Kept here next to the cache so the read/write contract lives
    // in one place — anyone changing the cache shape will see the readers
    // immediately below it.

    /// Returns the cached position for `id` if one is pending, else `nil`.
    /// Callers fall back to the value from `self.episodes`.
    func cachedPosition(for id: UUID) -> TimeInterval? {
        positionCache[id]
    }

    /// Folds the position cache into a list of episodes. Used by the
    /// in-progress / recent / per-show feeds so a freshly-started episode
    /// shows up with its live playhead without waiting for the first 30s
    /// flush.
    ///
    /// **Allocation contract.** This is called from `inProgressEpisodesView`,
    /// `recentEpisodesView`, and `episodesForShowView` — each fires inside a
    /// SwiftUI `body` getter that re-runs on every scroll tick and every
    /// playback tick. The naive `.map` below allocates a fresh array and
    /// ARC-churns every `Episode` struct on *every* read, even when the
    /// cache holds nothing relevant to this slice. Two guards keep the
    /// common case allocation-free:
    ///
    ///   1. **Empty cache** (no playback in flight) → return the input.
    ///   2. **Disjoint slice** — cache non-empty, but no episode in this
    ///      slice has a pending position (during playback only the playing
    ///      episode's show overlaps) → return the input unchanged. Swift's
    ///      copy-on-write makes this a refcount bump, not an N-element copy.
    ///
    /// Both guards still *read* `positionCache` every pass, so the
    /// `@Observable` dependency registers and the views re-render correctly
    /// when the cache changes. The `.map` runs only for the slice that
    /// actually overlaps the cache, where the copy is unavoidable (we must
    /// surface the live position) and bounded to that one show / feed.
    func applyingPositionCache(_ episodes: [Episode]) -> [Episode] {
        guard !positionCache.isEmpty else { return episodes }
        guard episodes.contains(where: { positionCache[$0.id] != nil }) else {
            return episodes
        }
        return episodes.map { episode in
            guard let cached = positionCache[episode.id] else { return episode }
            var copy = episode
            copy.playbackPosition = cached
            return copy
        }
    }

    // MARK: - Lifecycle hooks (called from AppStateStore.init)

    /// Subscribes the store to `UIApplication.didEnterBackgroundNotification`
    /// so the cache is flushed when the user backgrounds the app — covering
    /// the force-quit window where neither pause nor episode-end fires.
    /// Returns the observer token; callers retain it on the store so removal
    /// happens at deinit.
    func registerBackgroundFlushObserver() -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Mirror the iCloud observer pattern already in `init`: the
            // Notification queue delivers on .main so the closure is
            // already on the main thread; `assumeIsolated` lets us cross
            // back into the actor-isolated method without an `await`.
            MainActor.assumeIsolated {
                self?.flushPendingPositions()
            }
        }
    }

    // MARK: - Private — debounce machinery

    /// Schedules a flush task to fire `positionDebounceInterval` seconds
    /// from now. Cancels any prior pending task so successive calls within
    /// the window keep extending the deadline (true trailing debounce).
    private func schedulePositionDebounce() {
        positionFlushTask?.cancel()
        positionFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.positionDebounceInterval))
            guard let self, !Task.isCancelled else { return }
            self.flushPendingPositions()
        }
    }
}
