import Darwin
import Foundation
import os.log

let kbLog = Logger(subsystem: "io.f7z.podcast", category: "KernelBridge")

/// Mirror of the kernel's `schema_version` (Rust: `nmp_core::SNAPSHOT_SCHEMA_VERSION`),
/// emitted on every `PodcastUpdate` projection. Must be bumped in lock-step when the
/// Rust constant changes; snapshot decoding fails closed on a mismatch (#356) rather
/// than silently misparsing a newer/older schema.
let KERNEL_SCHEMA_VERSION = 1

/// Thin bridge around the generated `PodcastApp` UniFFI object.
final class PodcastHandle: @unchecked Sendable {
    private nonisolated(unsafe) static var current: PodcastHandle?

    /// `PodcastApp` owns the single `NmpApp` and the app-domain
    /// `PodcastHandle`. `podcastHandle` below is a temporary borrowed token
    /// used only to map older Swift extension methods back to this generated
    /// UniFFI `PodcastApp` instance.
    let podcastApp: PodcastApp
    private var updateSink: KernelUpdateSink?
    /// Borrowed opaque handle owned by `PodcastApp`.
    var podcastHandle: UnsafeMutableRawPointer?
    private let projectionCache = ProjectionMergeCache()
    /// Retained generated UniFFI capability sink.
    var syncBridge: SyncCapabilityBridge?
    /// Retained generated UniFFI agent-ask timeout sink.
    var agentAskSink: KernelAgentAskSink?
    /// Fired (on the main actor) immediately after a shell-initiated FFI report
    /// (`nmp_app_podcast_audio_report` / `_download_report`) bumps the podcast
    /// `rev`. `KernelModel` wires this to a one-shot rev-gated pull so those
    /// changes reach the UI reactively — replacing the old 500ms snapshot poll.
    /// (Dispatched host-ops already arrive via the kernel push frame.)
    var onSnapshotMaybeChanged: (() -> Void)?

    /// Fired (on the main actor) for every download report, carrying the fresh
    /// `DownloadQueueSnapshot` (progress %, queue state) and whether the report
    /// changed *durable* library state. `KernelModel` wires this to update its
    /// live `downloadSnapshot` directly — progress ticks update only that
    /// (driving the row overlay) WITHOUT pulling/decoding the full library; only
    /// `durableChanged == true` (a completion/cancellation) triggers a full pull.
    /// This is the seam that keeps ~1 Hz progress off the global-`rev` hot path.
    var onDownloadReport: ((DownloadQueueSnapshot?, Bool) -> Void)?

    /// Fired (on the main actor) for every audio report, carrying the fresh
    /// `PlayerState` (live playhead / buffer / play state) and whether the
    /// report changed *structural* state. `KernelModel` wires this to update its
    /// live `nowPlaying` (scrubber, Dynamic Island, lock screen) directly —
    /// `Playing`/`BufferingProgress` ticks update only that WITHOUT
    /// pulling/decoding the full library; only `durableChanged == true`
    /// (play/pause/stop, track end, sleep-timer) triggers a full pull. This is
    /// the seam that keeps ~1 Hz playback ticks off the global-`rev` hot path.
    var onAudioReport: ((PlayerState?, Bool) -> Void)?
    /// Fired on the main actor when Rust completes an agent-ask lifecycle event
    /// asynchronously. Today that is the Rust-owned timeout expiry path.
    var onAgentAskEvent: ((KernelModel.AgentAskResponse) -> Void)?

    /// Buffered resolver for `PodcastApp.signEventForReturn` round-trips. The
    /// `signed_events` projection that carries each result is drain-once: the
    /// kernel clears it on the first emit tick that carries it. Because the
    /// correlation id is only known AFTER the synchronous FFI return, a slow
    /// `await` could miss that single frame. This registry closes the race by
    /// retaining every drained result keyed by id, so any future caller
    /// resolves via find-or-register regardless of thread timing (D13: signing
    /// is the kernel's job, the host never holds a private key).
    let signedEventsRegistry = SignedEventsRegistry()

