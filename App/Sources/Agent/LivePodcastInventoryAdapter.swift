import Foundation

// MARK: - LivePodcastInventoryAdapter
//
// Concrete inventory/category implementation backed by `AppStateStore`.
// Most methods are pure reads off `state` plus a sort, so this stays
// allocation-light even on libraries with thousands of episodes.
//
// Constructed once per `AgentChatSession` (via `LivePodcastAgentToolDeps.make`)
// with a weak reference to the store so the adapter never extends the store's
// lifetime.

@MainActor
final class LivePodcastInventoryAdapter: PodcastInventoryProtocol, PodcastCategoryProtocol, @unchecked Sendable {

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

    // MARK: - PodcastCategoryProtocol

    func listCategories(limit: Int, includePodcasts: Bool) async -> [PodcastCategorySummary] {
        await MainActor.run {
            listCategoriesSync(limit: limit, includePodcasts: includePodcasts)
        }
    }

    func changePodcastCategory(
        podcastID: PodcastID,
        category reference: PodcastCategoryReference
    ) async throws -> PodcastCategoryChangeResult {
        try await MainActor.run {
            try changePodcastCategorySync(podcastID: podcastID, category: reference)
        }
    }

    // MARK: - MainActor reads

    private func listSubscriptionsSync(limit: Int) -> [SubscriptionSummary] {
        guard let store else { return [] }
        let sorted = store.sortedSubscriptions.filter { !$0.isAgentGenerated }
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

    private func listCategoriesSync(limit: Int, includePodcasts: Bool) -> [PodcastCategorySummary] {
        guard let store else { return [] }
        let subscriptionsByID = Dictionary(uniqueKeysWithValues: store.state.subscriptions.map { ($0.id, $0) })
        return store.state.categories.prefix(limit).map { category in
            let subscriptions = category.subscriptionIDs
                .compactMap { subscriptionsByID[$0] }
                .sorted { lhs, rhs in lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending }
            let rows = includePodcasts ? subscriptions.map(categorySubscriptionRow) : []
            return PodcastCategorySummary(
                categoryID: category.id.uuidString,
                name: category.name,
                slug: category.slug,
                description: category.description,
                colorHex: category.colorHex,
                subscriptionCount: subscriptions.count,
                generatedAt: category.generatedAt,
                model: category.model,
                subscriptions: rows
            )
        }
    }

    private func changePodcastCategorySync(
        podcastID: PodcastID,
        category reference: PodcastCategoryReference
    ) throws -> PodcastCategoryChangeResult {
        guard let store else {
            throw PodcastAgentToolAdapterError.unavailable("AppStateStore")
        }
        guard let podcastUUID = UUID(uuidString: podcastID) else {
            throw PodcastAgentToolAdapterError.invalidID(podcastID)
        }
        guard let subscription = store.subscription(id: podcastUUID) else {
            throw PodcastAgentToolAdapterError.missingPodcast(podcastID)
        }
        guard let target = resolveCategory(reference, categories: store.state.categories) else {
            throw PodcastCategoryAdapterError.missingCategory
        }

        let previous = store.category(forSubscription: podcastUUID)
        guard store.moveSubscription(podcastUUID, toCategory: target.id) else {
            throw PodcastCategoryAdapterError.moveFailed
        }
        let updated = store.category(id: target.id) ?? target
        return PodcastCategoryChangeResult(
            podcastID: podcastID,
            title: subscription.title,
            previousCategoryID: previous?.id.uuidString,
            previousCategoryName: previous?.name,
            categoryID: updated.id.uuidString,
            categoryName: updated.name,
            categorySlug: updated.slug
        )
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

    private func categorySubscriptionRow(_ sub: PodcastSubscription) -> CategorySubscriptionSummary {
        CategorySubscriptionSummary(
            podcastID: sub.id.uuidString,
            title: sub.title,
            author: sub.author.isEmpty ? nil : sub.author
        )
    }

    private func resolveCategory(
        _ reference: PodcastCategoryReference,
        categories: [PodcastCategory]
    ) -> PodcastCategory? {
        if let rawID = reference.id?.trimmed, let id = UUID(uuidString: rawID) {
            return categories.first(where: { $0.id == id })
        }
        if let slug = reference.slug?.trimmed.lowercased(), !slug.isEmpty {
            return categories.first(where: { $0.slug.lowercased() == slug })
        }
        if let name = reference.name?.trimmed.lowercased(), !name.isEmpty {
            return categories.first(where: { $0.name.lowercased() == name })
        }
        return nil
    }
}

private enum PodcastCategoryAdapterError: LocalizedError {
    case missingCategory
    case moveFailed

    var errorDescription: String? {
        switch self {
        case .missingCategory:
            return "Category not found. Use list_categories to choose an existing category ID, slug, or name."
        case .moveFailed:
            return "Could not move podcast into the requested category."
        }
    }
}
