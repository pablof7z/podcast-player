import SwiftUI

// MARK: - HomeSubscriptionListSection

/// The subscription surface beneath the featured rail. Renders either as
/// a vertical list (default) or as the legacy grid when the user opts in
/// from the toolbar menu. Both variants honour the active `LibraryFilter`
/// + category filter the parent owns; recency sorting is always on.
struct HomeSubscriptionListSection: View {
    let subscriptions: [PodcastSubscription]
    let layout: HomeSubscriptionLayout
    let now: Date
    let onRequestUnsubscribe: (PodcastSubscription) -> Void

    @Environment(AppStateStore.self) private var store

    var body: some View {
        switch layout {
        case .list:
            list
        case .grid:
            grid
        }
    }

    // MARK: - List variant

    private var list: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(subscriptions) { sub in
                HomeSubscriptionRow(
                    subscription: sub,
                    mostRecentEpisode: store.mostRecentEpisode(forSubscription: sub.id),
                    unplayedCount: store.unplayedCount(forSubscription: sub.id),
                    now: now,
                    onRequestUnsubscribe: { onRequestUnsubscribe(sub) }
                )
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                Divider()
                    .background(AppTheme.Tint.hairline)
                    .padding(.leading, AppTheme.Spacing.md + 40 + AppTheme.Spacing.md)
            }
        }
    }

    // MARK: - Grid variant (legacy)

    private var grid: some View {
        LazyVGrid(columns: gridColumns, spacing: AppTheme.Spacing.lg) {
            ForEach(subscriptions) { sub in
                NavigationLink(value: sub) {
                    LibraryGridCell(
                        subscription: sub,
                        unplayedCount: store.unplayedCount(forSubscription: sub.id),
                        category: store.category(forSubscription: sub.id)
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    SubscriptionContextMenu(
                        subscription: sub,
                        onRequestUnsubscribe: { onRequestUnsubscribe(sub) }
                    )
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: AppTheme.Spacing.lg)]
    }
}
