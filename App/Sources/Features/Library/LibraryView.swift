import SwiftUI

// MARK: - LibraryView

/// Root of the Library tab. Subscriptions grid + filter chips + a search-entry
/// bar that opens the dedicated podcast search surface.
///
/// **Glass usage in this file:**
///
///   - The category and filter rails are wrapped in structural glass containers.
///   - The search-entry bar is a structural glass capsule.
///   - All cards (`LibraryGridCell`) are matte.
struct LibraryView: View {

    /// Closure invoked when the user taps the search-entry bar. Defaults to
    /// a no-op so the view is constructible in any container.
    var onOpenSearch: () -> Void = { Haptics.light() }

    @Environment(AppStateStore.self) private var store
    /// Persisted across cold launches via `@AppStorage` so the user's
    /// filter preference (e.g. "I always want to see Unplayed first")
    /// sticks. Backed by `LibraryFilter`'s `RawRepresentable: String`
    /// conformance so the value round-trips through UserDefaults as the
    /// case rawValue. Falls back to `.all` for a fresh install or when
    /// the stored string doesn't match a known case (e.g. after a rename).
    @AppStorage("library.filter") private var filter: LibraryFilter = .all
    @AppStorage("library.categoryFilterID") private var categoryFilterID: String = ""
    @State private var showAddShowSheet: Bool = false
    /// Set when the user picks "Unsubscribe" from a grid cell's long-press
    /// context menu. The presented alert reads from this — clearing it
    /// dismisses the alert. Without the menu, unsubscribe was a 3-tap path
    /// (tile → ⓘ → Unsubscribe → confirm); now it's 2 taps.
    @State private var unsubscribeTarget: PodcastSubscription?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                searchEntryBar
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.top, AppTheme.Spacing.sm)

                continueListeningRail

                categoryRailContainer
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.top, AppTheme.Spacing.sm)

                filterRailContainer
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.top, AppTheme.Spacing.sm)

                if filteredSubs.isEmpty {
                    emptyState
                        .padding(.top, AppTheme.Spacing.xl)
                } else {
                    grid
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.top, AppTheme.Spacing.lg)
                        .padding(.bottom, AppTheme.Spacing.xl)
                }
            }
        }
        .navigationTitle("Library")
        .toolbar { toolbarContent }
        .background(Color(.systemBackground).ignoresSafeArea())
        .refreshable { await refreshAll() }
        .navigationDestination(for: PodcastSubscription.self) { sub in
            ShowDetailView(subscription: sub)
        }
        // Registered so the Continue Listening rail's cards can push the
        // shared Library episode detail. ShowDetailView registers the same
        // route on its own stack — both surfaces resolve consistently.
        .navigationDestination(for: LibraryEpisodeRoute.self) { route in
            LibraryEpisodePlaceholder(route: route)
        }
        .sheet(isPresented: $showAddShowSheet) {
            AddShowSheet(store: store, onDismiss: { showAddShowSheet = false })
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
    }

    // MARK: - Continue listening rail

    /// Shown only when the user has any in-progress episode. Sits above the
    /// filter rail so it doesn't interact with the Unplayed/Downloaded chip
    /// selection — the rail is a global resume affordance, not a filter
    /// projection.
    @ViewBuilder
    private var continueListeningRail: some View {
        let inProgress = store.inProgressEpisodes
        if !inProgress.isEmpty {
            LibraryContinueListeningRail(episodes: inProgress)
                .padding(.top, AppTheme.Spacing.lg)
        }
    }

    // MARK: - Filtering

    /// Applies the filter chip selection to the current subscription list.
    private var filteredSubs: [PodcastSubscription] {
        let all = categoryFilteredSubscriptions
        switch filter {
        case .all:
            return all
        case .unplayed:
            return all.filter { store.unplayedCount(forSubscription: $0.id) > 0 }
        case .downloaded:
            return all.filter { store.hasDownloadedEpisode(forSubscription: $0.id) }
        case .transcribed:
            return all.filter { store.hasTranscribedEpisode(forSubscription: $0.id) }
        }
    }

    private var selectedCategoryID: UUID? {
        guard let id = UUID(uuidString: categoryFilterID),
              store.category(id: id) != nil
        else { return nil }
        return id
    }

    private var selectedCategory: PodcastCategory? {
        selectedCategoryID.flatMap { store.category(id: $0) }
    }

    private var categorySelection: Binding<UUID?> {
        Binding(
            get: { selectedCategoryID },
            set: { categoryFilterID = $0?.uuidString ?? "" }
        )
    }

    private var categoryFilteredSubscriptions: [PodcastSubscription] {
        guard let selectedCategory else { return store.sortedSubscriptions }
        let ids = Set(selectedCategory.subscriptionIDs)
        return store.sortedSubscriptions.filter { ids.contains($0.id) }
    }

    private var categoryCounts: [UUID: Int] {
        let subscriptionIDs = Set(store.state.subscriptions.map(\.id))
        return Dictionary(uniqueKeysWithValues: store.state.categories.map { category in
            let count = category.subscriptionIDs.filter { subscriptionIDs.contains($0) }.count
            return (category.id, count)
        })
    }

    // MARK: - Search entry bar

    private var searchEntryBar: some View {
        Button {
            Haptics.light()
            onOpenSearch()
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.Tint.agentSurface)
                Text("Search your library…")
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
        .accessibilityLabel("Search your library")
        .accessibilityHint("Opens Search")
    }

    // MARK: - Filter rail

    @ViewBuilder
    private var categoryRailContainer: some View {
        if !store.state.categories.isEmpty {
            LibraryCategoryRail(
                categories: store.state.categories,
                counts: categoryCounts,
                selection: categorySelection
            )
            .glassEffect(.regular, in: .rect(cornerRadius: AppTheme.Corner.lg))
        }
    }

    private var filterRailContainer: some View {
        LibraryFilterRail(selection: $filter)
            .glassEffect(.regular, in: .capsule)
    }

    // MARK: - Grid

    private var grid: some View {
        LazyVGrid(columns: gridColumns, spacing: AppTheme.Spacing.lg) {
            ForEach(filteredSubs) { sub in
                NavigationLink(value: sub) {
                    LibraryGridCell(
                        subscription: sub,
                        unplayedCount: store.unplayedCount(forSubscription: sub.id),
                        category: store.category(forSubscription: sub.id)
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        Task { await SubscriptionService(store: store).refresh(sub) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        unsubscribeTarget = sub
                    } label: {
                        Label("Unsubscribe", systemImage: "minus.circle")
                    }
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: AppTheme.Spacing.lg)]
    }

    // MARK: - Empty state

    /// Distinguishes "the user genuinely has no subscriptions" from "the
    /// active filter happens to match nothing." Showing the fresh-user
    /// onboarding pitch ("Your shows live here. Search Apple Podcasts…")
    /// to a user with 44 subs and a Transcribed filter that nothing matches
    /// reads as if their library disappeared.
    @ViewBuilder
    private var emptyState: some View {
        if store.sortedSubscriptions.isEmpty {
            firstRunEmptyState
        } else {
            filteredEmptyState
        }
    }

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
                Text(filteredEmptyTitle)
                    .font(AppTheme.Typography.title)
                Text(filteredEmptySubtitle)
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

    private var filteredEmptyTitle: String {
        guard let selectedCategory else { return filter.emptyStateTitle }
        if filter == .all {
            return "No shows in \(selectedCategory.name)."
        }
        return "No \(filter.label.lowercased()) shows in \(selectedCategory.name)."
    }

    private var filteredEmptySubtitle: String {
        if selectedCategory != nil {
            return "Clear filters to see the rest of your categorized library."
        }
        return filter.emptyStateSubtitle
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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

    // MARK: - Refresh

    private func refreshAll() async {
        await SubscriptionService(store: store).refreshAll()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack { LibraryView() }
        .environment(AppStateStore())
}
