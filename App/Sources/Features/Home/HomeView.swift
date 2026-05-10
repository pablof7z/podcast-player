import SwiftUI

// MARK: - HomeView
//
// Merged Home — replaces the old Today + Library tabs with a single
// editorial surface:
//   • Dateline + active-filter chip strip
//   • Featured (resume cards + agent picks), collapsible
//   • Search-entry affordance
//   • Subscription list (default) or grid, recency-sorted, filterable
//
// Persistence keys mirror what `LibraryView` used so the user's chosen
// filter / category carries over without a one-time reset.

struct HomeView: View {
    /// Closure invoked when the user taps the search-entry bar. Mirrors
    /// the `LibraryView` pattern: `RootView` constructs Home with a
    /// `selectedTab = .search` closure.
    var onOpenSearch: () -> Void = { Haptics.light() }

    @Environment(AppStateStore.self) private var store
    @Environment(PlaybackState.self) private var playback

    @AppStorage("library.filter") private var filter: LibraryFilter = .all
    @AppStorage("library.categoryFilterID") private var categoryFilterID: String = ""
    @AppStorage("home.subscriptionLayout") private var layout: HomeSubscriptionLayout = .list
    @AppStorage("home.featuredExpanded") private var featuredExpanded: Bool = true

    @State private var picksService = AgentPicksService.shared
    @State private var unsubscribeTarget: PodcastSubscription?
    @State private var relatedSheetEpisode: Episode?
    @State private var voiceOverDetailRoute: HomeEpisodeRoute?
    @State private var showAddShowSheet: Bool = false
    /// Cached "now" used by the dateline + recency pills. Pinned at body
    /// composition time so a 1Hz playback tick doesn't re-format the
    /// recency pill on every redraw.
    @State private var renderedAt: Date = Date()

