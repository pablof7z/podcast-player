import Foundation

struct SubscriptionImportPayload: Sendable {
    let subscription: PodcastSubscription
    let episodes: [Episode]
}

struct SubscriptionImportResult: Sendable, Equatable {
    let imported: Int
    let skipped: Int
}

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

    /// Adds a batch of fetched OPML/import results with one state assignment.
    /// Historical backlog episodes are stored but not auto-downloaded; the
    /// per-show auto-download policy applies to future refreshes.
    @discardableResult
    func addSubscriptions(_ payloads: [SubscriptionImportPayload]) -> SubscriptionImportResult {
        guard !payloads.isEmpty else {
            return SubscriptionImportResult(imported: 0, skipped: 0)
        }

        var next = state
        var knownFeedURLs = Set(next.subscriptions.map { Self.feedURLKey($0.feedURL) })
        var imported = 0
        var skipped = 0

        next.subscriptions.reserveCapacity(next.subscriptions.count + payloads.count)
        next.episodes.reserveCapacity(next.episodes.count + payloads.reduce(0) { $0 + $1.episodes.count })

        for payload in payloads {
            let key = Self.feedURLKey(payload.subscription.feedURL)
            guard knownFeedURLs.insert(key).inserted else {
                skipped += 1
                continue
            }

            next.subscriptions.append(payload.subscription)
            next.episodes.append(contentsOf: payload.episodes)
            imported += 1
        }

        guard imported > 0 else {
            return SubscriptionImportResult(imported: imported, skipped: skipped)
        }

        performMutationBatch {
            state = next
        }

        return SubscriptionImportResult(imported: imported, skipped: skipped)
    }

    /// Replaces the subscription whose `id` matches `updated.id`. Used after
    /// a feed refresh to write back the new ETag / Last-Modified / metadata.
    func updateSubscription(_ updated: PodcastSubscription) {
        guard let idx = state.subscriptions.firstIndex(where: { $0.id == updated.id }) else { return }
        state.subscriptions[idx] = updated
    }

    /// Removes the subscription and every episode that referenced it.
    func removeSubscription(_ id: UUID) {
        var next = state
        next.subscriptions.removeAll { $0.id == id }
        next.episodes.removeAll { $0.subscriptionID == id }
        performMutationBatch {
            state = next
            // Drop the show from every projection immediately.
            invalidateEpisodeProjections()
        }
    }

    /// Toggles whether new-episode notifications fire for the subscription.
    func setSubscriptionNotificationsEnabled(_ id: UUID, enabled: Bool) {
        guard let idx = state.subscriptions.firstIndex(where: { $0.id == id }) else { return }
        state.subscriptions[idx].notificationsEnabled = enabled
    }

    /// Replaces the per-subscription auto-download policy. The download
    /// service reads this directly when `evaluateAutoDownload` runs after a
    /// feed refresh — no separate reschedule is needed because already-fired
    /// downloads keep going regardless of subsequent policy changes.
    func setSubscriptionAutoDownload(_ id: UUID, policy: AutoDownloadPolicy) {
        guard let idx = state.subscriptions.firstIndex(where: { $0.id == id }) else { return }
        state.subscriptions[idx].autoDownload = policy
    }

    private static func feedURLKey(_ url: URL) -> String {
        url.absoluteString.lowercased()
    }
}
