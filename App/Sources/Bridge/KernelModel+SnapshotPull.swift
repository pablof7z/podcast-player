// KernelModel+SnapshotPull.swift
// Cold-start pull guard helper split out of KernelModel.swift to keep the
// race-prone comparison testable without exposing KernelModel's private state.
//
// Also home to the snapshot-pull + kernel-update-application methods
// (`pullPodcastSnapshotIfChanged`, `applyPodcastUpdate`,
// `commitPodcastProjection`), moved here from KernelModel.swift to keep that
// file under the AGENTS.md 500-line hard limit.

import Foundation
import os.log

private let kmLog = Logger(subsystem: "io.f7z.podcast", category: "KernelModel")

extension KernelModel {
    nonisolated static func shouldPullPodcastSnapshot(
        currentRev: UInt64,
        lastProcessedRev: UInt64,
        hasHydratedPodcastSnapshot: Bool,
        allowEqualRev: Bool = false
    ) -> Bool {
        if !hasHydratedPodcastSnapshot || allowEqualRev {
            return currentRev >= lastProcessedRev
        }
        return currentRev > lastProcessedRev
    }

    /// One-shot rev-gated pull. This is NOT a poll — there is no timer; the
    /// 500ms background poll has been removed in favor of the reactive push
    /// (`apply(result:)`).
    ///
    /// The full-library `JSONDecoder` pass (`kernel.podcastSnapshot()`) is the
    /// expensive step and always runs off the MainActor on `snapshotDecodeQueue`.
    /// Dispatch sites are fire-and-forget over `@Observable`, so a one-runloop-
    /// later commit is invisible.
    ///
    /// Ordering: rapid pulls may request several decodes; the rev-monotonic
    /// guards in `applyPodcastUpdate` (`update.rev > lastProcessedRev`) and
    /// `commitPodcastProjection` (`frameRev == lastProcessedRev`) make the newest
    /// frame win and drop any stale one. `synchronous` is retained for source
    /// compatibility; decode is always off-main.
    ///
    /// Coalesced: only one decode is ever enqueued at a time. A request that
    /// arrives while one is already in flight sets `snapshotPullPending`
    /// instead of enqueuing its own full-library decode — the in-flight
    /// decode's completion consumes that flag and fires exactly one trailing
    /// pull, so a burst of N requests (e.g. one dispatch per podcast during a
    /// feed refresh) costs ~2 decodes instead of N.
    // internal (not private) so extension files can trigger snapshot pulls.
    func pullPodcastSnapshotIfChanged(
        synchronous: Bool = false,
        allowEqualRev: Bool = false
    ) {
        let currentRev = kernel.podcastSnapshotRev()
        guard Self.shouldPullPodcastSnapshot(
            currentRev: currentRev,
            lastProcessedRev: lastProcessedRev,
            hasHydratedPodcastSnapshot: hasHydratedPodcastSnapshot,
            allowEqualRev: allowEqualRev
        ) else { return }
        guard !snapshotPullInFlight else {
            snapshotPullPending = true
            return
        }
        snapshotPullInFlight = true
        let handle = kernel
        snapshotDecodeQueue.async { [weak self] in
            let update = handle.podcastSnapshot()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // Pull path always replaces the composite so push merges
                    // start from the current full state (fromPull: true).
                    self.applyPodcastUpdate(
                        update,
                        fromPull: true,
                        allowEqualRev: allowEqualRev)
                    self.snapshotPullInFlight = false
                    if self.snapshotPullPending {
                        self.snapshotPullPending = false
                        self.pullPodcastSnapshotIfChanged(allowEqualRev: true)
                    }
                }
            }
        }
    }

    /// Apply one `PodcastUpdate` to the observable surface. Shared by:
    ///   - The per-domain push path (`apply(result:)` → `mergeDomainFrames`)
    ///   - The rev-gated pull path (`pullPodcastSnapshotIfChanged`)
    ///
    /// Rev-gated so redundant frames (push at emit-Hz, or a pull racing a push)
    /// are dropped cheaply. For the push path `update` is the already-merged
    /// `compositeUpdate`; for the pull path it is the full library snapshot.
    ///
    /// This method runs the cheap, must-be-main assignments inline, then
    /// offloads the O(N×M) content/library hashing to a detached task.
    ///
    /// `fromPull`: when true, also replace `compositeUpdate` with the full
    /// snapshot so the push path's incremental merges start from a current base.
    // internal (not private) so `apply(result:)` in KernelModel.swift can call it.
    func applyPodcastUpdate(
        _ update: PodcastUpdate,
        fromPull: Bool = false,
        allowEqualRev: Bool = false
    ) {
        // Allow `>=` only when a full pull must seed or repair state after a
        // same-rev typed push. Ordinary steady-state pulls keep strict `>`.
        let revPasses = fromPull && (!hasHydratedPodcastSnapshot || allowEqualRev)
            ? update.rev >= Int(lastProcessedRev)
            : update.rev > Int(lastProcessedRev)
        guard revPasses else { return }
        lastProcessedRev = UInt64(update.rev)
        // For the pull path, replace the composite so future push merges start
        // from the current full state rather than a stale domain-by-domain build.
        if fromPull {
            compositeUpdate = update
            hasHydratedPodcastSnapshot = true
        }
        snapshot = update
        if update.downloads != downloadSnapshot { downloadSnapshot = update.downloads }
        let previousNowPlaying = nowPlaying
        nowPlaying = update.nowPlaying
        PodcastCapabilities.shared.iCloudSync.applySettingsSnapshot(
            SettingsKVSnapshot.from(podcastUpdate: update))
        // `spotlight.indexLibrary` is NOT called here. It used to run
        // unconditionally, inline, on every rev-passing frame — an O(N×M)
        // walk over the whole library on the MainActor even when nothing
        // library-related had changed (identity/social/playback-tick
        // frames all pass through here too). It now fires from
        // `commitPodcastProjection`, gated on the SAME `newLibHash`
        // check that already gates the `library` assignment below, so it
        // only runs on frames where the library actually changed — and
        // even then, `indexLibrary` itself no longer does its walk on
        // the MainActor (see SpotlightCapability.swift).
        reconcileLiveActivity(
            previous: previousNowPlaying, next: update.nowPlaying, library: update.library)
        reconcileNowPlayingMetadata(
            previous: previousNowPlaying, next: update.nowPlaying, library: update.library)
        kmLog.debug("podcast update rev=\(update.rev) library=\(update.library.count)")

        // Gate `podcastSnapshot` (and `library`) on content hashes that exclude
        // volatile position/buffering fields so list views don't re-render at
        // the emit rate. Both hashes are O(N×M) — offloaded off-main.
        let frameRev = UInt64(update.rev)
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let snapHashInterval = signposter.beginInterval("snapshotContentHash")
            let newSnapHash = self.snapshotContentHash(for: update)
            signposter.endInterval("snapshotContentHash", snapHashInterval)
            let libHashInterval = signposter.beginInterval("libraryMetaHash")
            let newLibHash = self.libraryMetaHash(for: update.library)
            signposter.endInterval("libraryMetaHash", libHashInterval)
            await MainActor.run {
                self.commitPodcastProjection(
                    update: update, frameRev: frameRev,
                    newSnapHash: newSnapHash, newLibHash: newLibHash)
            }
        }
    }

    /// Commit the rev-gated `podcastSnapshot`/`library` assignments. Shared by
    /// both the inline (pull) and detached (push) hashing paths so they can
    /// never drift. The `frameRev == lastProcessedRev` reentrancy guard is
    /// load-bearing for the async path — 4 Hz hops interleave, so a
    /// late-returning stale frame must not clobber newer state; `lastProcessedRev`
    /// is monotonic, so a newer frame already advanced it (newest wins). On the
    /// synchronous path the guard is trivially true (nothing ran between
    /// assigning `lastProcessedRev` above and arriving here).
    private func commitPodcastProjection(
        update: PodcastUpdate, frameRev: UInt64, newSnapHash: Int, newLibHash: Int
    ) {
        guard frameRev == lastProcessedRev else { return }
        if newSnapHash != lastSnapshotContentHash {
            lastSnapshotContentHash = newSnapHash
            podcastSnapshot = update
        }
        if newLibHash != lastLibraryMetaHash {
            lastLibraryMetaHash = newLibHash
            library = update.library
            // Bump AFTER the assignment so a reader that samples the generation
            // alongside `library` sees them advance together.
            libraryGeneration &+= 1
            // Fire-and-forget: `indexLibrary` spawns its own detached task
            // and returns immediately (see SpotlightCapability.swift), so
            // this call is cheap even though it's on the MainActor here.
            PodcastCapabilities.shared.spotlight.indexLibrary(update.library)
        }
    }
}
