import CoreSpotlight
import SwiftUI

/// The tabs available at the root navigation level.
enum RootTab: String, CaseIterable {
    case home = "Home"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .settings: "gear"
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
    @State private var lastShakeTime: Date = .distantPast
    /// Drives a Spotlight-continuation sheet for a note or memory.
    /// Set by `handleSpotlight` and cleared on sheet dismiss.
    @State private var spotlightSheet: SpotlightIndexer.DeepLink?

    var body: some View {
        tabBar
            .onShake { handleShake() }
            .sheet(isPresented: $showFeedback) {
                FeedbackView(workflow: feedbackWorkflow)
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
            .onContinueUserActivity(HandoffActivityType.editItem, perform: handleHandoff)
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
    }

    @ViewBuilder
    private func tabContent(for tab: RootTab) -> some View {
        switch tab {
        case .home:
            NavigationStack {
                HomeView()
            }
        case .settings:
            NavigationStack { SettingsView() }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let link = DeepLinkHandler.resolve(url) else { return }
        switch link {
        case .settings:
            selectedTab = .settings
        case .feedback:
            showFeedback = true
        case .newItem(let title):
            selectedTab = .home
            // Delay one run-loop tick so the Home tab is visible before the
            // add-row animates in. Without this, SwiftUI may drop the state
            // change because the HomeView isn't yet in the hierarchy.
            Task { @MainActor in
                store.pendingHomeAction = .addItem(prefill: title)
            }
        case .overdue:
            selectedTab = .home
            Task { @MainActor in
                store.pendingHomeAction = .showOverdue
            }
        case .agent:
            selectedTab = .home
            Task { @MainActor in
                store.pendingHomeAction = .openAgent
            }
        case .addFriend(let npub, let name):
            selectedTab = .settings
            Task { @MainActor in
                store.pendingFriendInvite = PendingFriendInvite(npub: npub, name: name)
            }
        }
    }

    /// Routes a Spotlight continuation activity to the correct in-app screen.
    ///
    /// Items open their detail sheet via `HomeView`'s `.onChange(of: store.pendingHomeAction)`.
    /// Notes and memories are presented as a standalone `NavigationStack` sheet
    /// directly from `RootView` so the user lands on the right record immediately
    /// without having to navigate Settings → Agent → Notes/Memories manually.
    private func handleSpotlight(_ activity: NSUserActivity) {
        guard let link = SpotlightIndexer.deepLink(from: activity) else { return }
        switch link {
        case .item(let id):
            selectedTab = .home
            Task { @MainActor in
                store.pendingHomeAction = .openItem(id)
            }
        case .note, .memory:
            spotlightSheet = link
        }
    }

    /// Builds the detail view shown inside the Spotlight-continuation sheet.
    @ViewBuilder
    private func spotlightDetailView(for link: SpotlightIndexer.DeepLink) -> some View {
        switch link {
        case .note(let id):
            AgentNotesView(spotlightTargetID: id)
        case .memory(let id):
            AgentMemoriesView(spotlightTargetID: id)
        case .item:
            EmptyView() // Items are routed through HomeView; should never reach here.
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

    private func handleHandoff(_ activity: NSUserActivity) {
        selectedTab = .home
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
            case .item(let id):   return "item:\(id)"
            case .note(let id):   return "note:\(id)"
            case .memory(let id): return "memory:\(id)"
            }
        }
    }
}
