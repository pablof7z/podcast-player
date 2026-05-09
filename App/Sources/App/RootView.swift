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
    case wiki = "Wiki"
    case ask = "Ask"

    var icon: String {
        switch self {
        case .home:    "house.fill"
        case .library: "books.vertical.fill"
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
                playbackState.onEpisodeFinished = { [store] id in
                    store.markEpisodePlayed(id)
                }
                // Cold-launch quick-action routing: AppDelegate stashed the
                // shortcut URL during didFinishLaunchingWithOptions; consume
                // it now and clear so subsequent re-appears don't re-route.
                if let delegate = UIApplication.shared.delegate as? AppDelegate,
                   let url = delegate.pendingShortcutURL {
                    delegate.pendingShortcutURL = nil
                    handleDeepLink(url)
                }
            }
            .fullScreenCover(isPresented: $showFullPlayer) {
                PlayerView(
                    state: playbackState,
                    glassNamespace: playerNamespace
                )
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

    private var tabBar: some View {
        TabView(selection: $selectedTab) {
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
        .tabViewBottomAccessory {
            if playbackState.episode != nil {
                MiniPlayerView(
                    state: playbackState,
                    onTap: { showFullPlayer = true },
                    glassNamespace: playerNamespace
                )
            }
        }
    }

    @ViewBuilder
    private func tabContent(for tab: RootTab) -> some View {
        switch tab {
        case .home:
            NavigationStack { HomeView().toolbar { sharedToolbar(showAgent: true) } }
        case .library:
            NavigationStack { LibraryView().toolbar { sharedToolbar(showAgent: true) } }
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
        }
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
            case .note(let id):   return "note:\(id)"
            case .memory(let id): return "memory:\(id)"
            }
        }
    }
}
