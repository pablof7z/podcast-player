import Foundation
import Observation
import SwiftUI
import os.log

private let kmLog = Logger(subsystem: "io.f7z.podcast", category: "KernelModel")

/// `@Observable` mirror of the kernel snapshot. The Rust actor pushes
/// JSON updates via the C callback; this class decodes them and republishes
/// for SwiftUI consumption.
///
/// Thin-shell: all state lives in `snapshot`. No business logic. No derived
/// caches. Every accessor is a pure read of the kernel snapshot (D2, D4, D8).
///
/// `@Observable` (not `ObservableObject`) so the migrated Identity / Agent /
/// Onboarding views can use `@Environment(KernelModel.self)`. Observation is
/// emitted automatically for plain stored properties.
@MainActor
@Observable
final class KernelModel {

    // ── External-scene shared handle ───────────────────────────────────────

    /// Process-wide weak handle to the live `KernelModel`. Used by surfaces
    /// that execute outside the SwiftUI environment chain — today that means
    /// iOS `AppIntent` performers (Siri/Shortcuts) and `CarPlaySceneDelegate`
    /// (a `UIResponder` instantiated by the OS for the
    /// `CPTemplateApplicationScene` role). Gives intent and scene code a
    /// stable pointer to the same model the UI is reading without forcing a
    /// singleton lifetime.
    ///
    /// `weak` so the model still deallocates on scene teardown; the next
    /// `KernelModel.init` re-publishes from its own initializer.
    ///
    /// `nonisolated(unsafe)` is required because `@MainActor`-isolated stored
    /// properties cannot be `static`. The lone writer is `KernelModel.init`
    /// (which runs on `@MainActor` per the class isolation); the readers are
    /// also `@MainActor`. The pointer is never published off the main thread.
    nonisolated(unsafe) static weak var shared: KernelModel?

    // ── Snapshot slot ──────────────────────────────────────────────────────

    /// Latest decoded snapshot. `nil` before the first tick lands.
    // widened to internal so KernelModel+SnapshotPull can write it
    var snapshot: PodcastUpdate?

    /// Latest download-queue snapshot, updated on every accepted frame where
    /// the downloads value changed. `podcastSnapshot` deliberately excludes
    /// `d.progress` from its content hash to avoid per-second list churn;
    /// this property is the dedicated observation target so `AppStateStore`
    /// can re-run `applyDownloadOverlay` with fresh progress values.
    // widened to internal so KernelModel+Reports can write on download ticks
    var downloadSnapshot: DownloadQueueSnapshot?

    // ── Local counters ─────────────────────────────────────────────────────

    private(set) var snapshotCount: UInt64 = 0
    private(set) var lastSnapshotAt: Date?

    /// Clearable toast text sourced from snapshot or synchronous dispatch
    /// rejections.
    // widened to internal so KernelModel+Dispatch can clear/set it
    var lastErrorToast: String?

    /// Mandatory NMP v0.1.0 surface (V-67). Non-nil when the kernel could not
    /// open its on-disk LMDB store and fell back to in-memory — this session's
    /// data will not persist. Carried on every accepted tick (set on failure,
    /// cleared back to `nil` once the store recovers). RootView presents a
    /// user-facing alert; the kernel actor is the sole writer.
    private(set) var storeOpenFailure: String?

    private(set) var kernelIdentity: KernelIdentityProjection = .empty
    private(set) var nostrSearchSessions: [String: NostrSearchResultsSnapshot] = [:]

    /// D7 actor-death surface — flips to `true` exactly once when the Rust
    /// supervisor emits a panic frame or the foreground-resume probe detects
    /// the actor gone. Terminal: only a process restart recovers.
    private(set) var kernelIsDead: Bool = false

    var visibleLimit: UInt32 = 80
    var emitHz: UInt32 = 4

    // ── Podcast projection (polled separately from NMP kernel snapshot) ───

