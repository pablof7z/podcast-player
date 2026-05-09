import SwiftUI

// MARK: - LibraryEpisodeRoute

/// Navigation value pushed onto the show-detail `NavigationStack` when
/// the user taps an episode row. Encapsulating the route as a value type
/// (rather than a hard `NavigationLink(destination:)`) is the seam Lane 5
/// uses to plug `EpisodeDetailView` in: the orchestrator changes the
/// `navigationDestination(for:)` resolver in `ShowDetailView` and the
/// stub goes away.
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

/// **Lane 5 owns the real `EpisodeDetailView`.** Until that lane lands,
/// this stub renders just enough to confirm the navigation push works
/// (title, episode meta, "owned by Lane 5" banner). At merge, the
/// orchestrator removes this file or replaces the body with the real
/// view's invocation; the route signature is the contract.
struct EpisodeDetailViewStub: View {
    let route: LibraryEpisodeRoute

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Episode")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(.secondary)
                Text(route.title)
                    .font(AppTheme.Typography.largeTitle)
            }

            Text("Lane 5 owns the real episode detail screen — transcript, chapters, clip-creation, wiki affordance. This is a placeholder so Lane 3 builds and the navigation push from the show detail can be tested independently.")
                .font(AppTheme.Typography.body)
                .foregroundStyle(.secondary)
                .padding(AppTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )

            Spacer(minLength: 0)
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Episode")
        .navigationBarTitleDisplayMode(.inline)
    }
}
