import Foundation
import Observation
import WidgetKit
import os.log

// MARK: - Friend invite

/// Pre-filled data for an incoming friend invite deep-link.
/// Consumed by `AgentFriendsView` to open `AddFriendSheet` with values already typed in.
struct PendingFriendInvite: Equatable, Identifiable {
    /// Bech32-encoded public key of the person being added (full `npub1…` string).
    let npub: String
    /// Display name suggested by the invite link; the user can change it before adding.
    let name: String?

    /// Stable identity derived from the public key — two invites for the same key are the same.
    var id: String { npub }
}

/// Single source of truth. All mutations route through here so the `didSet`
/// observer can persist automatically. UI and agent both call the same methods.
@MainActor
@Observable
final class AppStateStore {

    nonisolated private static let logger = Logger.app("AppStateStore")

    // MARK: - Navigation

    /// Pending friend invite dispatched by a `podcastr://friend/add` deep-link.
    /// Consumed and cleared by `AgentFriendsView` on `.onChange` so it fires exactly once.
    var pendingFriendInvite: PendingFriendInvite?

    var state: AppState {
        didSet {
            persistence.save(state)
            SpotlightIndexer.reindex(state: state)
            // Notify WidgetKit so widgets refresh immediately on every state
            // mutation rather than waiting for the timeline poll.
            WidgetCenter.shared.reloadAllTimelines()
            // Push the current settings to iCloud KV store. The sync service
            // internally no-ops if an inbound merge is already in progress.
            iCloudSettingsSync.shared.push(state.settings)
        }
    }

    /// Storage backing this store. Production code uses `Persistence.shared`
    /// (the App Group suite); tests inject an instance over a unique
    /// in-memory suite so fixtures never leak into the real app.
    let persistence: Persistence

    /// Retained observer token for iCloud external-change notifications.
    private var iCloudObserver: NSObjectProtocol?

    /// Retained observer token for `UIApplication.didEnterBackgroundNotification`.
    /// On background, the position cache is flushed to disk so the user
    /// can force-quit + relaunch without losing playback progress.
    /// See `AppStateStore+PositionDebounce.swift` for the rationale.
    private var backgroundObserver: NSObjectProtocol?

    // MARK: - Position debounce
    //
    // Position updates from `PlaybackState.tickPersistence` arrive at 1 Hz.
    // Writing the entire ~8 MB JSON blob every second would be 480 MB/min of
    // disk I/O on the main actor — battery, NAND wear, and main-thread
    // responsiveness all suffer. We coalesce position updates through these
    // three fields and only mutate `state.episodes` (which would trigger the
    // expensive save) on a controlled cadence.
    //
    // See `AppStateStore+PositionDebounce.swift` for the full read/write
    // contract; these properties are declared here because they're stored
    // properties (extensions can't add stored state) and isolated to the
    // store's main actor.

    /// Cached playback positions waiting to be folded into `state.episodes`.
    /// Read-folded into `episode(id:)`/`inProgressEpisodes`/`recentEpisodes`
    /// so UI surfaces never see a stale position. Drained by
    /// `flushPendingPositions()`.
    var positionCache: [UUID: TimeInterval] = [:]

    /// Pending trailing-debounce flush task. Cancelled and re-armed on each
    /// `setEpisodePlaybackPosition` call so the deadline keeps moving while
    /// updates stream in (true trailing debounce).
    var positionFlushTask: Task<Void, Never>?

    /// Wall-clock time of the most recent position flush. Drives the
    /// max-interval cap: if continuous updates exceed
    /// `positionMaxInterval` since this timestamp, the next call writes
    /// eagerly so a crash never loses more than one cap-window of
    /// position.
    var lastPositionFlush: Date?

