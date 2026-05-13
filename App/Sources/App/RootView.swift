import CoreSpotlight
import SwiftUI

/// The tabs available at the root navigation level.
///
/// Settings is reachable via a top-right toolbar button on every tab rather
/// than as a tab entry. The Player lives behind a persistent mini-bar that
/// expands into `PlayerView` on tap.
enum RootTab: String, CaseIterable {
    case home = "Home"
    case search = "Search"
    case clippings = "Clippings"
    case wiki = "Wiki"

    var icon: String {
        switch self {
        case .home:      "house.fill"
        case .search:    "magnifyingglass"
        case .clippings: "scissors"
        case .wiki:      "book.closed.fill"
        }
    }
}

/// The root view of the app. Hosts the main tab bar, the feedback shake gesture,
/// onboarding gate, and deep-link routing.
struct RootView: View {
    /// Optional Nostr relay service — owned by `AppMain` so its
    /// lifecycle outlives any presented sheet. Nil before the cold-launch
    /// `.task` in AppMain runs. We late-bind the responder's
    /// `PodcastAgentToolDeps` provider + ask coordinator once both this
    /// view's `playbackState` and the relay service exist.
    let relayService: NostrRelayService?

    @Environment(AppStateStore.self) private var store
    @Environment(AgentAskCoordinator.self) private var askCoordinator
    @State private var selectedTab: RootTab = .home
    @State private var feedbackWorkflow = FeedbackWorkflow()
    @State private var showFeedback = false
    @State private var showSettings = false
    @State private var showAgentChat = false
    /// Persistent agent session. Kept at this level so in-flight LLM tasks
    /// survive sheet dismissal. Nil until the user first opens the chat.
    @State private var agentSession: AgentChatSession?
    /// Message count when the agent chat sheet was last visible. Used to
    /// detect new agent replies while the sheet is closed.
    @State private var agentUnseenMessageCount: Int = 0
    /// Drives the Voice surface presentation. Toggled by the
    /// `voiceModeRequested` notification fired by `StartVoiceModeIntent`
    /// (Action Button, Siri, Spotlight, AirPods squeeze).
    @State private var showVoiceMode = false
    @State private var lastShakeTime: Date = .distantPast
    /// Drives a Spotlight-continuation sheet for a note or memory.
    @State private var spotlightSheet: SpotlightIndexer.DeepLink?
    /// Drives the persistent mini-player and full Now Playing view. Wraps the
    /// real `AudioEngine`; persistence callbacks are wired in `.onAppear` so
    /// the wrapper stays independent of `AppStateStore`'s type.
    @State private var playbackState = PlaybackState()
    @State private var showFullPlayer = false
    /// Drives the episode-detail sheet opened when the player's clip-source
    /// chip is tapped (notification `openEpisodeDetailRequested`).
    @State private var clipSourceEpisodeID: UUID?
    /// Drives the show-detail sheet opened from the player's "Go to show"
    /// menu item (notification `openSubscriptionDetailRequested`). Paired
    /// with `clipSourceEpisodeID` so the dismiss+present can happen in one
    /// render tick — the old URL-round-trip path crashed when it tried to
    /// present `spotlightSheet` while the player was mid-dismissal.
    @State private var playerNavSubscriptionID: UUID?
    /// Drives the NostrConversationDetailView sheet opened when the player's
    /// generation-source chip is tapped for a Nostr-originated episode.
    @State private var generationSourceNostrRootID: String?
    /// Shared namespace for matched-geometry between mini-bar and full player.
    @Namespace private var playerNamespace

    /// Hashable identity for the (optional) relay service so `.task(id:)`
    /// can re-fire when the parent's `@State` transitions from nil to a
    /// real service instance.
    private var relayServiceIdentity: ObjectIdentifier? {
        relayService.map(ObjectIdentifier.init)
    }