    /// Buffered resolver for async-completing kernel actions. The
    /// `action_results` projection carries the settled result (e.g. a
    /// `BlobDescriptor` from `nmp.blossom.upload`) as a drained array in each
    /// push frame. `BlossomKernelUploader` awaits its correlation-id here.
    let actionResultsRegistry = ActionResultsRegistry()

    init() {
        let podcastApp = PodcastApp()
        self.podcastApp = podcastApp
        Self.current = self
        podcastApp.signerBrokerInit()
        Self.configureStoragePath(for: podcastApp)
        // ADR-0053 / NMP v0.8: make the full built-in projection consumption
        // intent explicit before `start`; podcast domain sidecars are
        // registered inside `PodcastApp`.
        podcastApp.consumeAllBuiltinProjections()
        registerPodcastProjection()
    }

    private static func configureStoragePath(for app: PodcastApp) {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        let directory = base.appendingPathComponent("NMP", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            app.setStoragePath(path: directory.path)
        } catch {
            kbLog.error(
                "failed to create NMP storage directory: \(error.localizedDescription, privacy: .public)")
        }
    }

    deinit {
        unregisterPodcastProjectionIfNeeded()
        podcastApp.setUpdateSink(sink: nil)
        podcastApp.setCapabilityCallback(sink: nil)
        podcastApp.setAgentAskSink(sink: nil)
        podcastApp.shutdown()
        if Self.current === self {
            Self.current = nil
        }
    }

    static func app(for handle: UnsafeMutableRawPointer?) -> PodcastApp? {
        guard let current, let handle, handle == current.podcastHandle else { return nil }
        return current.podcastApp
    }

    /// Wire the Rust update callback. `handler` runs on every snapshot frame;
    /// `onPanic` runs exactly once if/when the actor thread dies and the Rust
    /// supervisor emits an `{"t":"panic",...}` envelope (D7 actor-death contract).
    ///
    /// `decodeQueue`: `KernelUpdateSink.onUpdate(frame:)` — the UniFFI
    /// callback Rust invokes on every push frame — used to decode
    /// synchronously on whatever thread Rust called back on, which a
    /// main-thread `sample` caught landing on MainActor: during active
    /// library sync the actor emits a continuous stream of frames, each one
    /// running `decode_update_frame`/`decode_typed_projection_frame`
    /// in-line, pegging the main thread at 100%+ CPU for the whole sync
    /// (#755 follow-up — a sustained, ongoing freeze, not just a launch
    /// stall). The decode now runs on `decodeQueue` (callers pass
    /// `KernelModel.snapshotDecodeQueue`, the same serial queue already used
    /// for the full-library snapshot pull); `handler` still hops to
    /// MainActor itself to apply the already-decoded result.
    func listen(
        _ handler: @escaping (KernelUpdateResult) -> Void,
        onPanic: @escaping () -> Void = {},
        decodeQueue: DispatchQueue
    ) {
        let sink = KernelUpdateSink(
            handler: handler, onPanic: onPanic,
            signedEvents: signedEventsRegistry,
            actionResults: actionResultsRegistry,
            decodeQueue: decodeQueue,
            decodeFrame: { [weak self] frame in
                self?.podcastApp.decodeUpdateFrame(frame: frame)
            },
            decodeDomainFrames: { [weak self] frame in
                self?.decodeDomainFrames(frame: frame)
            })
        updateSink = sink
        podcastApp.setUpdateSink(sink: sink)
    }

    /// Actor-liveness probe (D7 pull-side, ADR-0028). Returns `true` when the
    /// Rust actor thread is still running, `false` when terminated.
    func isAlive() -> Bool {
        podcastApp.isAlive()
    }

    func start(visibleLimit: UInt32 = 80, emitHz: UInt32 = 4) {
        // Set the podcast library data directory here rather than at
        // registerPodcastProjection() time. `PodcastApp.setPodcastDataDir`
        // reads podcasts.json immediately; deferring the call to `start()`
        // ensures UITestSeeder.seedIfNeeded() (which runs in AppDelegate
        // didFinishLaunchingWithOptions, after PodcastHandle.init()) has
        // already written the fresh seed before the kernel opens the store.
        Self.configurePodcastDataDir(for: podcastApp)
        podcastApp.start(visibleLimit: visibleLimit, emitHz: emitHz)
    }

