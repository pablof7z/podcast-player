import Foundation
import os.log

// MARK: - iCloudSyncCapability — `pcst.icloud_sync.capability`
//
// iOS half of the iCloud-settings-sync surface (feature #52). Mirrors a
// curated subset of `podcast.settings` into `NSUbiquitousKeyValueStore` so
// playback speed, skip intervals, and the ad-skip toggle roam across the
// user's devices and survive a reinstall.
//
// PASSIVE SHAPE — like `PlatformCapability` / `SpotlightCapability` there
// is no request/response capability socket here. The capability is driven
// by (a) `NSUbiquitousKeyValueStoreDidChangeExternallyNotification` for
// inbound pulls and (b) the reactive `KernelModel.applyPodcastUpdate`
// path (which calls `applySettingsSnapshot` on every accepted frame) for
// outbound writes. It is therefore **not** routed through
// `PodcastCapabilities.handleJSON(_:)`.
//
// Doctrine:
//   D6 — failures never throw. A missing entitlement, an unreachable iCloud
//        account, or a kernel-action rejection all degrade silently. The
//        inbound path uses `KernelModel.dispatchSilent` so a not-yet-wired
//        `podcast.settings.*` action does not surface as a user-visible
//        toast.
//   D7 — iOS executes; Rust decides. The cloud value is dispatched as an
//        action; the kernel may clamp, reject, or transform it before
//        emitting the next snapshot. We then read the next snapshot and
//        only write back if the kernel's authoritative value differs from
//        cloud (the `lastWritten` diff cache in `applySettingsSnapshot`).

/// `NSUbiquitousKeyValueStore` mirror for the podcast app's portable
/// settings. Single instance, owned by `PodcastCapabilities`. A weak
/// reference to `KernelModel` is the dispatch surface for inbound changes;
/// the model holds this capability strongly so the weak handle stays valid
/// for the lifetime of the app.
@MainActor
final class iCloudSyncCapability {

    // MARK: - Constants

    /// Capability namespace. Reserved for future request/response wiring;
    /// today this capability is purely tick-driven.
    static let namespace = "pcst.icloud_sync.capability"

    /// Key namespace for `NSUbiquitousKeyValueStore`. Kept short — the
    /// store has a 1024-byte per-key budget and the four scalar values fit
    /// comfortably with these names.
    enum Key {
        static let speed             = "pcst.speed"
        static let skipForwardSecs   = "pcst.skip_forward_secs"
        static let skipBackwardSecs  = "pcst.skip_backward_secs"
        static let autoSkipAds       = "pcst.auto_skip_ads"
        static let autoDeleteDownloadsAfterPlayed = "pcst.auto_delete_downloads_after_played"
        static let agentInitialModel = "pcst.agent_initial_model"
        static let agentInitialModelName = "pcst.agent_initial_model_name"
        static let agentThinkingModel = "pcst.agent_thinking_model"
        static let agentThinkingModelName = "pcst.agent_thinking_model_name"
        static let memoryCompilationModel = "pcst.memory_compilation_model"
        static let memoryCompilationModelName = "pcst.memory_compilation_model_name"
        static let categorizationModel = "pcst.categorization_model"
        static let categorizationModelName = "pcst.categorization_model_name"
        static let chapterCompilationModel = "pcst.chapter_compilation_model"
        static let chapterCompilationModelName = "pcst.chapter_compilation_model_name"
        static let embeddingsModel = "pcst.embeddings_model"
        static let embeddingsModelName = "pcst.embeddings_model_name"
        static let imageGenerationModel = "pcst.image_generation_model"
        static let imageGenerationModelName = "pcst.image_generation_model_name"
        static let rerankerEnabled = "pcst.reranker_enabled"
        static let ollamaChatUrl = "pcst.ollama_chat_url"
        static let sttProvider = "pcst.stt_provider"
        static let openRouterWhisperModel = "pcst.open_router_whisper_model"
        static let assemblyAiSttModel = "pcst.assembly_ai_stt_model"
        static let elevenLabsSttModel = "pcst.eleven_labs_stt_model"
        static let elevenLabsTtsModel = "pcst.eleven_labs_tts_model"
        static let elevenLabsVoiceId = "pcst.eleven_labs_voice_id"
        static let elevenLabsVoiceName = "pcst.eleven_labs_voice_name"
        static let blossomServerUrl = "pcst.blossom_server_url"
        static let youtubeExtractorUrl = "pcst.youtube_extractor_url"
        static let autoMarkPlayedAtEnd = "pcst.auto_mark_played_at_end"
        static let autoPlayNext = "pcst.auto_play_next"
        static let headphoneDoubleTapAction = "pcst.headphone_double_tap_action"
        static let headphoneTripleTapAction = "pcst.headphone_triple_tap_action"
        static let autoIngestPublisherTranscripts = "pcst.auto_ingest_publisher_transcripts"
        static let autoFallbackToScribe = "pcst.auto_fallback_to_scribe"
        static let notifyOnNewEpisodes = "pcst.notify_on_new_episodes"
        static let nostrRelayUrl = "pcst.nostr_relay_url"
        static let nostrProfileName = "pcst.nostr_profile_name"
        static let nostrProfileAbout = "pcst.nostr_profile_about"
        static let nostrProfilePicture = "pcst.nostr_profile_picture"