    var body: some View {
        scrollContent
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .refreshable { await refreshAllFeeds() }
            .navigationDestination(for: HomeEpisodeRoute.self) { route in
                EpisodeDetailView(episodeID: route.episodeID)
            }
            .navigationDestination(item: $voiceOverDetailRoute) { route in
                EpisodeDetailView(episodeID: route.episodeID)
            }
            .navigationDestination(for: PodcastSubscription.self) { sub in
                ShowDetailView(subscription: sub)
            }
            .sheet(isPresented: $showAddShowSheet) {
                AddShowSheet(store: store, onDismiss: { showAddShowSheet = false })
            }
            .sheet(item: $relatedSheetEpisode) { episode in
                HomeRelatedSheet(
                    seedEpisode: episode,
                    seedSubscription: store.subscription(id: episode.subscriptionID)
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .alert(
                "Unsubscribe from \(unsubscribeTarget?.title ?? "")?",
                isPresented: Binding(
                    get: { unsubscribeTarget != nil },
                    set: { if !$0 { unsubscribeTarget = nil } }
                ),
                presenting: unsubscribeTarget
            ) { sub in
                Button("Cancel", role: .cancel) {}
                Button("Unsubscribe", role: .destructive) {
                    Haptics.warning()
                    store.removeSubscription(sub.id)
                }
            } message: { _ in
                Text("This removes the show and all its episodes from your library.")
            }
            .task { picksService.ensureFreshPicks(store: store) }
            .onAppear { renderedAt = Date() }
    }

    // MARK: - Layout

    @ViewBuilder
    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HomeDatelineView(components: datelineComponents)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.top, AppTheme.Spacing.sm)

                if !activeChips.isEmpty {
                    HomeActiveFilterChipStrip(
                        chips: activeChips,
                        onDismiss: dismissChip
                    )
                }

                HomeFeaturedSection(
                    resumeEpisodes: store.inProgressEpisodes,
                    picksBundle: picksService.bundle,
                    isExpanded: $featuredExpanded,
                    onPlayEpisode: playEpisode,
                    onLongPressEpisode: { relatedSheetEpisode = $0 }
                )

                searchEntryBar
                    .padding(.horizontal, AppTheme.Spacing.md)

                subscriptionsSurface
                    .padding(.bottom, AppTheme.Spacing.xl)
            }
        }
    }

    // MARK: - Subscription surface

    @ViewBuilder
    private var subscriptionsSurface: some View {
        if store.state.subscriptions.isEmpty {
            firstRunEmptyState
                .padding(.top, AppTheme.Spacing.xl)
        } else if filteredSubs.isEmpty {
            filteredEmptyState
                .padding(.top, AppTheme.Spacing.xl)
        } else {
            HomeSubscriptionListSection(
                subscriptions: filteredSubs,
                layout: layout,
                now: renderedAt,
                onRequestUnsubscribe: { unsubscribeTarget = $0 }
            )
        }
    }

    // MARK: - Filter derivation
    //
    // Filters apply to the subscription list ONLY — featured is curated.
    // Pure derivation kept inline so the `body` getter stays straightforward
    // without an extra service indirection for trivial in-memory work.

    private var filteredSubs: [PodcastSubscription] {
        let recencySorted = store.sortedSubscriptionsByRecency
        let categoryScoped = applyCategoryFilter(recencySorted)
        switch filter {
        case .all:         return categoryScoped
        case .unplayed:    return categoryScoped.filter { store.unplayedCount(forSubscription: $0.id) > 0 }
        case .downloaded:  return categoryScoped.filter { store.hasDownloadedEpisode(forSubscription: $0.id) }
        case .transcribed: return categoryScoped.filter { store.hasTranscribedEpisode(forSubscription: $0.id) }
        }
    }

    private func applyCategoryFilter(_ subs: [PodcastSubscription]) -> [PodcastSubscription] {
        guard let id = selectedCategoryID,
              let category = store.category(id: id) else { return subs }
        let allowed = Set(category.subscriptionIDs)
        return subs.filter { allowed.contains($0.id) }
    }

    private var selectedCategoryID: UUID? {
        guard let id = UUID(uuidString: categoryFilterID),
              store.category(id: id) != nil else { return nil }
        return id
    }

    private var datelineComponents: HomeDatelineComponents {
        HomeDateline.components(
            episodes: store.state.episodes,
            topics: store.state.threadingTopics,
            now: renderedAt
        )
    }

    private var activeChips: [HomeActiveFilterChip] {
        HomeActiveFilters.chips(
            filter: filter,
            categoryID: selectedCategoryID,
            categoryName: { store.category(id: $0)?.name }
        )
    }

    private func dismissChip(_ chip: HomeActiveFilterChip) {
        switch chip.kind {
        case .libraryFilter: filter = .all
        case .category:      categoryFilterID = ""
        }
    }

    // MARK: - Search entry

    private var searchEntryBar: some View {
        Button {
            Haptics.light()
            onOpenSearch()
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.Tint.agentSurface)
                Text("Search Podcastr…")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.md)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: AppTheme.Corner.lg))
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search Podcastr")
        .accessibilityHint("Opens Search")
    }

    // MARK: - Empty states

    private var firstRunEmptyState: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            VStack(spacing: AppTheme.Spacing.xs) {
                Text("Your shows live here.")
                    .font(AppTheme.Typography.title)
                Text("Search Apple Podcasts, paste a feed URL, or import an OPML file to begin.")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                Haptics.light()
                showAddShowSheet = true
            } label: {
                Label("Add Show", systemImage: "plus.circle.fill")
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
            }
            .buttonStyle(.glassProminent)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
    }

    private var filteredEmptyState: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: filter.emptyStateGlyph)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            VStack(spacing: AppTheme.Spacing.xs) {
                Text(filter.emptyStateTitle)
                    .font(AppTheme.Typography.title)
                Text(filter.emptyStateSubtitle)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                Haptics.light()
                categoryFilterID = ""
                filter = .all
            } label: {
                Label("Clear filters", systemImage: "line.3.horizontal.decrease.circle")
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HomeFilterToolbarMenu(
                filter: $filter,
                categoryID: $categoryFilterID,
                layout: $layout,
                categories: store.state.categories
            )
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Haptics.light()
                showAddShowSheet = true
            } label: {
                Image(systemName: "plus.circle")
                    .font(.title3)
            }
            .accessibilityLabel("Add show")
        }
    }

    // MARK: - Actions

    private func playEpisode(_ episode: Episode) {
        Haptics.medium()
        playback.setEpisode(episode)
        playback.play()
    }

    private func refreshAllFeeds() async {
        await SubscriptionRefreshService.shared.refreshAll(store: store)
        // Library state moved meaningfully — let the agent picks update on
        // the next user-driven appearance instead of waiting on the 6h TTL.
        picksService.invalidate()
    }
}
