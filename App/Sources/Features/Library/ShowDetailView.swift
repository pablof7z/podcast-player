import SwiftUI

// MARK: - ShowDetailView

/// Show-level detail screen pushed from `LibraryView`'s grid.
///
/// **Composition:**
///   - `ShowDetailHeader` — artwork-tinted hero (matte).
///   - Description block — editorial body text.
///   - Filter rail (chips) — same `LibraryFilters` enum as the tab.
///   - Episode list — `EpisodeRow` × N, tapping pushes
///     `LibraryEpisodeRoute` onto the enclosing `NavigationStack`.
///
/// **Glass usage:** none on the body. The "Settings for this show"
/// sheet (presented from the toolbar `…` menu) is structurally glass.
///
/// **Lane handoff:** the `navigationDestination(for:)` resolver below
/// renders `EpisodeDetailViewStub`. At merge, Lane 5's real
/// `EpisodeDetailView` replaces it. The route signature
/// (`LibraryEpisodeRoute`) is the contract.
struct ShowDetailView: View {

    let store: LibraryMockStore
    let subscription: LibraryMockSubscription

    @Environment(MockPlaybackState.self) private var playbackState
    @State private var filter: LibraryFilter = .all
    @State private var showSettings: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ShowDetailHeader(
                    subscription: currentSubscription,
                    onSubscribeToggle: { store.toggleSubscription(subscription.id) }
                )

                description

                filterSection
                    .padding(.top, AppTheme.Spacing.md)

                episodeList
                    .padding(.bottom, AppTheme.Spacing.xl)
            }
        }
        .navigationTitle(currentSubscription.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showSettings) {
            ShowDetailSettingsSheet(
                subscription: currentSubscription,
                onDismiss: { showSettings = false }
            )
        }
        .navigationDestination(for: LibraryEpisodeRoute.self) { route in
            EpisodeDetailViewStub(route: route)
        }
    }

    // MARK: - Live snapshot

    /// Re-read the subscription from the store on every render so the
    /// "Subscribe / Subscribed" label flips immediately when toggled.
    private var currentSubscription: LibraryMockSubscription {
        store.subscriptions.first(where: { $0.id == subscription.id }) ?? subscription
    }

    // MARK: - Pieces

    private var description: some View {
        Text(currentSubscription.showDescription)
            .font(AppTheme.Typography.body)
            .foregroundStyle(.secondary)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.lg)
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Episodes")
                .font(AppTheme.Typography.title)
                .padding(.horizontal, AppTheme.Spacing.lg)

            // Glass-wrapped chip rail = structural glass (allowed).
            LibraryFilterRail(selection: $filter)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, AppTheme.Spacing.sm)
        }
    }

    private var episodeList: some View {
        let episodes = filteredEpisodes()
        return LazyVStack(spacing: 0) {
            if episodes.isEmpty {
                ContentUnavailableView(
                    "No episodes match",
                    systemImage: "tray",
                    description: Text("Try a different filter.")
                )
                .padding(.top, AppTheme.Spacing.xl)
            } else {
                ForEach(Array(episodes.enumerated()), id: \.element.id) { idx, ep in
                    EpisodeDetailLink(
                        route: LibraryEpisodeRoute(
                            episodeID: ep.id,
                            subscriptionID: ep.subscriptionID,
                            title: ep.title
                        ),
                        label: {
                            EpisodeRow(
                                episode: ep,
                                showAccent: currentSubscription.accentColor,
                                onPlay: { playEpisode(ep, in: currentSubscription) }
                            )
                            .padding(.horizontal, AppTheme.Spacing.lg)
                        }
                    )
                    if idx != episodes.count - 1 {
                        Divider()
                            .padding(.leading, AppTheme.Spacing.lg + 22 + AppTheme.Spacing.md)
                    }
                }
            }
        }
        .padding(.top, AppTheme.Spacing.sm)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    Haptics.light()
                    showSettings = true
                } label: {
                    Label("Settings for this show", systemImage: "slider.horizontal.3")
                }
                Button {
                    Haptics.medium()
                    store.toggleSubscription(subscription.id)
                } label: {
                    Label(
                        currentSubscription.isSubscribed ? "Unsubscribe" : "Subscribe",
                        systemImage: currentSubscription.isSubscribed ? "minus.circle" : "plus.circle"
                    )
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .accessibilityLabel("Show options")
        }
    }

    // MARK: - Tap-to-play

    /// Synthesizes a `MockPlayerEpisode` from the library shim types and
    /// hands it to the playback state. Lane 2 will replace this bridge with
    /// the real `Episode` -> `AudioEngine` path; for now it lets the
    /// mini-player surface react to user input without leaving the list.
    private func playEpisode(
        _ episode: LibraryMockEpisode,
        in subscription: LibraryMockSubscription
    ) {
        let player = MockPlayerEpisode(
            id: episode.id.uuidString,
            showName: subscription.title,
            episodeNumber: episode.number,
            title: episode.title,
            chapterTitle: nil,
            duration: TimeInterval(episode.durationSeconds),
            primaryArtColor: subscription.accentColor,
            secondaryArtColor: subscription.accentColor.opacity(0.55)
        )
        playbackState.load(player, transcript: [])
        playbackState.play()
    }

    // MARK: - Filtering

    /// Apply the current filter to the show's episode list.
    private func filteredEpisodes() -> [LibraryMockEpisode] {
        let all = store.episodes(for: currentSubscription)
        switch filter {
        case .all:          return all
        case .unplayed:     return all.filter { $0.isUnplayed || $0.isInProgress }
        case .downloaded:
            return all.filter {
                if case .downloaded = $0.downloadStatus { return true }
                return false
            }
        case .transcribed:
            return all.filter {
                if case .downloaded(let t) = $0.downloadStatus, t { return true }
                return false
            }
        }
    }
}

// MARK: - ShowDetailSettingsSheet

/// "Settings for this show" sheet. Mock toggles for auto-download,
/// transcription, notifications. Lane 2 wires these to the real
/// per-show preferences model.
struct ShowDetailSettingsSheet: View {
    let subscription: LibraryMockSubscription
    let onDismiss: () -> Void

    @State private var autoDownload: Bool = true
    @State private var transcribe: Bool = true
    @State private var notifyOnNew: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Episodes") {
                    Toggle("Auto-download new episodes", isOn: $autoDownload)
                    Toggle("Auto-transcribe new episodes", isOn: $transcribe)
                    Toggle("Notify me when new episodes drop", isOn: $notifyOnNew)
                }
                Section {
                    Button(role: .destructive) {
                        Haptics.warning()
                        onDismiss()
                    } label: {
                        Label("Unsubscribe", systemImage: "xmark.circle")
                    }
                }
            }
            .navigationTitle(subscription.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
                }
            }
        }
        .presentationBackground(.thinMaterial)            // structural glass on the sheet
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
