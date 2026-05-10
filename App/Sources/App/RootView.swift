import CoreSpotlight
import SwiftUI

/// The tabs available at the root navigation level.
///
/// Settings is reachable via a top-right toolbar button on every tab rather
/// than as a tab entry. The Player lives behind a persistent mini-bar that
/// expands into `PlayerView` on tap.
enum RootTab: String, CaseIterable {
    case home = "Home"
    case library = "Library"
    case search = "Search"
    case wiki = "Wiki"
    case ask = "Ask"

    var icon: String {
        switch self {
        case .home:    "house.fill"
        case .library: "books.vertical.fill"
        case .search:  "magnifyingglass"
        case .wiki:    "book.closed.fill"
        case .ask:     "bubble.left.and.bubble.right.fill"
        }
    }
}

/// The root view of the app. Hosts the main tab bar, the feedback shake gesture,
/// onboarding gate, and deep-link routing.
struct RootView: View {
    @Environment(AppStateStore.self) private var store
    @State private var selectedTab: RootTab = .home
    @State private var feedbackWorkflow = FeedbackWorkflow()
    @State private var showFeedback = false
    @State private var showSettings = false
    /// Sparkles toolbar shortcut presents the agent chat as a dismissible
    /// sheet — distinct from the dedicated Ask tab.
    @State private var showAgentChat = false
    @State private var lastShakeTime: Date = .distantPast
    /// Drives a Spotlight-continuation sheet for a note or memory.
    @State private var spotlightSheet: SpotlightIndexer.DeepLink?
    /// Drives the persistent mini-player and full Now Playing view. Wraps the
    /// real `AudioEngine`; persistence callbacks are wired in `.onAppear` so
    /// the wrapper stays independent of `AppStateStore`'s type.
    @State private var playbackState = PlaybackState()
    @State private var showFullPlayer = false
    /// Shared namespace for matched-geometry between mini-bar and full player.
    @Namespace private var playerNamespace

