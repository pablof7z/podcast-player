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
                    // Migrate any legacy ID-based marker and seed a fresh
                    // install silently so the first launch doesn't dump
                    // the entire changelog as "new."
                    WhatsNewService.migrateAndSeedIfNeeded()
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
}

/// Drives the What's New `.sheet(item:)`. Bundling the entries with the
/// trigger guarantees the sheet content closure receives them atomically
/// — see the wiring note above.
private struct WhatsNewPresentation: Identifiable {
    let id = UUID()
    let entries: [WhatsNewEntry]
}
