import SwiftUI

// MARK: - LibraryEpisodeRoute

/// Navigation value pushed onto the show-detail `NavigationStack` when the
/// user taps an episode row. Encapsulating the route as a value type (rather
/// than a hard `NavigationLink(destination:)`) lets the EpisodeDetail agent
/// swap the `navigationDestination(for:)` resolver without touching this view.
struct LibraryEpisodeRoute: Hashable {
    let episodeID: UUID
    let subscriptionID: UUID
    let title: String
}

// MARK: - EpisodeDetailLink

/// Tap-row → push-route helper. A button shaped like a list cell content
/// container that pushes a `LibraryEpisodeRoute` onto the enclosing
/// `NavigationStack`.
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

// MARK: - LibraryEpisodePlaceholder

/// Minimal placeholder destination used by `ShowDetailView` until the
/// EpisodeDetail agent wires the real screen into the route resolver.
/// Keeps the navigation push verifiable end-to-end.
struct LibraryEpisodePlaceholder: View {
    let route: LibraryEpisodeRoute

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text(route.title)
                .font(AppTheme.Typography.largeTitle)
            Text("Episode detail will render here once it's wired in.")
                .font(AppTheme.Typography.body)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