    func configure(visibleLimit: UInt32, emitHz: UInt32) {
        podcastApp.configure(visibleLimit: visibleLimit, emitHz: emitHz)
    }

    func stop() {
        podcastApp.stop()
    }

    func reset() {
        podcastApp.reset()
    }

    // ── T118 / G3 — iOS scenePhase → kernel lifecycle bridge ──────────────

    func lifecycleForeground() {
        podcastApp.lifecycleForeground()
    }

    func lifecycleBackground() {
        podcastApp.lifecycleBackground()
    }

    // ── Generic dispatch ──────────────────────────────────────────────────

    /// Dispatch a namespace-keyed action. Returns the synchronous dispatch
    /// result. D6: returns .failure for a null podcast handle.
    ///
    /// ADR-0064: routes through `PodcastApp.dispatchAction(envelope:)` with
    /// generated NMP action-builder bytes. Swift still serializes some
    /// app-owned JSON action bodies, but it no longer calls the UniFFI
    /// namespace/action JSON compatibility method.
    @discardableResult
    func dispatchAction(namespace: String, body: [String: Any]) -> DispatchResult {
        // Perf: dispatch is a synchronous FFI round-trip on the caller thread
        // (usually main). Time the whole serialize → FFI → parse path so a slow
        // action shows up as a main-thread cost in the Performance view.
        let dispatchStart = DispatchTime.now().uptimeNanoseconds
        defer {
            PerfMetrics.shared.record(
                .dispatchAction,
                micros: Int((DispatchTime.now().uptimeNanoseconds &- dispatchStart) / 1_000))
        }
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let jsonStr = String(data: data, encoding: .utf8)
        else {
            return .failure("failed to serialize action body")
        }
        let correlationId = Self.mintDispatchCorrelationId()
        let envelope: [UInt8]?
        if namespace == "nmp.blossom.upload" {
            envelope = KernelDispatchEnvelope.blossomUpload(body: body, correlationId: correlationId)
        } else {
            envelope = KernelDispatchEnvelope.podcast(
                namespace: namespace,
                json: jsonStr,
                correlationId: correlationId
            )
        }
        guard let envelope else {
            return .failure("no generated action builder for namespace \(namespace)")
        }
        return DispatchResult.from(outcome: podcastApp.dispatchAction(envelope: Data(envelope)))
    }

    private static func mintDispatchCorrelationId() -> String {
        "podcast-swift-\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""))"
    }

    private func decodeDomainFrames(frame: Data) -> PodcastDomainFrames? {
        guard let typedFrame = podcastApp.decodeTypedProjectionFrame(frame: frame) else {
            return nil
        }
        let envelopes = typedFrame.envelopes.map(TypedProjectionEnvelope.init)
        let result = projectionCache.merge(
            envelopes: envelopes,
            sessionId: typedFrame.sessionId,
            snapshotEpoch: typedFrame.snapshotEpoch
        )
        return PodcastDomainFrames.decode(from: result.mergedEnvelopes)
    }