    /// Latest podcast library decoded from the Rust podcast snapshot.
    // widened to internal so KernelModel+SnapshotPull can write it
    var library: [PodcastSummary] = []
    /// Monotonic generation bumped each time `library` is reassigned (i.e. on
    /// every `libraryMetaHash` change — see `commitPodcastProjection`). The
    /// kernel-projection pass reads this to detect, in O(1), that a tick fired
    /// purely on a `podcastSnapshot`/`kernelIdentity` change while `library`
    /// stayed byte-identical — letting it skip the O(N) episode rebuild.
    /// `@ObservationIgnored`: callers already observe `library`; a separate
    /// tracked generation would arm a redundant observation.
    // widened to internal so KernelModel+SnapshotPull can write it
    @ObservationIgnored var libraryGeneration: Int = 0
    /// Latest full podcast snapshot (library, player, account …).
    // widened to internal so KernelModel+SnapshotPull can write it
    var podcastSnapshot: PodcastUpdate?
    /// Live player state — updated on every snapshot tick (4 Hz during playback).
    /// Views that only need player position should observe this instead of
    /// `podcastSnapshot?.nowPlaying` so they don't hold a reference to the
    /// full snapshot struct. All other views should use `podcastSnapshot`.
    // widened to internal so KernelModel+Reports can update on audio ticks
    var nowPlaying: PlayerState?
    /// Called on the MainActor on every `Playing` audio report with the
    /// episode id string and position (seconds). Wired by `attachKernel` so
    /// UI consumers (scrubber, Live Activity) receive live position ticks
    /// without relying on `withObservationTracking`.
    var onPositionTick: ((String, Double) -> Void)?
    /// Called on the MainActor when Rust completes an agent-ask lifecycle
    /// event asynchronously, currently timeout expiry.
    var onAgentAskEvent: ((AgentAskResponse) -> Void)?
    /// Hash of the library fields that matter to list views. Excludes
    /// `playbackPositionSecs` so list views don't re-render at 4 Hz
    /// during playback (the position is only needed by the player row).
    // widened to internal so KernelModel+SnapshotPull can write it
    var lastLibraryMetaHash: Int = 0
    /// Hash of the snapshot fields that matter to non-player UI. Excludes
    /// `nowPlaying.positionSecs` and `nowPlaying.bufferingFraction` so
    /// views like HomeView, InboxView, etc. don't re-render at 4 Hz.
    // widened to internal so KernelModel+SnapshotPull can write it
    var lastSnapshotContentHash: Int = 0
    /// Rev of the last snapshot we decoded from the kernel. Unlike
    /// `podcastSnapshot?.rev` (which only advances on content changes),
    /// this tracks every processed tick so the short-circuit guards stay
    /// accurate.
    // widened to internal so KernelModel+SnapshotPull can read/write it
    var lastProcessedRev: UInt64 = 0
    /// `false` until the first cold-start full pull has been successfully
    /// applied. Guards the re-seed allowance: before the first hydration
    /// the pull path uses `>=` instead of `>` when comparing
    /// `update.rev` against `lastProcessedRev`, so a partial push frame
    /// that races the startup pull and advances `lastProcessedRev` cannot
    /// permanently block the full-library snapshot from seeding the
    /// composite. Flipped to `true` inside `applyPodcastUpdate` the
    /// moment the first `fromPull` frame commits; after that the
    /// steady-state `>` guard is restored for both push and pull paths.
    // widened to internal so KernelModel+SnapshotPull can write it
    var hasHydratedPodcastSnapshot: Bool = false
    /// Per-domain last-applied rev counters. Each domain frame's `rev` is
    /// compared here before merging — stale/duplicate frames are dropped
    /// without touching the composite.
    private var domainRevTracker = DomainRevTracker()
    /// Composite `PodcastUpdate` — the current merged state built by
    /// selectively replacing domains as per-domain push frames arrive. The
    /// pull path replaces the entire composite on cold-start / fallback.
    // widened to internal so KernelModel+SnapshotPull can write it
    var compositeUpdate: PodcastUpdate = PodcastUpdate()
    /// Serial queue for the off-MainActor full-library snapshot decode. The
    /// `JSONDecoder` pass measured ~35 ms on the simulator (≈100 ms on device)
    /// at 3.6k episodes — it must never run on the MainActor. Serial so a burst
    /// of rapid dispatches doesn't pile up concurrent multi-MB decodes; the
    /// rev-monotonic guards in `applyPodcastUpdate` drop any stale frame that a
    /// late decode produces. See `docs/perf/ffi-snapshot-transport-findings.md`.
    // widened to internal so KernelModel+SnapshotPull can read it
    let snapshotDecodeQueue = DispatchQueue(
        label: "podcast.snapshot-decode", qos: .userInitiated)
    /// `true` while a full-library decode is enqueued/running on
    /// `snapshotDecodeQueue`. Every `dispatch(namespace:body:)` call ends
    /// with `pullPodcastSnapshotIfChanged(allowEqualRev: true)` (see
    /// `KernelModel+Dispatch.swift`), so a fan-out like a feed refresh that
    /// issues one dispatch per podcast used to enqueue one ~8 MB JSON
    /// decode per podcast — dozens of redundant decodes of data that
    /// settles once. This flag plus `snapshotPullPending` below coalesces
    /// a burst of requests into the in-flight decode plus at most one
    /// trailing follow-up, instead of one decode per caller.
    // widened to internal so KernelModel+SnapshotPull can read/write it
    var snapshotPullInFlight = false
    /// Set when a pull is requested while one is already in flight.
    /// Consumed by the in-flight decode's completion, which kicks off
    /// exactly one more pull so the final settled state still lands.
    // widened to internal so KernelModel+SnapshotPull can read/write it
    var snapshotPullPending = false

