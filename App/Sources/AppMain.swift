import SwiftUI

/// The top-level entry point for the app. Sets up global environment objects
/// and wires the Nostr relay service to relevant settings changes.
@main
struct PodcastrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var store = AppStateStore()
    @State private var userIdentity = UserIdentityStore()
    @State private var relayService: NostrRelayService?

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
                .onChange(of: store.state.settings.nostrEnabled) { _, _ in relayService?.start() }
                .onChange(of: store.state.settings.nostrRelayURL) { _, _ in relayService?.start() }
                .onChange(of: store.state.settings.nostrPublicKeyHex) { _, _ in relayService?.start() }
        }
    }
}
