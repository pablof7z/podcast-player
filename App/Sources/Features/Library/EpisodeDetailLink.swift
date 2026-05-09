import SwiftUI

// MARK: - LibraryEpisodeRoute

/// Navigation value pushed onto the show-detail `NavigationStack` when
/// the user taps an episode row. Encapsulating the route as a value type
/// (rather than a hard `NavigationLink(destination:)`) keeps the show-list
/// surface decoupled from `EpisodeDetailView`'s internal init.
struct LibraryEpisodeRoute: Hashable {
    let episodeID: UUID
    let subscriptionID: UUID
    let title: String
}

// MARK: - EpisodeDetailLink

/// Tap-row → push-route helper. A button shaped like a list cell content
/// container that pushes a `LibraryEpisodeRoute` onto the enclosing
/// `NavigationStack` via a binding.
struct EpisodeDetailLink<Label: View>: View {
    let route: LibraryEpisodeRoute
    @ViewBuilder let label: () -> Label

    var body: some View {
        NavigationLink(value: route) {
            label()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - EpisodeDetailViewStub

/// Bridge between Library's `LibraryEpisodeRoute` and the real
/// `EpisodeDetailView`. Library still holds the `navigationDestination` for
/// `LibraryEpisodeRoute` and renders this view; this view forwards into the
/// real episode-detail surface using the route's `episodeID`.
///
/// The type name is preserved for source-compatibility with Library's
/// `ShowDetailView.navigationDestination(for:)` resolver.
struct EpisodeDetailViewStub: View {
    let route: LibraryEpisodeRoute

    var body: some View {
        EpisodeDetailView(episodeID: route.episodeID)
    }
}
