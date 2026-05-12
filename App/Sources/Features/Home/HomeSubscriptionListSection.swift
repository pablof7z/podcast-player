import SwiftUI

// MARK: - HomeSubscriptionListSection

/// The subscription surface beneath the featured rail. Renders as a vertical
/// list, recency-sorted, honouring the active LibraryFilter + category filter
/// the parent owns.
struct HomeSubscriptionListSection: View {
    let subscriptions: [PodcastSubscription]
    let now: Date
    let onRequestUnsubscribe: (PodcastSubscription) -> Void

    @Environment(AppStateStore.self) private var store

    var body: some View {
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
}