    var body: some View {
        tabBar
            .environment(playbackState)
            .onAppear {
                playbackState.onPersistPosition = { [store] id, position in
                    store.setEpisodePlaybackPosition(id, position: position)
                }
                playbackState.onEpisodeFinished = { [store, playbackState] id in
                    store.markEpisodePlayed(id)
                    // Auto-advance to the next queue entry when the user
                    // hasn't opted out, and only when the sleep timer
                    // isn't waiting on this exact episode-end as its stop
                    // signal — auto-playing through that defeats the
                    // whole point of `endOfEpisode` mode.
                    let endOfEpisodeArmed: Bool
                    switch playbackState.engine.sleepTimer.phase {
                    case .armedEndOfEpisode, .fired:
                        endOfEpisodeArmed = true
                    default:
                        endOfEpisodeArmed = false
                    }
                    guard store.state.settings.autoPlayNext, !endOfEpisodeArmed else { return }
                    playbackState.playNext { store.episode(id: $0) }
                }
                // Drain the position-debounce cache on pause / episode
                // change / natural end-without-auto-mark. The store also
                // flushes on `UIApplication.didEnterBackgroundNotification`
                // independently — this closure covers the in-app
                // transitions the store can't observe.
                playbackState.onFlushPositions = { [store] in
                    store.flushPendingPositions()
                }
                // Cold-launch quick-action routing: AppDelegate stashed the
                // shortcut URL during didFinishLaunchingWithOptions; consume
                // it now and clear so subsequent re-appears don't re-route.
                if let delegate = UIApplication.shared.delegate as? AppDelegate,
                   let url = delegate.pendingShortcutURL {
                    delegate.pendingShortcutURL = nil
                    handleDeepLink(url)
                }
                playbackState.autoMarkPlayedOnFinish = store.state.settings.autoMarkPlayedAtEnd
                playbackState.applyPreferences(from: store.state.settings)
                playbackState.resolveShowName = { [store] episode in
                    store.subscription(id: episode.subscriptionID)?.title ?? ""
                }
                playbackState.resolveShowImage = { [store] episode in
                    store.subscription(id: episode.subscriptionID)?.imageURL
                }
                // Lock-screen / Control Center enrichment. The engine reads
                // these on every Now Playing publish so the lock screen
                // shows show name + active chapter title, not just episode
                // title. Each defaults to no-op so the engine works in
                // isolation; we wire them here so the live store is the
                // source of truth (chapters can hydrate post-playback).
                playbackState.engine.resolveShowName = { [store] episode in
                    store.subscription(id: episode.subscriptionID)?.title
                }
                playbackState.engine.resolveActiveChapterTitle = { [store] episode, playhead in
                    let live = store.episode(id: episode.id) ?? episode
                    let navigable = live.chapters?.filter(\.includeInTableOfContents) ?? []
                    return navigable.active(at: playhead)?.title
                }
                playbackState.engine.resolveArtworkURL = { [store] episode, playhead in
                    // Mirror the in-app hero priority: chapter image →
                    // episode <itunes:image> → show cover. Reads from the
                    // live store so chapters hydrated post-playback drive
                    // the lock-screen artwork swap.
                    let live = store.episode(id: episode.id) ?? episode
                    let navigable = live.chapters?.filter(\.includeInTableOfContents) ?? []
                    if let chapterURL = navigable.active(at: playhead)?.imageURL {
                        return chapterURL
                    }
                    return live.imageURL
                        ?? store.subscription(id: live.subscriptionID)?.imageURL
                }
            }
            // Re-push preferences whenever the user edits Settings so the
            // skip intervals update on the lock screen and the auto-mark
            // toggle takes effect mid-session.
            .onChange(of: store.state.settings) { _, new in
                playbackState.autoMarkPlayedOnFinish = new.autoMarkPlayedAtEnd
                playbackState.applyPreferences(from: new)
            }
            .sheet(isPresented: $showFullPlayer) {
                PlayerView(
                    state: playbackState,
                    glassNamespace: playerNamespace
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.disabled)
            }
            .onShake { handleShake() }
            .sheet(isPresented: $showFeedback) {
                FeedbackView(workflow: feedbackWorkflow)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
            .sheet(isPresented: $showAgentChat) {
                NavigationStack {
                    AgentChatView()
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Done") {
                                    Haptics.selection()
                                    showAgentChat = false
                                }
                            }
                        }
                }
                .environment(playbackState)
            }
            .sheet(item: Binding(
                get: { spotlightSheet.map(IdentifiedSpotlightLink.init) },
                set: { spotlightSheet = $0?.link }
            )) { identified in
                NavigationStack {
                    spotlightDetailView(for: identified.link)
                }
            }
            .fullScreenCover(
                isPresented: .init(
                    get: { feedbackWorkflow.isAnnotationVisible },
                    set: { if !$0 { feedbackWorkflow.phase = .composing } }
                )
            ) {
                ScreenshotAnnotationView(workflow: feedbackWorkflow)
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { !store.state.settings.hasCompletedOnboarding },
                    set: { _ in }
                )
            ) {
                OnboardingView()
            }
            .onOpenURL { handleDeepLink($0) }
            .onReceive(
                NotificationCenter.default.publisher(for: AppDelegate.shortcutURLNotification)
            ) { note in
                if let url = note.object as? URL { handleDeepLink(url) }
            }
            .onContinueUserActivity(CSSearchableItemActionType, perform: handleSpotlight)
    }

    @ViewBuilder
    private var tabBar: some View {
        let base = TabView(selection: $selectedTab) {
            ForEach(RootTab.allCases, id: \.self) { tab in
                tabContent(for: tab)
                    .tabItem { Label(tab.rawValue, systemImage: tab.icon) }
                    .tag(tab)
            }
        }
        // iOS 26: tab bar collapses to a compact pill on scroll-down. The
        // bottom accessory below adapts to `.inline` placement and slots
        // between the active-tab capsule and the trailing controls — same
        // pattern Apple Music uses for its mini-player.
        .tabBarMinimizeBehavior(.onScrollDown)

        // The accessory modifier itself reserves vertical space when applied,
        // even if its closure returns EmptyView — so apply it only while an
        // episode is loaded. Otherwise an empty bar shows above the tabs.
        if playbackState.episode != nil {
            base.tabViewBottomAccessory {
                MiniPlayerView(
                    state: playbackState,
                    onTap: { showFullPlayer = true },
                    glassNamespace: playerNamespace
                )
            }
        } else {
            base
        }
    }

    @ViewBuilder
    private func tabContent(for tab: RootTab) -> some View {
        switch tab {
        case .home:
            NavigationStack { HomeView().toolbar { sharedToolbar(showAgent: true) } }
        case .library:
            NavigationStack {
                LibraryView(onOpenSearch: { selectedTab = .search })
                    .toolbar { sharedToolbar(showAgent: true) }
            }
        case .search:
            NavigationStack { PodcastSearchView().toolbar { sharedToolbar(showAgent: true) } }
        case .wiki:
            NavigationStack { WikiView().toolbar { sharedToolbar(showAgent: true) } }
        case .ask:
            // Ask tab IS the agent — no need for a redundant agent shortcut here.
            NavigationStack { AskAgentView().toolbar { sharedToolbar(showAgent: false) } }
        }
    }

    /// Top-right toolbar shared across tabs:
    ///   • Sparkles — selects the Ask tab (the agent surface). Hidden on Ask itself.
    ///   • Gear — presents the Settings sheet.
    @ToolbarContentBuilder
    private func sharedToolbar(showAgent: Bool) -> some ToolbarContent {
        if showAgent {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.selection()
                    showAgentChat = true
                } label: {
                    Image(systemName: "sparkles")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Open Agent")
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Haptics.selection()
                showSettings = true
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Settings")
            .keyboardShortcut(",", modifiers: .command)
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let link = DeepLinkHandler.resolve(url) else { return }
        switch link {
        case .settings:
            showSettings = true
        case .feedback:
            showFeedback = true
        case .agent:
            selectedTab = .ask
        case .addFriend(let npub, let name):
            showSettings = true
            Task { @MainActor in
                store.pendingFriendInvite = PendingFriendInvite(npub: npub, name: name)
            }
        case .episode(let uuid):
            // Use the same Spotlight-sheet path so we don't need to mutate
            // a NavigationPath we don't currently expose. Library and Home
            // tabs each own their own NavigationStack; presenting the detail
            // as a sheet lands the user on the right record either way.
            spotlightSheet = .episode(uuid)
        case .episodeByGUID(let guid, let startTime):
            // `podcastr://e/<guid>?t=<sec>` — resolve the guid against the
            // local store. When the episode is loaded and a `t=` was
            // provided, seek the playback engine to that timestamp before
            // surfacing the detail sheet so the user lands at the
            // referenced point in time instead of the saved playhead.
            if let episode = store.state.episodes.first(where: { $0.id.uuidString == guid || $0.guid == guid }) {
                if let startTime {
                    playbackState.setEpisode(episode)
                    playbackState.seek(to: startTime)
                    playbackState.play()
                }
                spotlightSheet = .episode(episode.id)
            }
        case .subscription(let uuid):
            spotlightSheet = .subscription(uuid)
        }
    }

    /// Routes a Spotlight continuation activity to the correct in-app screen.
    /// Notes and memories are presented as a standalone sheet so the user lands
    /// on the right record immediately.
    private func handleSpotlight(_ activity: NSUserActivity) {
        guard let link = SpotlightIndexer.deepLink(from: activity) else { return }
        spotlightSheet = link
    }

    /// Builds the detail view shown inside the Spotlight-continuation sheet.
    @ViewBuilder
    private func spotlightDetailView(for link: SpotlightIndexer.DeepLink) -> some View {
        switch link {
        case .note(let id):
            AgentNotesView(spotlightTargetID: id)
        case .memory(let id):
            AgentMemoriesView(spotlightTargetID: id)
        case .subscription(let id):
            if let subscription = store.subscription(id: id) {
                ShowDetailView(subscription: subscription)
            } else {
                spotlightMissing("Show not found", "This subscription is no longer in your library.")
            }
        case .episode(let id):
            if store.episode(id: id) != nil {
                EpisodeDetailView(episodeID: id)
            } else {
                spotlightMissing("Episode not found", "This episode is no longer in your library.")
            }
        }
    }

    /// Empty-state shown inside the Spotlight sheet when the targeted record
    /// has been removed since the index was written.
    private func spotlightMissing(_ title: String, _ subtitle: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: "questionmark.folder",
            description: Text(subtitle)
        )
    }

    private func handleShake() {
        let now = Date()
        guard now.timeIntervalSince(lastShakeTime) > 1.0 else { return }
        lastShakeTime = now

        if feedbackWorkflow.phase == .awaitingScreenshot {
            feedbackWorkflow.screenshot = captureScreenshot()
            feedbackWorkflow.phase = .annotating
        } else {
            Haptics.medium()
            feedbackWorkflow.draft = ""
            feedbackWorkflow.screenshot = nil
            feedbackWorkflow.annotatedImage = nil
            feedbackWorkflow.phase = .composing
            showFeedback = true
        }
    }

    private func captureScreenshot() -> UIImage? {
        guard
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first
        else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { ctx in window.layer.render(in: ctx.cgContext) }
    }

    // MARK: - IdentifiedSpotlightLink

    /// Thin `Identifiable` wrapper so a `SpotlightIndexer.DeepLink` can drive
    /// `.sheet(item:)` without requiring the enum itself to be `Identifiable`.
    private struct IdentifiedSpotlightLink: Identifiable {
        let link: SpotlightIndexer.DeepLink

        var id: String {
            switch link {
            case .note(let id):         return "note:\(id)"
            case .memory(let id):       return "memory:\(id)"
            case .subscription(let id): return "subscription:\(id)"
            case .episode(let id):      return "episode:\(id)"
            }
        }
    }
}
