import SwiftUI

// MARK: - ShowDetailView

/// Show-level detail screen pushed from `LibraryView`'s grid.
///
/// **Composition:**
///   - `ShowDetailHeader` — artwork-tinted hero (matte).
///   - Description block — feed `<description>` body text.
///   - Filter rail (chips) — same `LibraryFilter` enum as the tab.
///   - Episode list — `EpisodeRow` × N, tapping pushes
///     `LibraryEpisodeRoute` onto the enclosing `NavigationStack`.
///
/// **Glass usage:** none on the body. The "Settings for this show" sheet
/// (presented from the toolbar `…` menu) is structurally glass.
struct ShowDetailView: View {

    @Environment(AppStateStore.self) private var store
    @Environment(MockPlaybackState.self) private var playback
    @Environment(\.dismiss) private var dismiss

    let subscription: PodcastSubscription

    @State private var filter: LibraryFilter = .all
    @State private var showSettings: Bool = false
    @State private var showUnsubscribeConfirm: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ShowDetailHeader(
                    subscription: liveSubscription,
                    episodeCount: episodes.count
                )

                description

                filterSection
                    .padding(.top, AppTheme.Spacing.md)

                episodeList
                    .padding(.bottom, AppTheme.Spacing.xl)
            }
        }
        .navigationTitle(liveSubscription.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .refreshable { await refresh() }
        .sheet(isPresented: $showSettings) {
            ShowDetailSettingsSheet(
                subscription: liveSubscription,
                store: store,
                onDismiss: { showSettings = false },
                onUnsubscribe: { confirmUnsubscribe() }
            )
        }
        .confirmationDialog(
            "Unsubscribe from \(liveSubscription.title)?",
            isPresented: $showUnsubscribeConfirm,
            titleVisibility: .visible
        ) {
            Button("Unsubscribe", role: .destructive) { performUnsubscribe() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the show and all of its episodes from your library.")
        }
        .navigationDestination(for: LibraryEpisodeRoute.self) { route in
            LibraryEpisodePlaceholder(route: route)
        }
    }

    // MARK: - Live snapshot

    /// Re-read the subscription from the store on every render so settings
    /// updates (notifications toggle, refresh metadata) are reflected.
    private var liveSubscription: PodcastSubscription {
        store.subscription(id: subscription.id) ?? subscription
    }

    private var episodes: [Episode] {
        store.episodes(forSubscription: subscription.id)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var description: some View {
        let body = liveSubscription.description.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            Text(body)
                .font(AppTheme.Typography.body)
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.top, AppTheme.Spacing.lg)
        }
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Episodes")
                .font(AppTheme.Typography.title)
                .padding(.horizontal, AppTheme.Spacing.lg)

            LibraryFilterRail(selection: $filter)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, AppTheme.Spacing.sm)
        }
    }

    private var episodeList: some View {
        let visible = filteredEpisodes()
        return LazyVStack(spacing: 0) {
            if visible.isEmpty {
                ContentUnavailableView(
                    episodes.isEmpty ? "No episodes yet" : "No episodes match",
                    systemImage: "tray",
                    description: Text(
                        episodes.isEmpty
                        ? "Pull down to refresh this feed."
                        : "Try a different filter."
                    )
                )
                .padding(.top, AppTheme.Spacing.xl)
            } else {
                ForEach(Array(visible.enumerated()), id: \.element.id) { idx, ep in
                    Button {
                        handleTap(ep)
                    } label: {
                        EpisodeRow(episode: ep, showAccent: liveSubscription.accentColor)
                            .padding(.horizontal, AppTheme.Spacing.lg)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if idx != visible.count - 1 {
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
                Button(role: .destructive) {
                    Haptics.warning()
                    showUnsubscribeConfirm = true
                } label: {
                    Label("Unsubscribe", systemImage: "minus.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .accessibilityLabel("Show options")
        }
    }

    // MARK: - Filtering

    private func filteredEpisodes() -> [Episode] {
        switch filter {
        case .all:
            return episodes
        case .unplayed:
            return episodes.filter { $0.isUnplayed || $0.isInProgress }
        case .downloaded:
            return episodes.filter {
                if case .downloaded = $0.downloadState { return true }
                return false
            }
        case .transcribed:
            return episodes.filter {
                if case .ready = $0.transcriptState { return true }
                return false
            }
        }
    }

    // MARK: - Actions

    private func handleTap(_ episode: Episode) {
        Haptics.selection()
        // The player agent owns the real `play(episode:)` call. For now we just
        // toggle the existing demo playback so a tap is observably different
        // from a no-op; the navigation push below is the source of truth.
        playback.play()
    }

    private func confirmUnsubscribe() {
        showUnsubscribeConfirm = true
    }

    private func performUnsubscribe() {
        store.removeSubscription(subscription.id)
        dismiss()
    }

    private func refresh() async {
        await SubscriptionService(store: store).refresh(liveSubscription)
    }
}

// MARK: - ShowDetailSettingsSheet

/// "Settings for this show" sheet. Real toggles for notifications + a
/// destructive unsubscribe action. Auto-download / transcription preferences
/// will land here once the corresponding writers exist on the store.
struct ShowDetailSettingsSheet: View {
    let subscription: PodcastSubscription
    let store: AppStateStore
    let onDismiss: () -> Void
    let onUnsubscribe: () -> Void

    @State private var notificationsEnabled: Bool

    init(
        subscription: PodcastSubscription,
        store: AppStateStore,
        onDismiss: @escaping () -> Void,
        onUnsubscribe: @escaping () -> Void
    ) {
        self.subscription = subscription
        self.store = store
        self.onDismiss = onDismiss
        self.onUnsubscribe = onUnsubscribe
        _notificationsEnabled = State(initialValue: subscription.notificationsEnabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Notifications") {
                    Toggle("Notify me when new episodes drop", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, newValue in
                            store.setSubscriptionNotificationsEnabled(
                                subscription.id,
                                enabled: newValue
                            )
                        }
                }
                Section("Feed") {
                    LabeledContent("URL") {
                        Text(subscription.feedURL.absoluteString)
                            .font(AppTheme.Typography.monoCaption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                    if let refreshed = subscription.lastRefreshedAt {
                        LabeledContent("Last refreshed") {
                            Text(refreshed.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Button(role: .destructive) {
                        Haptics.warning()
                        onDismiss()
                        onUnsubscribe()
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
        .presentationBackground(.thinMaterial)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
