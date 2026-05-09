import Foundation

// MARK: - Podcast subscriptions

extension AppStateStore {

    /// All subscribed podcasts, sorted alphabetically by title.
    var sortedSubscriptions: [PodcastSubscription] {
        state.subscriptions.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    /// Returns the live subscription record matching `id`, or `nil` when not found.
    func subscription(id: UUID) -> PodcastSubscription? {
        state.subscriptions.first { $0.id == id }
    }

    /// Returns the live subscription record whose feed URL matches the input,
    /// case-insensitive on host so trailing-slash and scheme-case differences
    /// don't create duplicates.
    func subscription(feedURL: URL) -> PodcastSubscription? {
        state.subscriptions.first { $0.feedURL.absoluteString.caseInsensitiveCompare(feedURL.absoluteString) == .orderedSame }
    }

    /// Inserts a brand-new subscription (no episodes yet). Returns `false` if a
    /// subscription with the same feed URL already exists; the caller can then
    /// call refresh on the existing one instead.
    @discardableResult
    func addSubscription(_ newSubscription: PodcastSubscription) -> Bool {
        guard subscription(feedURL: newSubscription.feedURL) == nil else { return false }
        state.subscriptions.append(newSubscription)
        return true
    }

    /// Replaces the subscription whose `id` matches `updated.id`. Used after
    /// a feed refresh to write back the new ETag / Last-Modified / metadata.
    func updateSubscription(_ updated: PodcastSubscription) {
        guard let idx = state.subscriptions.firstIndex(where: { $0.id == updated.id }) else { return }
        state.subscriptions[idx] = updated
    }

    /// Removes the subscription and every episode that referenced it.
    func removeSubscription(_ id: UUID) {
        state.subscriptions.removeAll { $0.id == id }
        state.episodes.removeAll { $0.subscriptionID == id }
    }

    /// Toggles whether new-episode notifications fire for the subscription.
    func setSubscriptionNotificationsEnabled(_ id: UUID, enabled: Bool) {
        guard let idx = state.subscriptions.firstIndex(where: { $0.id == id }) else { return }
        state.subscriptions[idx].notificationsEnabled = enabled
    }
}