        /// Every key this capability owns.
        static let all: Set<String> = [
            speed, skipForwardSecs, skipBackwardSecs, autoSkipAds,
            autoDeleteDownloadsAfterPlayed,
            agentInitialModel, agentInitialModelName, agentThinkingModel, agentThinkingModelName,
            memoryCompilationModel, memoryCompilationModelName,
            categorizationModel, categorizationModelName, chapterCompilationModel, chapterCompilationModelName,
            embeddingsModel, embeddingsModelName, imageGenerationModel, imageGenerationModelName,
            rerankerEnabled, ollamaChatUrl, sttProvider, openRouterWhisperModel,
            assemblyAiSttModel, elevenLabsSttModel, elevenLabsTtsModel, elevenLabsVoiceId, elevenLabsVoiceName,
            blossomServerUrl, youtubeExtractorUrl, autoMarkPlayedAtEnd, autoPlayNext,
            headphoneDoubleTapAction, headphoneTripleTapAction,
            autoIngestPublisherTranscripts, autoFallbackToScribe, notifyOnNewEpisodes,
            nostrRelayUrl, nostrProfileName, nostrProfileAbout, nostrProfilePicture,
        ]
    }

    // MARK: - State

    private static let logger = Logger(subsystem: "io.f7z.podcast", category: "iCloudSync")

    // Widened from `private let` to `let` (internal) so extension files
    // (iCloudSyncCapability+ApplySnapshot.swift and
    // iCloudSyncCapability+CloudDispatch.swift) can access the store.
    let kvs: NSUbiquitousKeyValueStore

    /// Dispatch sink. Weak so the capability does not extend the model's
    /// lifetime — the model owns the capability, not the other way round.
    weak var kernel: KernelModel?

    /// Reference to the app state store for echo suppression. Weak so the
    /// capability does not extend the store's lifetime.
    weak var appStore: AppStateStore?

    /// Retained observer token. Cleared in `stop()` so the notification
    /// centre does not call back into a stopped capability.
    private var changeObserver: NSObjectProtocol?

    /// Snapshot of the last value we wrote to (or read from) iCloud for
    /// each key. Used by `applySettingsSnapshot(_:)` to detect deltas so
    /// we only write when the value actually changed.
    // Widened from `private(set) var` to `var` (internal) so extension
    // files can both read and write the diff cache.
    var lastWritten: [String: AnyHashable] = [:]

    /// Echo-suppression flag. Set while applying an inbound iCloud change
    /// so the outbound writer does not immediately re-emit the same value.
    // Widened from `private(set) var` to `var` (internal) so extension
    // files can both read and set this flag.
    var isApplyingRemoteChange: Bool = false

    // Widened from `private var` to `var` (internal) so
    // applySettingsSnapshot (in its extension file) can check the guard.
    var started: Bool = false

    // MARK: - Init

    init(kvs: NSUbiquitousKeyValueStore = .default) {
        self.kvs = kvs
    }

    // MARK: - Lifecycle

    /// Register for change notifications, kick off an initial KVS pull,
    /// and dispatch any non-default cloud values into the kernel. Safe to
    /// call multiple times — subsequent calls are no-ops.
    func start(kernel: KernelModel) {
        guard !started else { return }
        started = true
        self.kernel = kernel

        // Subscribe before the synchronize() — there is no race window in
        // which an external change could fire before we are listening.
        // Extract the changed-keys list inside the (non-Sendable)
        // notification closure and hop just the `[String]` across the
        // `@MainActor` boundary so Swift 6 doesn't flag the notification
        // capture as a data race.
        changeObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs,
            queue: .main
        ) { [weak self] notification in
            let changed = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey]
                as? [String] ?? []
            MainActor.assumeIsolated {
                self?.handleExternalChange(changedKeys: changed)
            }
        }

        kvs.synchronize()
        // For --UITestSeed launches (fresh seed and relaunch-persistence tests),
        // skip the initial KV→kernel dispatch. A stale pcst.speed value (e.g.
        // 1.5 from a prior testPlaybackSpeedPersists run) persists in the local
        // NSUbiquitousKeyValueStore SQLite cache between app launches; kvs.synchronize()
        // reads it back into memory AFTER UITestSeeder's removeObject calls, so the
        // in-memory deletions are overwritten before dispatchKeysFromCloud fires.
        // Fresh seeds carry their own default_playback_rate in podcasts.json;
        // relaunch persistence tests prove the kernel reads from podcasts.json
        // (not from KV). Skipping for all --UITestSeed variants keeps both paths clean.
        if !CommandLine.arguments.contains("--UITestSeed") {
            dispatchKeysFromCloud(Array(Key.all))
        }
        Self.logger.info("iCloudSyncCapability started")
    }

    /// Idempotent. Tears down the change observer and clears the dispatch
    /// handle. Does **not** clear `NSUbiquitousKeyValueStore` — those
    /// values live in the user's iCloud account.
    func stop() {
        started = false
        if let observer = changeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        changeObserver = nil
        kernel = nil
        lastWritten = [:]
        isApplyingRemoteChange = false
        appStore?.isApplyingRemoteChange = false
    }

    var isStarted: Bool { started }

    // MARK: - Inbound — iCloud → snapshot

    /// Handle a single
    /// `NSUbiquitousKeyValueStoreDidChangeExternallyNotification`. Takes
    /// the changed-keys list (extracted on the producing side so the hop
    /// across the `@MainActor` boundary stays Sendable) and dispatches
    /// the matching `podcast.settings.*` action for each tracked key.
    ///
    /// Internal so the test suite can drive this path directly without
    /// having to fire an actual KVS notification.
    func handleExternalChange(changedKeys: [String]) {
        let tracked = changedKeys.filter { Key.all.contains($0) }
        guard !tracked.isEmpty else { return }
        Self.logger.info("KVS external change: \(tracked.joined(separator: ","), privacy: .public)")
        dispatchKeysFromCloud(tracked)
    }
}

// `SettingsKVSnapshot` (the value the snapshot bridge produces) and
// the `from(podcastUpdate:)` bridge live in
// `iCloudSyncCapability+Snapshot.swift`.
