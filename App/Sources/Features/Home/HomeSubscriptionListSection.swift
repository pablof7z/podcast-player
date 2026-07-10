import SwiftUI

// MARK: - HomeSubscriptionListSection

/// The subscription surface beneath the featured rail. Renders as a vertical
/// list of followed podcasts, recency-sorted, honouring the active
/// LibraryFilter + category filter the parent owns.
///
/// The header carries a "See all" affordance that pushes
/// `AllPodcastsListView` — a separate screen that lists every known
/// podcast (followed AND unfollowed) with swipe-to-delete. Home keeps
/// showing only followed shows so the everyday surface stays focused on
/// what the user actually follows.
struct HomeSubscriptionListSection: View {
    let podcasts: [Podcast]
    let now: Date
    let onRequestUnsubscribe: (Podcast) -> Void
    let onSeeAllPodcasts: () -> Void

    @Environment(AppStateStore.self) private var store

    /// `LibraryPodcastStatsProjection.load` is an FFI round trip whose Rust
    /// side (`nmp_app_podcast_library_podcast_stats`) scans the whole
    /// library. This section renders on the default Home screen with no
    /// navigation gate, so an uncached call here re-runs on every SwiftUI
    /// body pass — a main-thread `sample` on a real ~2k-episode library
    /// caught this class of bug pegging the main thread (#755 follow-up;
    /// same pattern already fixed on `HomeView` itself). Cached behind
    /// `@State` + `.task(id:)`, keyed by `podcasts` (already cached one
    /// level up as `HomeView.filteredSubs`) plus the snapshot rev so a new
    /// episode landing still refreshes "most recent episode" per row.
    @State private var cachedLibraryStats = LibraryPodcastStatsProjection(
        episodeCounts: [:], unplayedCounts: [:], downloadedPodcastIDs: [],
        transcribedPodcastIDs: [], latestEpisodeIDs: [:]
    )

    private struct LibraryStatsKey: Equatable {
        var podcasts: [Podcast]
        var snapshotRev: Int?
    }

    private var libraryStatsKey: LibraryStatsKey {
        LibraryStatsKey(podcasts: podcasts, snapshotRev: store.kernel?.podcastSnapshot?.rev)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            rowList
        }
        .task(id: libraryStatsKey) {
            cachedLibraryStats = await LibraryPodcastStatsProjection.loadOffMain(
                podcastIDs: podcasts.map(\.id), store: store
            )
        }
    }

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text("Podcasts")
                .font(AppTheme.Typography.title3)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Button(action: {
                Haptics.selection()
                onSeeAllPodcasts()
            }) {
                Text("See All")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See all podcasts")
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.bottom, AppTheme.Spacing.xs)
    }

    private var rowList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(podcasts) { sub in
                HomeSubscriptionRow(
                    podcast: sub,
                    mostRecentEpisode: cachedLibraryStats.latestEpisode(for: sub.id, store: store),
                    now: now,
                    onRequestUnsubscribe: { onRequestUnsubscribe(sub) }
                )
                .accessibilityIdentifier("library-podcast-row")
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                Divider()
                    .background(AppTheme.Tint.hairline)
                    .padding(.leading, AppTheme.Spacing.md + 53 + AppTheme.Spacing.md)
            }
        }
        .accessibilityIdentifier("library-podcast-list")
    }
}
