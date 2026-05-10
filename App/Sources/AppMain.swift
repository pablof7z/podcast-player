import SwiftUI

/// The top-level entry point for the app. Sets up global environment objects
/// and wires the Nostr relay service to relevant settings changes.
@main
struct PodcastrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var store = AppStateStore()
    @State private var userIdentity = UserIdentityStore.shared
    @State private var relayService: NostrRelayService?

    // MARK: - What's-new sheet wiring
    //
    // Evaluated once on cold launch (`.task` below). Stays here in
    // `AppMain.swift` rather than `RootView.swift` so the "what changed
    // since you last opened the app" check fires before any tab-level
    // view has a chance to short-circuit it.
    @State private var whatsNewEntries: [WhatsNewEntry] = []
    @State private var showWhatsNew = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(userIdentity)
                .task { userIdentity.start() }
                .task {
                    let service = NostrRelayService(store: store)
                    relayService = service
                    service.start()
                }
                .task {
                    // First launch with this feature seeds the marker
                    // silently (so the user is "caught up"); subsequent
                    // launches surface only entries newer than the marker.
                    WhatsNewService.seedMarkerIfNeeded()
                    let unseen = WhatsNewService.unseenEntries(
                        lastSeenID: WhatsNewService.lastSeenID
                    )
                    if !unseen.isEmpty {
                        whatsNewEntries = unseen
                        showWhatsNew = true
                    }
                }
                .sheet(isPresented: $showWhatsNew) {
                    WhatsNewSheet(entries: whatsNewEntries)
                }
                .onChange(of: store.state.settings.nostrEnabled) { _, _ in relayService?.start() }
                .onChange(of: store.state.settings.nostrRelayURL) { _, _ in relayService?.start() }
                .onChange(of: store.state.settings.nostrPublicKeyHex) { _, _ in relayService?.start() }
        }
    }
}