    init(persistence: Persistence = .shared) {
        self.persistence = persistence
        var loadedState: AppState
        do {
            loadedState = try persistence.load()
        } catch {
            Self.logger.error("Persistence.load failed: \(error, privacy: .public) — starting with empty state")
            loadedState = AppState()
        }
        Self.migrateLegacyOpenRouterSecretIfNeeded(in: &loadedState, persistence: persistence)
        // Start iCloud KV sync before assigning state so that the first
        // push (triggered by the `didSet` below) reflects the merged values.
        iCloudSettingsSync.shared.start(mergingInto: &loadedState.settings)
        self.state = loadedState
        // Bootstrap the live RAG stack so the SQLite vector store is opened
        // (and its file path logged) before any view tries to query it.
        // Hand `self` to the service so the briefing adapter and transcript
        // ingester can resolve episode/subscription metadata.
        RAGService.shared.attach(appStore: self)
        // Prune agent-activity entries older than 30 days so the persisted log
        // doesn't grow unboundedly across many months of use. This fires one
        // Persistence.save only when stale entries are actually found.
        pruneStaleActivityEntries()
        // Seed Spotlight with whatever was persisted before this launch — the
        // index can be wiped out independently of our app data (device reset,
        // reinstall, user clearing system search).
        SpotlightIndexer.reindex(state: loadedState)
        // Observe external iCloud changes so settings stay in sync while the
        // app is running on multiple devices simultaneously.
        iCloudObserver = NotificationCenter.default.addObserver(
            forName: iCloudSettingsSync.settingsDidChangeExternallyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyExternalSettingsChange()
            }
        }
        // Kick off the foreground subscription-refresh loop. The service
        // itself owns the polling task + lifecycle observers, so this call
        // is idempotent and we never have to clean up from here.
        SubscriptionRefreshService.shared.startPeriodicRefresh(store: self)
        // Subscribe to app-backgrounding so the position cache is flushed
        // to disk before iOS can suspend or kill the process. Token is
        // retained on `self` so the observer outlives the init call but
        // dies with the store. See `AppStateStore+PositionDebounce.swift`.
        backgroundObserver = registerBackgroundFlushObserver()
    }

    /// Pulls the latest iCloud values into `state.settings`.
    /// Called when `iCloudSettingsSync` reports an external change.
    private func applyExternalSettingsChange() {
        let sync = iCloudSettingsSync.shared
        sync.isApplyingRemoteChange = true
        defer { sync.isApplyingRemoteChange = false }
        var updated = state.settings
        sync.merge(from: NSUbiquitousKeyValueStore.default, into: &updated)
        guard updated != state.settings else { return }
        Self.logger.info("iCloudSettingsSync: applying remote settings update")
        // Assign directly (bypassing updateSettings) to avoid a redundant push.
        state.settings = updated
    }

    private static func migrateLegacyOpenRouterSecretIfNeeded(
        in state: inout AppState,
        persistence: Persistence
    ) {
        let legacyKey = state.settings.legacyOpenRouterAPIKey.trimmedOrEmpty
        guard !legacyKey.isEmpty else {
            state.settings.legacyOpenRouterAPIKey = nil
            return
        }

        do {
            try OpenRouterCredentialStore.saveAPIKey(legacyKey)
            state.settings.markOpenRouterManual()
        } catch {
            logger.error("Failed to migrate legacy OpenRouter key to keychain: \(error, privacy: .public)")
            state.settings.clearOpenRouterCredential()
        }
        persistence.save(state)
    }

    // MARK: - Settings

    func updateSettings(_ settings: Settings) {
        state.settings = settings
    }

    /// Wipes all user data while preserving API credentials and Nostr identity.
    func clearAllData() {
        // Drop any queued position writes — they would target episode IDs
        // about to disappear and could resurrect deleted records on the
        // next flush.
        positionFlushTask?.cancel()
        positionFlushTask = nil
        positionCache.removeAll()

        let preserved = state.settings
        state = AppState()
        state.settings = preserved
        persistence.save(state)
        SpotlightIndexer.clearAll()
    }

    deinit {
        // NotificationCenter retains observer tokens until they're removed,
        // even after the registering instance dies. Without this, the
        // closure would keep firing into a `nil` self (harmless but noisy)
        // and the test target would leak observers across runs.
        //
        // Swift 6 deinit is nonisolated; we can't touch the @MainActor
        // stored properties from here directly. The observer tokens and
        // Task we need to clean up are conceptually owned by the actor,
        // but `removeObserver` is thread-safe and `Task.cancel()` is
        // `Sendable`, so we can safely reach them via `assumeIsolated` —
        // by the time deinit runs, no other actor work can be racing
        // against us for `self`.
        MainActor.assumeIsolated {
            if let backgroundObserver {
                NotificationCenter.default.removeObserver(backgroundObserver)
            }
            if let iCloudObserver {
                NotificationCenter.default.removeObserver(iCloudObserver)
            }
            positionFlushTask?.cancel()
        }
    }
}
