import SwiftUI

/// The top-level entry point for the app. Sets up global environment objects
/// and wires the Nostr relay service to relevant settings changes.
@main
struct PodcastrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var store = AppStateStore()
    @State private var userIdentity = UserIdentityStore.shared
    @State private var relayService: NostrRelayService?
    /// Single global owner-consultation coordinator. Lives here (not on
    /// `AgentChatSession`) so an inbound peer-agent reply flowing through
    /// `AgentRelayBridge` can pop the same sheet even when the user is on
    /// Home / Library / Wiki — i.e. while no chat session exists. Mounted
    /// on `RootView` via `agentAskPresenter(coordinator:)`.
    @State private var askCoordinator = AgentAskCoordinator()
    /// Phase 2 relay system. Coexists with `NostrRelayService` until Phase 5
    /// migrates callers. `relayConfigStore` is constructed eagerly on launch;
    /// `relayPool` is constructed once the user's signer is available, which
    /// can happen synchronously (local-key path) or asynchronously (NIP-46
    /// resume path) — `bootstrapRelaysIfReady()` is idempotent per-pubkey.
    @State private var relayConfigStore: RelayConfigStore?
    @State private var relayPool: RelayPool?
    @State private var outboxRouter: OutboxRouter?
    @State private var bootstrappedPubkey: String?
    @State private var bootstrapTask: Task<Void, Never>?

    // MARK: - What's-new sheet wiring
    //
    // Evaluated once on cold launch (`.task` below). Stays here in
    // `AppMain.swift` rather than `RootView.swift` so the "what changed
    // since you last opened the app" check fires before any tab-level
    // view has a chance to short-circuit it.
    //
    // Single optional `@State` + `.sheet(item:)` rather than the more
    // common pair of `entries: [...]` and `isPresented: Bool`. The
    // `OnboardingView` fullScreenCover sits on top of RootView during
    // first launch, and SwiftUI re-evaluates the queued sheet's content
    // closure once the cover dismisses. With the two-state pattern the
    // closure was reading a stale `entries = []` from across that
    // render boundary, so the sheet rendered empty. `.sheet(item:)`
    // passes the entries through the trigger itself, eliminating the
    // race.
    @State private var whatsNewPresentation: WhatsNewPresentation?

    var body: some Scene {
        WindowGroup {
            RootView(relayService: relayService)
                .environment(store)
                .environment(userIdentity)
                .environment(askCoordinator)
                .task { userIdentity.start() }
                .task { CarPlayController.shared.attach(store: store) }
                .task {
                    let service = NostrRelayService(store: store, askCoordinator: askCoordinator)
                    relayService = service
                    service.start()
                }
                .task {
                    let configStore = RelayConfigStore(appStateStore: store)
                    relayConfigStore = configStore
                    bootstrapRelaysIfReady()
                }
                .onChange(of: userIdentity.publicKeyHex) { _, _ in
                    bootstrapRelaysIfReady()
                }
                // NIP-46 resume sets `publicKeyHex` synchronously but `signer`
                // asynchronously inside `resumeRemote`. Observe `remoteSignerState`
                // too so the bootstrap fires once the bunker connect completes.
                .onChange(of: userIdentity.remoteSignerState) { _, _ in
                    bootstrapRelaysIfReady()
                }
                .task {
                    // Seed a fresh install silently so the first launch
                    // doesn't dump the entire changelog as "new."
                    WhatsNewService.seedIfNeeded()
                    let unseen = WhatsNewService.unseenEntries(
                        lastSeenAt: WhatsNewService.lastSeenAt
                    )
                    if !unseen.isEmpty {
                        whatsNewPresentation = WhatsNewPresentation(entries: unseen)
                    }
                }
                .sheet(item: $whatsNewPresentation) { presentation in
                    WhatsNewSheet(entries: presentation.entries)
                }
                .onChange(of: store.state.settings.nostrEnabled) { _, _ in relayService?.start() }
                .onChange(of: store.state.settings.nostrRelayURL) { _, _ in relayService?.start() }
                .onChange(of: store.state.settings.nostrPublicKeyHex) { _, _ in relayService?.start() }
                .onChange(of: store.state.settings.nostrProfileName) { _, _ in relayService?.republishProfile() }
                .onChange(of: store.state.settings.nostrProfileAbout) { _, _ in relayService?.republishProfile() }
                .onChange(of: store.state.settings.nostrProfilePicture) { _, _ in relayService?.republishProfile() }
        }
    }

    /// Builds a `RelayPool` against the current signer and runs the bootstrap
    /// sequence. Idempotent per-pubkey: handles both the local-key path
    /// (signer ready synchronously inside `userIdentity.start()`) and the
    /// NIP-46 path (signer ready after the bunker handshake completes).
    @MainActor
    private func bootstrapRelaysIfReady() {
        guard let pubkey = userIdentity.publicKeyHex,
              let signer = userIdentity.signer,
              let configStore = relayConfigStore else {
            // Sign-out (or signer not yet available after a sign-out): tear down
            // if a previous session is active. Without this the old user's
            // WebSockets would keep running until process exit.
            if bootstrappedPubkey != nil {
                tearDownRelaySession()
            }
            return
        }

        // Same pubkey already bootstrapped — re-entrancy from a redundant
        // `remoteSignerState` change must not replace the live pool, which
        // would leak the previous pool's receive tasks.
        guard bootstrappedPubkey != pubkey else { return }

        // Switching identities: tear down the previous session before
        // spinning up a new pool.
        if bootstrappedPubkey != nil {
            tearDownRelaySession()
        }

        bootstrappedPubkey = pubkey
        let pool = RelayPool(signer: signer)
        relayPool = pool
        let router = OutboxRouter()
        outboxRouter = router
        configStore.attachRelayPool(pool)
        // Snapshot follow pubkeys at bootstrap time. The outbox loop reuses
        // this list for its entire lifetime; an in-flight identity switch
        // cancels the bootstrap task before the next iteration runs, so a
        // stale list never leaks into the next user's session.
        let followPubkeys = store.state.friends.map(\.identifier)
        bootstrapTask = Task {
            await RelayBootstrapService.bootstrap(
                configStore: configStore,
                pool: pool,
                signer: signer,
                userPubkey: pubkey,
                outboxRouter: router,
                followPubkeys: followPubkeys
            )
        }
    }

    /// Cancel the in-flight bootstrap (so a stale fetch can't mutate the
    /// config store after an identity switch) and tear down the live pool.
    @MainActor
    private func tearDownRelaySession() {
        bootstrapTask?.cancel()
        bootstrapTask = nil
        if let router = outboxRouter, let pool = relayPool {
            router.reset(pool: pool)
        }
        outboxRouter = nil
        relayPool?.disconnectAll()
        relayPool = nil
        relayConfigStore?.detachRelayPool()
        bootstrappedPubkey = nil
    }
}

/// Drives the What's New `.sheet(item:)`. Bundling the entries with the
/// trigger guarantees the sheet content closure receives them atomically
/// — see the wiring note above.
private struct WhatsNewPresentation: Identifiable {
    let id = UUID()
    let entries: [WhatsNewEntry]
}
