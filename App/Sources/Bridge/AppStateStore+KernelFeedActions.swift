import Foundation

extension AppStateStore {
    /// Ensure a feed is known to the Rust kernel without following it.
    /// The kernel owns the fetch, podcast upsert and episode ingestion; Swift
    /// waits for the projected row instead of writing local podcast/episode
    /// state that a later projection could clobber.
    @discardableResult
    func kernelEnsurePodcast(
        feedURL: String,
        timeout: Duration = .seconds(30)
    ) async throws -> Podcast {
        guard let kern = kernel else {
            throw SubscriptionService.AddError.transport("Kernel not available")
        }
        let trimmed = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            throw SubscriptionService.AddError.invalidURL
        }

        let before = podcast(feedURL: url)
        let beforeRefreshedAt = before?.lastRefreshedAt
        kern.dispatch(PodcastKernelAction.EnsurePodcast(feedUrl: trimmed))

        // React to the projected row appearing (or its refresh stamp advancing)
        // instead of polling on a 300ms timer. `podcast(feedURL:)` reads
        // `state.podcasts`, so the awaiter re-fires the instant
        // `applyKernelState` ingests the feed.
        if let current = await awaitState(timeout: timeout, body: { [weak self] () -> Podcast? in
            guard let current = self?.podcast(feedURL: url) else { return nil }
            if before == nil || current.lastRefreshedAt != beforeRefreshedAt {
                return current
            }
            return nil
        }) {
            return current
        }

        // Timeout: surface a present-but-unrefreshed row rather than erroring;
        // the refresh may still land.
        if let current = podcast(feedURL: url) {
            return current
        }
        throw SubscriptionService.AddError.transport(
            "Feed did not appear in library after \(timeout). It may still arrive.")
    }
}
