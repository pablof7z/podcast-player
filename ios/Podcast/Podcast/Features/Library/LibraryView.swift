import SwiftUI

// MARK: - LibraryView

/// Top-level Library tab. Shows a podcast grid; tapping a cell pushes
/// `ShowDetailView` through the NavigationStack.
struct LibraryView: View {
    @Environment(AppStateStore.self) private var store
    @Environment(PlaybackState.self) private var playback

    @State private var showAddSheet = false
    @State private var voiceOverDetailRoute: LibraryEpisodeRoute?

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: AppTheme.Spacing.md)]

    var body: some View {
        NavigationStack {
            Group {
                if store.allPodcasts.isEmpty {
                    emptyState
                } else {
                    podcastGrid
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: Podcast.self) { podcast in
                ShowDetailView(podcast: podcast)
            }
            .navigationDestination(for: LibraryEpisodeRoute.self) { route in
                LibraryEpisodePlaceholder(route: route)
            }
            .navigationDestination(item: $voiceOverDetailRoute) { route in
                LibraryEpisodePlaceholder(route: route)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddShowSheet(store: store, onDismiss: { showAddSheet = false })
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Podcasts Yet",
            systemImage: "headphones",
            description: Text("Tap + to add a show.")
        )
    }

    private var podcastGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.md) {
                ForEach(store.allPodcasts) { podcast in
                    NavigationLink(value: podcast) {
                        LibraryGridCell(
                            podcast: podcast,
                            unplayedCount: store.unplayedCount(forPodcast: podcast.id)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(AppTheme.Spacing.md)
        }
    }
}
