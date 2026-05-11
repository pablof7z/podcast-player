import SwiftUI

// MARK: - HomeView
//
// Merged Home — replaces the old Today + Library tabs with a single
// editorial surface:
//   • Dateline + active-filter chip strip
//   • Featured (resume cards + agent picks), collapsible
//   • Subscription list (default) or grid, recency-sorted, filterable
//
// Persistence keys mirror what `LibraryView` used so the user's chosen
// filter / category carries over without a one-time reset.
//
// Search lives on its own tab. The earlier inline search-entry bar was
// removed — it duplicated the tab-bar affordance and burned vertical
// space in the editorial scroll.

struct HomeView: View {
    @Environment(AppStateStore.self) private var store
    @Environment(PlaybackState.self) private var playback

    @AppStorage("library.filter") private var filter: LibraryFilter = .all
    @AppStorage("library.categoryFilterID") private var categoryFilterID: String = ""
    @AppStorage("home.subscriptionLayout") private var layout: HomeSubscriptionLayout = .list
    @AppStorage("home.featuredExpanded") private var featuredExpanded: Bool = true

    @State private var picksService = AgentPicksService.shared
    @State private var threadingService = ThreadingInferenceService.shared
    @State private var unsubscribeTarget: PodcastSubscription?
    @State private var relatedSheetEpisode: Episode?
    @State private var threadedTodaySheet: ThreadingInferenceService.ActiveTopic?
    @State private var voiceOverDetailRoute: HomeEpisodeRoute?
    @State private var showAddShowSheet: Bool = false
    @State private var showCategoryPicker: Bool = false
    /// Cached "now" used by the dateline + recency pills. Pinned at body
    /// composition time so a 1Hz playback tick doesn't re-format the
    /// recency pill on every redraw.
    @State private var renderedAt: Date = Date()

    var body: some View {
        scrollContent
            .navigationTitle(navBarTitle)
            .navigationBarTitleDisplayMode(.inline)
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
            .sheet(item: $threadedTodaySheet) { active in
                HomeThreadedTodayView(active: active)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showCategoryPicker) {
                HomeCategoryPickerSheet(
                    selectedCategoryID: selectedCategoryID,
                    onSelect: { id in
                        categoryFilterID = id?.uuidString ?? ""
                    }
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
            .task {
                picksService.ensureFreshPicks(store: store, category: activeCategory)
                // Bind the threading service to the store so the
                // "Threaded Today" derivation has somewhere to look.
                threadingService.attach(store: store)
            }
            // Re-curate the featured section whenever the user flips
            // categories. The picks service treats each category as its
            // own cache slot, so this either reads a cached bundle or
            // kicks off a fresh stream. The cross-fade itself is handled
            // by the `.id`-keyed transition on `HomeFeaturedSection`'s
            // rail; this `onChange` only owns the data side.
            .onChange(of: categoryFilterID) { _, _ in
                picksService.setActiveCategory(selectedCategoryID)
                picksService.ensureFreshPicks(store: store, category: activeCategory)
            }
            .onAppear { renderedAt = Date() }
    }

    /// Top active threading topic for the "Threaded Today" affordance.
    /// Nil when no topic has at least three unplayed mentions, which is
    /// also the signal to hide the pill entirely. Scoped to the active
    /// category when one is set so flipping sections re-curates the pill
    /// to a thread that lives inside that section.
    private var topActiveThread: ThreadingInferenceService.ActiveTopic? {
        threadingService.topActiveTopics(
            limit: 1,
            subscriptionFilter: allowedSubscriptionIDs
        ).first
    }

    /// Subscription-id set for the active category, or `nil` for All.
    /// Resolved once and passed down so the featured surface, dateline,
    /// and threaded-today rail all narrow to the same set of shows.
    private var allowedSubscriptionIDs: Set<UUID>? {
        guard let id = selectedCategoryID,
              let category = store.category(id: id) else { return nil }
        return Set(category.subscriptionIDs)
    }

    /// Resolved `PodcastCategory` for the active filter, or `nil` for All.
    private var activeCategory: PodcastCategory? {
        guard let id = selectedCategoryID else { return nil }
        return store.category(id: id)
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

                if shouldShowFeaturedSection {
                    HomeFeaturedSection(
                        resumeEpisodes: scopedResumeEpisodes,
                        picksBundle: picksService.bundle(for: selectedCategoryID),
                        isStreaming: picksService.isStreaming(for: selectedCategoryID),
                        activeThread: topActiveThread,
                        activeCategoryID: selectedCategoryID,
                        activeCategoryName: activeCategory?.name,
                        isExpanded: $featuredExpanded,
                        onPlayEpisode: playEpisode,
                        onLongPressEpisode: { relatedSheetEpisode = $0 },
                        onOpenThread: { threadedTodaySheet = topActiveThread }
                    )
                }

                subscriptionsSurface
                    .padding(.bottom, AppTheme.Spacing.xl)
            }
        }
    }