    var body: some View {
        tabBar
            .environment(playbackState)
            .task(id: relayServiceIdentity) {
                // Late-bind the Nostr agent's podcast tool deps. Driven
                // by `.task(id:)` rather than `.onAppear` because the
                // relay service is created in `AppMain.task` and the
                // race is real: on cold launch RootView often appears
                // before the parent task fires, so `relayService` is
                // still nil at first appearance. A plain `if let
                // relayService` inside `onAppear` would silently skip,
                // peer tool calls would then hit the "Podcast tools
                // are not wired up" error envelope, and nothing would
                // ever re-run to fix it.
                //
                // `.task(id:)` re-fires whenever the keyed identity
                // changes — including the nil→non-nil transition we
                // care about — so the provider lands before any peer
                // inbound can reach a tool dispatch.
                guard let relayService else { return }
                relayService.agentResponder.podcastDepsProvider = { [store, playbackState] in
                    LivePodcastAgentToolDeps.make(store: store, playback: playbackState)
                }
                relayService.agentResponder.askCoordinator = askCoordinator
            }
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
                // Segment end: advance queue or pause if empty.
                playbackState.onSegmentFinished = { [store, playbackState] in
                    let advanced = playbackState.playNext { store.episode(id: $0) }
                    if !advanced {
                        playbackState.pause()
                    }
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
                    store.podcast(id: episode.podcastID)?.title ?? ""
                }
                playbackState.resolveShowImage = { [store] episode in
                    store.podcast(id: episode.podcastID)?.imageURL
                }
                // Lock-screen / Control Center enrichment. The engine reads
                // these on every Now Playing publish so the lock screen
                // shows show name + active chapter title, not just episode
                // title. Each defaults to no-op so the engine works in
                // isolation; we wire them here so the live store is the
                // source of truth (chapters can hydrate post-playback).
                playbackState.engine.resolveShowName = { [store] episode in
                    store.podcast(id: episode.podcastID)?.title
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
                        ?? store.podcast(id: live.podcastID)?.imageURL
                }
                // Chapter resolver for headphone-gesture mappings
                // (next/previous chapter on AirPods double/triple-tap). Reads
                // from the live store so chapters hydrated post-playback are
                // picked up without re-wiring.
                playbackState.resolveNavigableChapters = { [store] episode in
                    let live = store.episode(id: episode.id) ?? episode
                    return live.chapters?.filter(\.includeInTableOfContents) ?? []
                }
                // Clip handler — fires when the user's headphone gesture is
                // mapped to "clip now". The AutoSnip controller is wired
                // below so the singleton's `playback`/`store` refs are set
                // before any AirPods event arrives.
                playbackState.onClipRequested = {
                    AutoSnipController.shared.captureSnip(source: .headphone)
                }
                // Attach AutoSnip early so a headphone-gesture clip works
                // even when the user has never opened the full player.
                // Idempotent — `PlayerView.onAppear` calls this too.
                AutoSnipController.shared.attach(playback: playbackState, store: store)
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
                if let session = agentSession {
                    NavigationStack {
                        AgentChatView(session: session)
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
            }
            .onChange(of: showAgentChat) { _, _ in
                // Snapshot message count on every open/close so that:
                // • opening the chat clears the badge (sheet is now visible)
                // • closing records the baseline so new replies show the badge
                agentUnseenMessageCount = agentSession?.messages.count ?? 0
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
            // Voice mode surface — opened by `StartVoiceModeIntent` (Action
            // Button / Siri / Spotlight / AirPods squeeze). The intent
            // posts `voiceModeRequested`; we observe it below and pop the
            // cover. Without this wiring the intent ran in the background
            // and the user saw nothing happen.
            .fullScreenCover(isPresented: $showVoiceMode) {
                VoiceView(onSwitchToText: {
                    showVoiceMode = false
                    openAgentChat()
                })
            }
            .onReceive(NotificationCenter.default.publisher(for: .voiceModeRequested)) { _ in
                showVoiceMode = true
            }
            // Long-press on a transcript line in the player posts this
            // notification after stashing the segment context on the store.
            // `AgentChatSession.init` drains the context on the next sheet
            // open and prefills the composer.
            .onReceive(NotificationCenter.default.publisher(for: .askAgentRequested)) { _ in
                showFullPlayer = false
                openAgentChat()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openPlayerRequested)) { _ in
                showFullPlayer = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openEpisodeDetailRequested)) { note in
                guard let idString = note.userInfo?["episodeID"] as? String,
                      let uuid = UUID(uuidString: idString) else { return }
                showFullPlayer = false
                clipSourceEpisodeID = uuid
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSubscriptionDetailRequested)) { note in
                guard let idString = note.userInfo?["subscriptionID"] as? String,
                      let uuid = UUID(uuidString: idString) else { return }
                showFullPlayer = false
                playerNavSubscriptionID = uuid
            }
            .onReceive(NotificationCenter.default.publisher(for: .openAgentChatConversation)) { note in
                guard let convID = note.userInfo?["conversationID"] as? UUID else { return }
                showFullPlayer = false
                if agentSession == nil {
                    agentSession = AgentChatSession(
                        store: store,
                        playback: playbackState,
                        askCoordinator: askCoordinator
                    )
                }
                Task { @MainActor in
                    await agentSession?.switchToConversation(convID)
                    showAgentChat = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openNostrConversationRequested)) { note in
                guard let rootID = note.userInfo?["rootEventID"] as? String else { return }
                showFullPlayer = false
                generationSourceNostrRootID = rootID
            }
            .modifier(PlayerNavSheets(
                episodeID: $clipSourceEpisodeID,
                subscriptionID: $playerNavSubscriptionID,
                store: store
            ))
            .sheet(item: Binding(
                get: { generationSourceNostrRootID.map(IdentifiedString.init) },
                set: { generationSourceNostrRootID = $0?.value }
            )) { identified in
                if let convo = store.state.nostrConversations.first(where: { $0.rootEventID == identified.value }) {
                    NavigationStack {
                        NostrConversationDetailView(conversation: convo)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button("Done") {
                                        generationSourceNostrRootID = nil
                                    }
                                }
                            }
                    }
                }
            }
            .nostrApprovalPresenter()
            .agentAskPresenter(coordinator: askCoordinator)
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
        // pattern Apple Music uses for its mini-player. Search overrides
        // this to `.never` so the keyboard doesn't steal focus.
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
            NavigationStack {
                HomeView()
                    .toolbar { sharedToolbar() }
            }
        case .search:
            NavigationStack { PodcastSearchView().toolbar { sharedToolbar() } }
                .tabBarMinimizeBehavior(.never)
        case .clippings:
            NavigationStack { ClippingsView().toolbar { sharedToolbar() } }
        case .wiki:
            NavigationStack { WikiView().toolbar { sharedToolbar() } }
        }
    }

    /// True when the agent has sent new messages since the sheet was last open.
    private var hasUnreadAgentMessages: Bool {
        guard !showAgentChat, let session = agentSession else { return false }
        return session.messages.count > agentUnseenMessageCount
    }

    /// Ensures the persistent agent session exists, then presents the chat sheet.
    private func openAgentChat() {
        if agentSession == nil {
            agentSession = AgentChatSession(
                store: store,
                playback: playbackState,
                askCoordinator: askCoordinator
            )
        }
        showAgentChat = true
    }

    /// Top-right toolbar shared across tabs:
    ///   • Sparkles — presents the agent chat sheet.
    ///   • Gear — presents the Settings sheet.
    @ToolbarContentBuilder
    private func sharedToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Haptics.selection()
                openAgentChat()
            } label: {
                Image(systemName: "sparkles")
                    .overlay(alignment: .topTrailing) {
                        if hasUnreadAgentMessages {
                            Circle()
                                .fill(.red)
                                .frame(width: 7, height: 7)
                                .offset(x: 4, y: -4)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(AppTheme.Animation.springFast, value: hasUnreadAgentMessages)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(hasUnreadAgentMessages ? "Open Agent — new reply" : "Open Agent")
            .keyboardShortcut("a", modifiers: [.command, .shift])
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
            openAgentChat()
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
                    playbackState.navigationalSeek(to: startTime)
                    playbackState.play()
                }
                spotlightSheet = .episode(episode.id)
            }
        case .subscription(let uuid):
            spotlightSheet = .subscription(uuid)
        case .clip(let clipID):
            // `podcastr://clip/<uuid>` — resolve the clip → episode,
            // seek the engine to `startSeconds`, and surface the detail
            // sheet. Mirrors the `episodeByGUID` pattern. When the clip
            // is no longer in the local store (e.g. a friend's share for
            // a podcast you don't have) we silently no-op rather than
            // leaving a "missing" sheet open — the friend's audio isn't
            // recoverable from the link alone.
            if let clip = store.clip(id: clipID),
               let episode = store.episode(id: clip.episodeID) {
                playbackState.setEpisode(episode)
                playbackState.navigationalSeek(to: clip.startSeconds)
                playbackState.play()
                spotlightSheet = .episode(episode.id)
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
        case .subscription(let id):
            if let podcast = store.podcast(id: id) {
                ShowDetailView(podcast: podcast)
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

    // MARK: - IdentifiedUUID

    /// Thin `Identifiable` wrapper so a `UUID` can drive `.sheet(item:)`
    /// via optional binding (same pattern as `IdentifiedSpotlightLink`).
    private struct IdentifiedUUID: Identifiable {
        let id: UUID
    }

    // MARK: - IdentifiedString

    /// Thin `Identifiable` wrapper so a plain `String` can drive `.sheet(item:)`.
    private struct IdentifiedString: Identifiable {
        let value: String
        var id: String { value }
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

// MARK: - PlayerNavSheets

/// Pulls the two "swap the player sheet for a detail sheet" presentations
/// out of `RootView.body` so the body stays inside the Swift type-checker's
/// reasonable-time budget. Both bindings are driven by notifications posted
/// from inside the player (`PlayerClipSourceChip`, `PlayerMoreMenu`); the
/// onReceive handlers in `RootView` flip `showFullPlayer` and the matching
/// id in the same render tick so SwiftUI sees a single dismiss→present
/// transition instead of overlapping sheets.
private struct PlayerNavSheets: ViewModifier {
    @Binding var episodeID: UUID?
    @Binding var subscriptionID: UUID?
    let store: AppStateStore

    func body(content: Content) -> some View {
        content
            .sheet(item: episodeBinding) { identified in
                NavigationStack {
                    EpisodeDetailView(episodeID: identified.id)
                }
            }
            .sheet(item: subscriptionBinding) { identified in
                NavigationStack {
                    if let podcast = store.podcast(id: identified.id) {
                        ShowDetailView(podcast: podcast)
                    } else {
                        ContentUnavailableView(
                            "Show not found",
                            systemImage: "questionmark.folder",
                            description: Text("This subscription is no longer in your library.")
                        )
                    }
                }
            }
    }

    private var episodeBinding: Binding<IdentifiedUUID?> {
        Binding(
            get: { episodeID.map(IdentifiedUUID.init) },
            set: { episodeID = $0?.id }
        )
    }

    private var subscriptionBinding: Binding<IdentifiedUUID?> {
        Binding(
            get: { subscriptionID.map(IdentifiedUUID.init) },
            set: { subscriptionID = $0?.id }
        )
    }

    private struct IdentifiedUUID: Identifiable {
        let id: UUID
    }
}
