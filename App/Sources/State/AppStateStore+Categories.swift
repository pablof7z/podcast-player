import Foundation

// MARK: - Podcast categories

extension AppStateStore {

    /// Replaces the current set of LLM-derived categories.
    ///
    /// Single-write entry-point so the `state.didSet` save fires once per
    /// recompute, regardless of how many categories the model returned.
    func setCategories(_ categories: [PodcastCategory]) {
        state.categories = categories
    }

    /// Returns the category with the given ID, if any.
    func category(id: UUID) -> PodcastCategory? {
        state.categories.first(where: { $0.id == id })
    }

    /// Returns the (first) category that contains the given subscription.
    ///
    /// Validation in `PodcastCategorizationService` guarantees each
    /// subscription appears in exactly one category at write time, so the
    /// "first" match is also the only match. Linear scan is fine here:
    /// category counts are tiny (6-12 by spec) compared to the per-show
    /// dictionaries the projections cache builds.
    func category(forSubscription subscriptionID: UUID) -> PodcastCategory? {
        state.categories.first(where: { $0.subscriptionIDs.contains(subscriptionID) })
    }
}