    // ── Computed projections ───────────────────────────────────────────────

    var isRunning: Bool { snapshot?.running ?? false }
    var rev: Int { snapshot?.rev ?? 0 }
    /// Non-optional convenience for the podcast settings projection.
    /// Falls back to `SettingsSnapshot()` (default values) before the
    /// first podcast snapshot tick — all callers get a coherent value.
    var settings: SettingsSnapshot { podcastSnapshot?.settings ?? SettingsSnapshot() }

    // ── Implementation ─────────────────────────────────────────────────────

    let kernel = PodcastHandle() // internal: extension files dispatch through it
    private var startedKernel = false

    init() {
        kernel.listen({ [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                MainActor.assumeIsolated { self.apply(result: result) }
            }
        }, onPanic: { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                MainActor.assumeIsolated { self.markKernelDead() }
            }
        })
        kernel.attachAudioReportChannel()
        kernel.attachDownloadReportChannel()
        kernel.attachHttpReportChannel()
        // Prime Rust's is_on_wifi flag before the first feed refresh.
        kernel.startNetworkMonitor()
        // Reactive replacement for the old 500ms poll: shell-initiated FFI
        // reports (audio/download/voice) bump the podcast `rev` without emitting
        // a kernel push frame, so surface them with a one-shot rev-gated pull at
        // the moment they happen. Dispatched host-ops already arrive via the
        // push frame (`apply`) and `dispatch`/`dispatchSilent`'s own pull.
        //
        // Audio reports fire at playback frequency, so this hook is a 4 Hz hot
        // path — the full-library decode and the O(N×M) list hashing both run off
        // the MainActor (see `pullPodcastSnapshotIfChanged`). Live player position
        // still updates inline via `nowPlaying`/`snapshot` at the top of
        // `applyPodcastUpdate`.
        kernel.onSnapshotMaybeChanged = { [weak self] in
            self?.pullPodcastSnapshotIfChanged()
        }
        // Download reports carry their own narrow snapshot inline; progress ticks
        // no longer bump the global `rev`, so they must NOT pull/decode the full
        // library. Update `downloadSnapshot` directly (drives the row overlay) and
        // pull only when durable library state changed (completion/cancellation).
        kernel.onDownloadReport = { [weak self] downloads, durableChanged in
            self?.applyDownloadReport(downloads: downloads, durableChanged: durableChanged)
        }
        // Audio reports carry the fresh player state inline; `Playing`/buffering
        // ticks no longer bump the global `rev`, so they must NOT pull/decode the
        // full library. Update `nowPlaying` + the live media surfaces directly
        // and pull only when structural state changed (play/pause/stop, end).
        kernel.onAudioReport = { [weak self] nowPlaying, durableChanged in
            self?.applyAudioReport(nowPlaying: nowPlaying, durableChanged: durableChanged)
        }
        // Publish to the shared handle for external scenes (CarPlay, AppIntents,
        // …). The static is `weak`, so the model still deallocates on scene
        // teardown; the next instance re-publishes from its own `init`.
        Self.shared = self
        kernel.attachVoiceReportChannel()
        kernel.onAgentAskEvent = { [weak self] response in
            self?.onAgentAskEvent?(response)
        }
    }

    private func markKernelDead() {
        if kernelIsDead { return }
        kmLog.fault("kernelIsDead set — actor thread terminated")
        kernelIsDead = true
    }

    /// Pull-side actor-liveness probe (ADR-0028). Called by the app on every
    /// `.active` scenePhase to catch panics that occurred while backgrounded.
    func checkAlive() {
        if kernelIsDead { return }
        if !kernel.isAlive() {
            markKernelDead()
        }
    }

    // ── Lifecycle ──────────────────────────────────────────────────────────

    func start() {
        guard !startedKernel else { return }
        startedKernel = true
        kernel.start(visibleLimit: visibleLimit, emitHz: emitHz)
        // One-shot startup pull: the persisted library is loaded during register,
        // so it's already in the projection — surface it once. The decode runs
        // off the MainActor (a 3.6k-episode library decode would otherwise block
        // the launch MainActor for ~100 ms); the first frame lands a runloop
        // later, which is imperceptible at launch. Everything after this is
        // event-driven (push frame + report hooks); no timer/poll.
        pullPodcastSnapshotIfChanged()
    }

    func stop() {
        kernel.stop()
        startedKernel = false
    }

    func resetAndRestart() {
        kernel.reset()
        snapshot = nil
        podcastSnapshot = nil
        library = []
        lastProcessedRev = 0
        hasHydratedPodcastSnapshot = false
        domainRevTracker = DomainRevTracker()
        compositeUpdate = PodcastUpdate()
        kernel.reregisterPodcastProjection()
        lastErrorToast = nil
        storeOpenFailure = nil
        nostrSearchSessions = [:]
        kernel.start(visibleLimit: visibleLimit, emitHz: emitHz)
        startedKernel = true
        // One-shot post-reset pull — surface the re-registered projection. Decode
        // runs off the MainActor; the rebuilt UI is current a runloop later.
        pullPodcastSnapshotIfChanged()
    }

    // `pullPodcastSnapshotIfChanged` / `applyPodcastUpdate` / `commitPodcastProjection`
    // moved to KernelModel+SnapshotPull.swift (file-size cap, AGENTS.md).

    func applyConfiguration() {
        kernel.configure(visibleLimit: visibleLimit, emitHz: emitHz)
    }

    // ── scenePhase pass-through ────────────────────────────────────────────

    // widened so KernelModel+Dispatch can write it in lifecycleForeground
    var hasObservedForeground = false

    // ── Snapshot apply ─────────────────────────────────────────────────────

    private func apply(result: KernelUpdateResult) {
        // Perf: time the synchronous main-actor segment of every accepted push
        // frame. The O(N×M) hashing it kicks off is offloaded off-main.
        let applyStart = DispatchTime.now().uptimeNanoseconds
        defer {
            PerfMetrics.shared.record(
                .mainApply,
                micros: Int((DispatchTime.now().uptimeNanoseconds &- applyStart) / 1_000))
        }
        // Store-open-failure fires before rev-gating so the mandatory alert shows.
        storeOpenFailure = result.storeOpenFailure
        if !result.nostrSearchSessions.isEmpty {
            for (session, snapshot) in result.nostrSearchSessions {
                nostrSearchSessions[session] = snapshot
            }
        }
        // Identity: only replace when the identity domain sidecar was present in
        // this frame (result.identity != .empty). Absent = identity unchanged;
        // preserve the current kernelIdentity rather than clobbering with .empty.
        // This is correct because the kernel only emits the identity sidecar when
        // the identity domain rev advanced (sign-in, sign-out, account change).
        if result.identity != .empty {
            if result.identity != kernelIdentity {
                kernelIdentity = result.identity
            }
        } else if !result.domainFrames.resolvedProfiles.isEmpty {
            // `resolved_profiles` is top-level, not an identity sidecar. Merge it
            // additively so active-account fields are not clobbered.
            let merged = kernelIdentity.merging(
                resolvedProfiles: result.domainFrames.resolvedProfiles)
            if merged != kernelIdentity {
                kernelIdentity = merged
            }
        }
        snapshotCount &+= 1
        lastSnapshotAt = Date()

        // Merge each present domain into the composite and flow through
        // applyPodcastUpdate only when at least one domain was accepted.
        // The drop-guard inside mergeDomainFrames handles stale/duplicate frames.
        let accepted = mergeDomainFrames(
            result.domainFrames,
            into: &compositeUpdate,
            tracker: &domainRevTracker)
        guard accepted else { return }

        // Advance the composite rev to the max accepted domain rev so
        // applyPodcastUpdate's rev-monotonic guard lets it through. Use the
        // highest rev across all present domains.
        let maxDomainRev = maxRev(result.domainFrames)
        if compositeUpdate.rev < Int(maxDomainRev) {
            compositeUpdate.rev = Int(maxDomainRev)
        }
        // The kernel is running whenever it emits domain frames — set the flag
        // so `isRunning` stays accurate without a full snapshot pull.
        compositeUpdate.running = true

        // Pass fromPull: false — the composite is already up-to-date; we do NOT
        // want to overwrite it with the full pull snapshot.
        applyPodcastUpdate(compositeUpdate, fromPull: false)
    }

    /// Highest `rev` across all domain frames present in the push frame.
    private func maxRev(_ frames: PodcastDomainFrames) -> UInt64 {
        [frames.library?.rev, frames.playback?.rev, frames.downloads?.rev,
         frames.settings?.rev, frames.identity?.rev, frames.widget?.rev,
         frames.social?.rev, frames.voice?.rev, frames.misc?.rev].compactMap { $0 }.max() ?? 0
    }
}
