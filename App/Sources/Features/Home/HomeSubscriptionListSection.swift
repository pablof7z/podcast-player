import SwiftUI

// MARK: - HomeSubscriptionListSection

/// The subscription surface beneath the featured rail. Renders as a vertical
/// list, recency-sorted, honouring the active LibraryFilter + category filter
/// the parent owns.
struct HomeSubscriptionListSection: View {
    let podcasts: [Podcast]
    let now: Date
    let onRequestUnsubscribe: (Podcast) -> Void

    @Environment(AppStateStore.self) private var store

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(podcasts) { sub in
                HomeSubscriptionRow(
                    podcast: sub,
                    mostRecentEpisode: store.mostRecentEpisode(forPodcast: sub.id),
                    unplayedCount: store.unplayedCount(forPodcast: sub.id),
                    now: now,
                    onRequestUnsubscribe: { onRequestUnsubscribe(sub) }
                )
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                Divider()
                    .background(AppTheme.Tint.hairline)
                    .padding(.leading, AppTheme.Spacing.md + 46 + AppTheme.Spacing.md)
            }
        }
    }
}
