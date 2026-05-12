import Foundation

// MARK: - Subscription sorting (recency)

extension AppStateStore {

    /// Subscriptions sorted by their most-recent-episode `pubDate`, descending.
    ///
    /// Designed for the merged Home subscription list — the user wants to see
    /// the feed that just published an episode at the top, not the one whose
    /// title happens to start with "A". Subscriptions with no known episode
    /// yet (fresh import, before the first feed fetch) sink to the bottom and
    /// fall back to alphabetical order so the list never collapses to a
    /// random arrangement.
    ///
    /// O(N log N) on the subscription count. Per-show recency is read from
    /// the precomputed `episodeIndexesByShow` projection — `.first` of that
    /// array is the newest-pubDate episode index, so the recency lookup is
    /// O(1) per show. We do NOT walk `state.episodes` here; the projection
    /// is the source of truth that keeps `LibraryGridCell`'s body O(1) too.
    var sortedSubscriptionsByRecency: [PodcastSubscription] {
        let subs = state.subscriptions.filter { !$0.isAgentGenerated && !$0.isExternalPlayback }
        let episodes = state.episodes
        // Memoize the recency-date lookup so the comparator is O(1) per
        // comparison instead of re-resolving the projection inside the sort.
        var lookup: [UUID: Date] = [:]
        lookup.reserveCapacity(subs.count)
        for sub in subs {
            if let firstIdx = episodeIndexesByShow[sub.id]?.first,
               episodes.indices.contains(firstIdx) {
                lookup[sub.id] = episodes[firstIdx].pubDate
            }
        }
        return subs.sorted { lhs, rhs in
            switch (lookup[lhs.id], lookup[rhs.id]) {
            case let (l?, r?):
                if l == r {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return l > r
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    /// Most-recent episode for `subscriptionID`, or `nil` when the show has
    /// no episodes yet. Mirrors the recency lookup used by
    /// `sortedSubscriptionsByRecency` so the row preview and the row's sort
    /// key always agree.
    func mostRecentEpisode(forSubscription subscriptionID: UUID) -> Episode? {
        guard let firstIdx = episodeIndexesByShow[subscriptionID]?.first,
              state.episodes.indices.contains(firstIdx) else { return nil }
        return state.episodes[firstIdx]
    }
}
