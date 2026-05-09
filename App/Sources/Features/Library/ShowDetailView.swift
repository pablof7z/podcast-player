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
    @Environment(\.dismiss) private var dismiss

    let subscription: PodcastSubscription

    @State private var filter: LibraryFilter = .all
    @State private var showSettings: Bool = false
    @State private var showUnsubscribeConfirm: Bool = false
    /// Drives the VoiceOver "Open episode details" custom action — bound into
    /// `ShowDetailEpisodeList` and consumed via `.navigationDestination(item:)`
    /// so the same `EpisodeDetailView` opens regardless of how the user got there.
    @State private var voiceOverDetailRoute: LibraryEpisodeRoute?

    var body: some View {
        List {
            Section {
                ShowDetailHeader(
                    subscription: liveSubscription,
                    episodeCount: episodes.count
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                description
                    .listRowInsets(EdgeInsets(
                        top: 0,
                        leading: AppTheme.Spacing.lg,
                        bottom: 0,
                        trailing: AppTheme.Spacing.lg
                    ))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                filterSection
                    .listRowInsets(EdgeInsets(
                        top: AppTheme.Spacing.md,
                        leading: 0,
                        bottom: AppTheme.Spacing.sm,
                        trailing: 0
                    ))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            episodeListSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground).ignoresSafeArea())
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
        // `.alert` rather than `.confirmationDialog` because the dialog is
        // anchored to the toolbar's `Menu`. iOS 26 renders confirmationDialog
        // anchored to a menu as a popover and elides any `role: .cancel`
        // button (the popover's tap-outside-to-dismiss is treated as the
        // implicit cancel). That leaves the user staring at a single red
        // "Unsubscribe" button with no visible escape — a real UX trap for a
        // destructive action that wipes thousands of episodes. `.alert` is
        // a centred modal and reliably renders both buttons regardless of
        // anchor context.
        .alert(
            "Unsubscribe from \(liveSubscription.title)?",
            isPresented: $showUnsubscribeConfirm
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Unsubscribe", role: .destructive) { performUnsubscribe() }
        } message: {
            Text("This removes the show and all of its episodes from your library.")
        }
        .navigationDestination(for: LibraryEpisodeRoute.self) { route in
            LibraryEpisodePlaceholder(route: route)
        }
        .navigationDestination(item: $voiceOverDetailRoute) { route in
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

    @ViewBuilder
    private var episodeListSection: some View {
        let visible = filteredEpisodes()
        if visible.isEmpty {
            Section {
                ContentUnavailableView(
                    episodes.isEmpty ? "No episodes yet" : "No episodes match",
                    systemImage: "tray",
                    description: Text(
                        episodes.isEmpty
                        ? "Pull down to refresh this feed."
                        : "Try a different filter."
                    )
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .padding(.top, AppTheme.Spacing.xl)
            }
        } else {
            Section {
                ShowDetailEpisodeList(
                    subscription: liveSubscription,
                    episodes: visible,
                    voiceOverDetailRoute: $voiceOverDetailRoute
                )
            }
        }
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
