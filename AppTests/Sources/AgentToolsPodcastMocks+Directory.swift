import Foundation
@testable import Podcastr

// MARK: - Directory + Subscribe mocks
//
// Pulled out of `AgentToolsPodcastMocks.swift` to keep that file under the
// 500-line hard limit set by `AGENTS.md`. These two mocks back the iTunes
// directory lookup and the `subscribe_podcast` / `ensurePodcast` adapters
// used by `list_episodes`'s external-input paths.

actor MockDirectory: PodcastDirectoryProtocol {
    /// Map of collection_id → feed_url for `lookupFeedURL`. nil ⇒ "not found".
    private var feedURLByCollectionID: [String: String] = [:]
    private var lookupError: Error?
    private(set) var lookupCalls: [String] = []

    init(feedURLByCollectionID: [String: String] = [:], lookupError: Error? = nil) {
        self.feedURLByCollectionID = feedURLByCollectionID
        self.lookupError = lookupError
    }

    func setFeedURL(_ feedURL: String?, forCollectionID id: String) {
        if let feedURL { feedURLByCollectionID[id] = feedURL }
        else { feedURLByCollectionID.removeValue(forKey: id) }
    }

    func setLookupError(_ error: Error?) {
        lookupError = error
    }

    func searchDirectory(
        query: String,
        type: PodcastDirectorySearchType,
        limit: Int
    ) async throws -> [PodcastDirectoryHit] {
        return []
    }

    func lookupFeedURL(forCollectionID collectionID: String) async throws -> String? {
        lookupCalls.append(collectionID)
        if let lookupError { throw lookupError }
        return feedURLByCollectionID[collectionID]
    }
}

actor MockSubscribe: PodcastSubscribeProtocol {
    /// Per-feed-URL canned response for `ensurePodcast`. Used by the
    /// `list_episodes` external-input tests so the test author can pin the
    /// resolved podcast_id to a value the inventory mock has episodes for.
    private var ensureResults: [String: PodcastEnsureResult] = [:]
    private var ensureError: Error?
    private(set) var ensureCalls: [String] = []

    /// Per-feed-URL canned response for `subscribe`.
    private var subscribeResults: [String: PodcastSubscribeResult] = [:]
    private(set) var subscribeCalls: [String] = []

    init(
        ensureResults: [String: PodcastEnsureResult] = [:],
        ensureError: Error? = nil
    ) {
        self.ensureResults = ensureResults
        self.ensureError = ensureError
    }

    func setEnsureResult(_ result: PodcastEnsureResult, forFeedURL feedURL: String) {
        ensureResults[feedURL] = result
    }

    func setEnsureError(_ error: Error?) {
        ensureError = error
    }

    func subscribe(feedURLString: String) async throws -> PodcastSubscribeResult {
        subscribeCalls.append(feedURLString)
        if let canned = subscribeResults[feedURLString] {
            return canned
        }
        return PodcastSubscribeResult(
            podcastID: "mock-pod",
            title: "Mock Show",
            feedURL: feedURLString,
            episodeCount: 0,
            alreadySubscribed: false
        )
    }

    func ensurePodcast(feedURLString: String) async throws -> PodcastEnsureResult {
        ensureCalls.append(feedURLString)
        if let ensureError { throw ensureError }
        if let canned = ensureResults[feedURLString] {
            return canned
        }
        return PodcastEnsureResult(
            podcastID: "mock-ensured-pod",
            title: "Mock Ensured Show",
            feedURL: feedURLString,
            episodeCount: 0
        )
    }

    private(set) var deleteCalls: [PodcastID] = []
    private var deleteResults: [PodcastID: PodcastDeleteResult] = [:]
    private var deleteError: Error?

    func setDeleteResult(_ result: PodcastDeleteResult, forPodcastID podcastID: PodcastID) {
        deleteResults[podcastID] = result
    }

    func setDeleteError(_ error: Error?) {
        deleteError = error
    }

    func deletePodcast(podcastID: PodcastID) async throws -> PodcastDeleteResult {
        deleteCalls.append(podcastID)
        if let deleteError { throw deleteError }
        if let canned = deleteResults[podcastID] { return canned }
        return PodcastDeleteResult(
            podcastID: podcastID,
            title: "Mock Show",
            wasSubscribed: true,
            episodesDeleted: 0
        )
    }
}