    /// Resume rail filtered to the active category when one is set, or
    /// the global rail otherwise. Empty list collapses the rail entirely
    /// in `HomeFeaturedSection`.
    private var scopedResumeEpisodes: [Episode] {
        HomeCategoryScope.episodesInCategory(
            store.inProgressEpisodes,
            allowedSubscriptionIDs: allowedSubscriptionIDs
        )
    }

    // MARK: - Subscription surface

    @ViewBuilder
    private var subscriptionsSurface: some View {
        if store.state.subscriptions.isEmpty {
            HomeFirstRunEmptyState(onAddShow: { showAddShowSheet = true })
                .padding(.top, AppTheme.Spacing.xl)
        } else if filteredSubs.isEmpty {
            HomeFilteredEmptyState(
                filter: filter,
                categoryName: activeCategory?.name,
                onClearFilters: {
                    categoryFilterID = ""
                    filter = .all
                }
            )
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

    private var navBarTitle: String {
        activeCategory?.name ?? "Home"
    }

    private var datelineComponents: HomeDatelineComponents {
        // Topic list narrows to the category before being passed in: a
        // contradiction in a topic whose mentions live outside the
        // active category shouldn't bump the section's contradiction
        // count, otherwise switching to "Learning" reads
        // "1 CONTRADICTION" for a thread that doesn't live there.
        HomeDateline.components(
            episodes: store.state.episodes,
            topics: scopedThreadingTopics,
            now: renderedAt,
            categoryName: activeCategory?.name,
            allowedSubscriptionIDs: allowedSubscriptionIDs
        )
    }

    /// Threading topics whose mentions land in the active category. When
    /// no category is active this returns the global topic list.
    private var scopedThreadingTopics: [ThreadingTopic] {
        HomeCategoryScope.topicsInCategory(
            topics: store.state.threadingTopics,
            mentions: store.state.threadingMentions,
            episodes: store.state.episodes,
            allowedSubscriptionIDs: allowedSubscriptionIDs
        )
    }

    private var activeChips: [HomeActiveFilterChip] {
        HomeActiveFilters.chips(
            filter: filter,
            categoryID: selectedCategoryID,
            categoryName: { store.category(id: $0)?.name }
        )
    }

    private var shouldShowFeaturedSection: Bool {
        let bundle = picksService.bundle(for: selectedCategoryID)
        return !scopedResumeEpisodes.isEmpty
            || !bundle.picks.isEmpty
            || picksService.isRefreshing(for: selectedCategoryID)
    }

    private func dismissChip(_ chip: HomeActiveFilterChip) {
        switch chip.kind {
        case .libraryFilter: filter = .all
        case .category:      categoryFilterID = ""
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button {
                Haptics.light()
                showCategoryPicker = true
            } label: {
                HStack(spacing: 3) {
                    Text(navBarTitle)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Browse categories")
            .accessibilityHint("Opens category picker")
        }
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
        // the next turn instead of waiting on the 6h TTL. We blow every
        // cached category slot away so each section recurates on first
        // visit; the active section gets its refresh triggered now.
        picksService.invalidate()
        picksService.ensureFreshPicks(store: store, category: activeCategory)
    }
}
