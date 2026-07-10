import SwiftUI

// MARK: - AllPodcastsListView

/// Full-screen list of every podcast the app knows about — including
/// podcasts the user does NOT follow (e.g. shows attached to an external
/// episode the agent played, or an OPML row that was imported and later
/// unfollowed but whose episodes remain).
///
/// Use:
///   - Tap a row → push `ShowDetailView` for that podcast.
///   - Swipe trailing → "Delete" destructive action that removes the
///     podcast row, any follow row, and every episode that belonged to it.
struct AllPodcastsListView: View {

    @Environment(AppStateStore.self) private var store
    @State private var pendingDelete: Podcast?
    @State private var searchText: String = ""
    @State private var showAddShowSheet: Bool = false

    /// `rustAllPodcasts`, `LibraryPodcastStatsProjection.load`, and
    /// `rustIsAlreadySubscribed` are all FFI round trips whose Rust side
    /// scans the whole library (`nmp_app_podcast_library_all_podcasts` /
    /// `..._library_podcast_stats` / `..._library_subscription_status`, each
    /// iterating `store.all_podcasts()`). `body` used to rebuild `libraryStats`
    /// on every render, `podcasts`/`filteredPodcasts` were plain computed
    /// properties (re-run on every keystroke AND every unrelated re-render),
    /// and `rustIsAlreadySubscribed` was called once PER ROW PER RENDER —
    /// O(N²) for N visible rows. Same bug class as `HomeView`'s fixed
    /// projections (#755 follow-up). Cached behind `@State` + `.task(id:)`;
    /// the followed-set membership check is now a single O(followed) call
    /// building a `Set<UUID>`, then an O(1) `.contains` per row instead of an
    /// O(library) FFI round trip per row.
    @State private var cachedPodcasts: [Podcast] = []
    @State private var cachedFilteredPodcasts: [Podcast] = []
    @State private var cachedLibraryStats = LibraryPodcastStatsProjection(
        episodeCounts: [:], unplayedCounts: [:], downloadedPodcastIDs: [],
        transcribedPodcastIDs: [], latestEpisodeIDs: [:]
    )
    @State private var cachedFollowedPodcastIDs: Set<UUID> = []

    private struct PodcastsKey: Equatable {
        var snapshotRev: Int?
    }

    private var podcastsKey: PodcastsKey {
        PodcastsKey(snapshotRev: store.kernel?.podcastSnapshot?.rev)
    }

    private struct FilteredPodcastsKey: Equatable {
        var searchText: String
        var snapshotRev: Int?
    }

    private var filteredPodcastsKey: FilteredPodcastsKey {
        FilteredPodcastsKey(searchText: searchText, snapshotRev: store.kernel?.podcastSnapshot?.rev)
    }

    var body: some View {
        List {
            if filteredPodcasts.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No podcasts yet" : "No matches",
                    systemImage: searchText.isEmpty ? "antenna.radiowaves.left.and.right" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                        ? "Subscribe to a show or play an episode to start your library."
                        : "Try a different search.")
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredPodcasts) { podcast in
                    NavigationLink(value: podcast) {
                        row(for: podcast)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Haptics.warning()
                            pendingDelete = podcast
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("All Podcasts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.light()
                    showAddShowSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add show")
            }
        }
        .sheet(isPresented: $showAddShowSheet) {
            AddShowSheet(store: store, onDismiss: { showAddShowSheet = false })
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search podcasts"
        )
        .alert(
            "Delete podcast",
            isPresented: pendingDeleteBinding,
            presenting: pendingDelete
        ) { podcast in
            Button("Delete", role: .destructive) {
                store.deletePodcast(podcastID: podcast.id)
                Haptics.success()
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { podcast in
            let episodes = cachedLibraryStats.episodeCount(for: podcast.id)
            let count = episodes == 1 ? "1 episode" : "\(episodes) episodes"
            Text("This removes \(podcast.title.isEmpty ? "the podcast" : podcast.title) and \(count) from your library. This cannot be undone.")
        }
        .task(id: podcastsKey) {
            let all = await store.rustAllPodcastsOffMain()
            cachedPodcasts = all
            cachedLibraryStats = await LibraryPodcastStatsProjection.loadOffMain(
                podcastIDs: all.map(\.id), store: store
            )
            cachedFollowedPodcastIDs = Set(await store.rustFollowedPodcastsOffMain().map(\.id))
        }
        .task(id: filteredPodcastsKey) {
            cachedFilteredPodcasts = await store.rustAllPodcastsOffMain(query: searchText)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for podcast: Podcast) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            artwork(for: podcast)
            VStack(alignment: .leading, spacing: 2) {
                Text(podcast.title.isEmpty ? (podcast.feedURL?.host ?? "Untitled") : podcast.title)
                    .font(AppTheme.Typography.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                metaLine(for: podcast)
            }
            Spacer(minLength: 0)
            if cachedFollowedPodcastIDs.contains(podcast.id) {
                Text("Following")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppTheme.Spacing.xs)
                    .padding(.vertical, 2)
                    .background(Color(.tertiarySystemFill), in: Capsule(style: .continuous))
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func artwork(for podcast: Podcast) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.Corner.sm, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            podcast.accentColor.opacity(0.9),
                            podcast.accentColor.opacity(0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            if let url = podcast.imageURL {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 88, height: 88)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholderGlyph(for: podcast)
                    }
                }
            } else {
                placeholderGlyph(for: podcast)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.sm, style: .continuous))
    }

    private func placeholderGlyph(for podcast: Podcast) -> some View {
        Image(systemName: podcast.artworkSymbol)
            .font(.system(size: 18, weight: .light))
            .foregroundStyle(.white.opacity(0.92))
    }

    private func metaLine(for podcast: Podcast) -> some View {
        let count = cachedLibraryStats.episodeCount(for: podcast.id)
        let countLabel = count == 1 ? "1 episode" : "\(count) episodes"
        var parts: [String] = [countLabel]
        if !podcast.author.isEmpty { parts.append(podcast.author) }
        return Text(parts.joined(separator: " · "))
            .font(AppTheme.Typography.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    // MARK: - Data

    /// All podcasts excluding the built-in Unknown sentinel (it's an
    /// implementation detail of the agent's external-play fallback —
    /// surfacing it in this list would invite the user to delete the
    /// fallback row and break subsequent external plays).
    private var podcasts: [Podcast] { cachedPodcasts }

    private var filteredPodcasts: [Podcast] { cachedFilteredPodcasts }

    private var pendingDeleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }
}
