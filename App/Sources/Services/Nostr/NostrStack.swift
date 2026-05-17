import Foundation
@preconcurrency import NDKSwiftCore
import os.log

/// Single owner of the app's `NDK` instance. Everything that talks to Nostr
/// (profile fetcher, thread fetcher, podcast discovery, comment service,
/// event publisher, agent responder, relay service) borrows the same
/// `ndk` from here.
///
/// **Always-available NDK:** the instance is held for the lifetime of the
/// process, even when `nostrEnabled == false` and no relay is configured.
/// Signing (via `NDKEventBuilder.build(signer:)`) needs an NDK to read
/// client-tag config and parse references, but does not need a live relay
/// connection. Toggling Nostr enabled/disabled only switches the relay
/// pool's connection state via `connect()` / `disconnect()`.
///
/// Reactivity model: callers observe `relaysConnected` (an `@Observable`
/// property) to know when subscriptions should fire. They do not poll.
/// Inbound events come through `ndk.subscribe(...).events` (an
/// `AsyncStream`); state changes come through NDKSwift's Combine publishers.
@MainActor
@Observable
final class NostrStack {
    nonisolated private static let logger = Logger.app("NostrStack")

    /// App-wide singleton. Wired by `AppMain.task` once `AppStateStore`
    /// exists. Every Nostr service borrows `NostrStack.shared.ndk`.
    static let shared = NostrStack()

    /// The shared `NDK` instance. `nil` only until `bind(store:)` completes
    /// once at app launch; thereafter held for the process lifetime.
    /// Safe to use for signing even when no relay is connected.
    private(set) var ndk: NDK?

    /// `true` when the relay pool is connected and subscriptions can fire.
    /// Read by services that gate on live relay availability (e.g. the
    /// inbox / discovery / profile fetcher); signing-only callers should
    /// not consult this.
    private(set) var relaysConnected: Bool = false

    /// URL of the currently-connected user-configured relay, or `nil` when
    /// disconnected. Used to detect whether a settings change needs a relay
    /// swap. Discovery relays (Primal) are always added alongside this one.
    private(set) var connectedRelayURL: String?

    /// Fixed relay added on every connect for broad NIP-F4 discovery coverage.
    private static let discoveryRelay = "wss://relay.primal.net"

    private var store: AppStateStore?
    private var cache: NDKNostrDBCache?

    private init() {}

    /// Wires the singleton to the live state store and constructs the
    /// always-available `NDK` instance. Called from `AppMain` once at
    /// launch; safe to call repeatedly (idempotent).
    func bind(store: AppStateStore) async {
        if self.store == nil { self.store = store }
        if ndk != nil { return }

        let cache: NDKNostrDBCache
        do {
            cache = try await NDKNostrDBCache(path: cacheDirectoryPath())
        } catch {
            Self.logger.error("bind: cache init failed — \(error, privacy: .public); proceeding without cache")
            return
        }
        self.cache = cache
        // Build NDK with no initial relays. `start()` adds the configured
        // relay once Nostr is enabled. Building empty avoids racing
        // discovery against an unset signer.
        self.ndk = NDK(relayURLs: [], cache: cache)
        Self.logger.notice("bind: NDK constructed (offline, signing-ready)")
    }

    /// Reads the current Nostr settings and (re)connects the relay pool.
    /// Idempotent — calling twice with the same settings is a no-op.
    /// Does **not** rebuild the NDK instance; signing remains available
    /// throughout.
    func start() async {
        guard let store else {
            Self.logger.error("start: not bound to an AppStateStore yet")
            return
        }
        guard let ndk else {
            Self.logger.error("start: NDK not yet constructed; bind() must complete first")
            return
        }
        let settings = store.state.settings
        guard settings.nostrEnabled, !settings.nostrRelayURL.isEmpty else {
            await stop()
            return
        }
        // Relay URL unchanged + already connected → nothing to do.
        if relaysConnected, connectedRelayURL == settings.nostrRelayURL {
            return
        }
        // Relay URL changed: disconnect, swap relay, reconnect. We rebuild
        // the relay set rather than mutating in place so subscribers see a
        // clean disconnect → connect transition.
        if relaysConnected {
            await ndk.disconnect()
            relaysConnected = false
        }
        _ = await ndk.addRelay(settings.nostrRelayURL, reason: "user-configured relay")
        _ = await ndk.addRelay(Self.discoveryRelay, reason: "discovery relay")
        await ndk.connect()
        relaysConnected = true
        connectedRelayURL = settings.nostrRelayURL
        Self.logger.notice("start: NDK connected to \(settings.nostrRelayURL, privacy: .public) + \(Self.discoveryRelay, privacy: .public)")
    }

    /// Disconnect the relay pool. The NDK instance itself stays alive so
    /// signing continues to work.
    func stop() async {
        guard let ndk, relaysConnected else { return }
        await ndk.disconnect()
        relaysConnected = false
        connectedRelayURL = nil
        Self.logger.notice("stop: NDK relays disconnected")
    }

    /// On-disk path for `NDKNostrDBCache`. Lives in the app's Caches
    /// directory — re-creatable, not user data, evictable by the OS.
    private func cacheDirectoryPath() -> String {
        let urls = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = (urls.first ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("nostr-ndk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ndk.db").path
    }
}