    fileprivate static func decode(payload: String, domainFrames typedDomainFrames: PodcastDomainFrames) -> KernelUpdateResult? {
        let start = ContinuousClock.now
        let data = Data(payload.utf8)
        let decoder = KernelDecoding.makeDecoder()
        do {
            let envelope = try decoder.decode(SnapshotEnvelope.self, from: data)
            guard envelope.t == "snapshot" else {
                kbLog.error("unknown envelope tag=\(envelope.t) bytes=\(data.count)")
                return nil
            }
            var domainFrames = typedDomainFrames
            domainFrames.resolvedProfiles = PodcastDomainFrames.decodeResolvedProfiles(from: data)
            let nostrSearchSessions = NostrSearchProjection.decodeSessions(from: data)
            guard domainFrames.hasAnyDomain || !nostrSearchSessions.isEmpty else {
                kbLog.error(
                    "snapshot frame missing all podcast.* domain sidecars bytes=\(data.count)")
                return nil
            }
            // Identity is sourced from the identity domain sidecar when present,
            // otherwise derived from the playback domain (active_account may also
            // appear there on older kernels). Fails open to .empty.
            let identity = KernelIdentityProjection.from(domainFrames: domainFrames)
            // Mandatory NMP v0.1.0 surface (V-67): `store_open_failure` rides the
            // generic snapshot (sibling of `projections`). Read raw, mirroring the
            // identity decode — typed domain envelopes don't model this key.
            let storeOpenFailure = KernelUpdateResult.extractStoreOpenFailure(envelopePayload: data)
            let duration = start.duration(to: .now)
            kbLog.info(
                "decoded ok domains=\(domainFrames.presentDomainNames())")
            return KernelUpdateResult(
                domainFrames: domainFrames,
                identity: identity,
                storeOpenFailure: storeOpenFailure,
                nostrSearchSessions: nostrSearchSessions,
                payloadBytes: data.count,
                callbackReceivedAt: start,
                decodeMicros: duration.microseconds)
        } catch {
            kbLog.error(
                "envelope decode error: \(error.localizedDescription) bytes=\(data.count)")
            return nil
        }
    }
}

// ─── Snapshot envelope ────────────────────────────────────────────────────

private struct SnapshotEnvelope: Decodable {
    let t: String
}

// ─── UniFFI callback objects ──────────────────────────────────────────────

private final class KernelUpdateSink: PodcastUpdateSink, @unchecked Sendable {
    let handler: (KernelUpdateResult) -> Void
    let onPanic: () -> Void
    let signedEvents: SignedEventsRegistry
    let actionResults: ActionResultsRegistry
    let decodeQueue: DispatchQueue
    let decodeFrame: (Data) -> String?
    let decodeDomainFrames: (Data) -> PodcastDomainFrames?

    init(
        handler: @escaping (KernelUpdateResult) -> Void,
        onPanic: @escaping () -> Void,
        signedEvents: SignedEventsRegistry,
        actionResults: ActionResultsRegistry,
        decodeQueue: DispatchQueue,
        decodeFrame: @escaping (Data) -> String?,
        decodeDomainFrames: @escaping (Data) -> PodcastDomainFrames?
    ) {
        self.handler = handler
        self.onPanic = onPanic
        self.signedEvents = signedEvents
        self.actionResults = actionResults
        self.decodeQueue = decodeQueue
        self.decodeFrame = decodeFrame
        self.decodeDomainFrames = decodeDomainFrames
    }

    /// Rust invokes this UniFFI callback on every push frame, on whatever
    /// thread the actor's callback dispatch lands on — observed on
    /// MainActor via a main-thread `sample`. The decode work (JSON parse +
    /// typed-projection merge) is dispatched onto `decodeQueue` so a
    /// continuous stream of frames during active library sync can't peg the
    /// main thread; `handler` (built by `KernelModel`) still hops back to
    /// MainActor itself to apply the already-decoded result. `signedEvents`/
    /// `actionResults` are `@unchecked Sendable` with their own internal
    /// locking, safe to call from `decodeQueue`.
    func onUpdate(frame: Data) {
        guard !frame.isEmpty else { return }
        decodeQueue.async { [self] in
            let frameStart = DispatchTime.now().uptimeNanoseconds
            guard let payload = decodeFrame(frame) else { return }
            let payloadData = Data(payload.utf8)
            signedEvents.ingest(envelopePayload: payloadData)
            actionResults.ingest(envelopePayload: payloadData)
            if payload.contains("\"t\":\"panic\"") {
                kbLog.fault("NMP_ACTOR_PANIC detected bytes=\(frame.count)")
                onPanic()
                return
            }
            let domainFrames = decodeDomainFrames(frame) ?? PodcastDomainFrames()
            guard let result = PodcastHandle.decode(payload: payload, domainFrames: domainFrames) else { return }
            PerfMetrics.shared.record(
                .pushFrameDecode,
                micros: Int((DispatchTime.now().uptimeNanoseconds &- frameStart) / 1_000),
                bytes: frame.count)
            handler(result)
        }
    }
}
