import Foundation

// MARK: - LivePodcastInventoryAdapter
//
// Concrete `PodcastInventoryProtocol` implementation backed by `AppStateStore`.
// All four list methods are pure reads off `state` plus a sort, so this stays
// allocation-light even on libraries with thousands of episodes.
//
// Constructed once per `AgentChatSession` (via `LivePodcastAgentToolDeps.make`)
// with a weak reference to the store so the adapter never extends the store's
// lifetime.

@MainActor
final class LivePodcastInventoryAdapter: PodcastInventoryProtocol, @unchecked Sendable {

    private weak var store: AppStateStore?

    init(store: AppStateStore) {
        self.store = store
    }

    // MARK: - PodcastInventoryProtocol

    func listSubscriptions(limit: Int) async -> [SubscriptionSummary] {
        await MainActor.run { listSubscriptionsSync(limit: limit) }
    }

    func listEpisodes(podcastID: PodcastID, limit: Int) async -> [EpisodeInventoryRow]? {
        await MainActor.run { listEpisodesSync(podcastID: podcastID, limit: limit) }
    }

    func listInProgress(limit: Int) async -> [EpisodeInventoryRow] {
        await MainActor.run { listInProgressSync(limit: limit) }
    }

    func listRecentUnplayed(limit: Int) async -> [EpisodeInventoryRow] {
        await MainActor.run { listRecentUnplayedSync(limit: limit) }
    }

    // MARK: - MainActor reads

    private func listSubscriptionsSync(limit: Int) -> [SubscriptionSummary] {
        guard let store else { return [] }
        let sorted = store.sortedSubscriptions
        let bounded = Array(sorted.prefix(limit))
        return bounded.map { sub in
            let eps = store.episodes(forSubscription: sub.id)
            let unplayed = eps.filter { !$0.played }.count
            let lastPub = eps.first?.pubDate  // already sorted newest-first
            return SubscriptionSummary(
                podcastID: sub.id.uuidString,
                title: sub.title,
                author: sub.author.isEmpty ? nil : sub.author,
                totalEpisodes: eps.count,
                unplayedEpisodes: unplayed,
                lastPublishedAt: lastPub
            )
        }
    }

    private func listEpisodesSync(podcastID: PodcastID, limit: Int) -> [EpisodeInventoryRow]? {
        guard let store, let uuid = UUID(uuidString: podcastID),
              let sub = store.subscription(id: uuid)
        else { return nil }
        let episodes = store.episodes(forSubscription: uuid).prefix(limit)
        return episodes.map { ep in
            inventoryRow(episode: ep, subscriptionTitle: sub.title)
        }
    }

    private func listInProgressSync(limit: Int) -> [EpisodeInventoryRow] {
        guard let store else { return [] }
        let titlesByID = Dictionary(uniqueKeysWithValues: store.state.subscriptions.map { ($0.id, $0.title) })
        let inProgress = store.inProgressEpisodes.prefix(limit)
        return inProgress.map { ep in
            inventoryRow(
                episode: ep,
                subscriptionTitle: titlesByID[ep.subscriptionID] ?? ""
            )
        }
    }

    private func listRecentUnplayedSync(limit: Int) -> [EpisodeInventoryRow] {
        guard let store else { return [] }
        let titlesByID = Dictionary(uniqueKeysWithValues: store.state.subscriptions.map { ($0.id, $0.title) })
        // `recentEpisodes(limit:)` filters to !played; further filter to
        // position == 0 so this surface is *strictly new*, not partial —
        // the in-progress list already covers half-listened episodes.
        let recent = store.recentEpisodes(limit: limit * 2)
            .filter { $0.playbackPosition == 0 }
            .prefix(limit)
        return recent.map { ep in
            inventoryRow(
                episode: ep,
                subscriptionTitle: titlesByID[ep.subscriptionID] ?? ""
            )
        }
    }

    // MARK: - Helpers

    private func inventoryRow(episode ep: Episode, subscriptionTitle: String) -> EpisodeInventoryRow {
        EpisodeInventoryRow(
            episodeID: ep.id.uuidString,
            podcastID: ep.subscriptionID.uuidString,
            title: ep.title,
            podcastTitle: subscriptionTitle,
            publishedAt: ep.pubDate,
            durationSeconds: ep.duration.map { Int($0) },
            played: ep.played,
            playbackPositionSeconds: ep.playbackPosition,
            isInProgress: !ep.played && ep.playbackPosition > 0
        )
    }
}
