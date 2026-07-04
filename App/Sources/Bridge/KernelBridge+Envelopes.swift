import Foundation

// ─── iTunes / threading / local / home / carplay / library envelopes ─────

extension PodcastHandle {
    func itunesDirectorySearchEnvelope(query: String, type: String, limit: Int) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "query": query,
            "type": type,
            "limit": limit,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .itunesDirectorySearch, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func itunesLookupFeedEnvelope(collectionID: String) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload = ["collection_id": collectionID]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .itunesLookupFeedUrl, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func itunesTopPodcastsEnvelope(limit: Int, storefront: String) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "limit": limit,
            "storefront": storefront,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .itunesTopPodcasts, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func threadingProjectionEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = podcastAppString(handle, endpoint: .threadingProjection) else {
            return nil
        }
        return result
    }

    func threadingActiveTopicsEnvelope(limit: Int, podcastIDs: [UUID]) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "limit": limit,
            "podcast_ids": podcastIDs.map(\.uuidString),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .threadingActiveTopics, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func localSearchEnvelope(query: String, limit: Int) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "query": query,
            "limit": limit,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .localSearch, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func homeContinueListeningEnvelope(limit: Int, podcastIDs: [UUID]) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "limit": limit,
            "podcast_ids": podcastIDs.map(\.uuidString),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .homeContinueListening, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func homeTriageRollupEnvelope(podcastIDs: [UUID]) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "podcast_ids": podcastIDs.map(\.uuidString),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .homeTriageRollup, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func homeSubscriptionListEnvelope(filter: String, podcastIDs: [UUID]) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "filter": filter,
            "podcast_ids": podcastIDs.map(\.uuidString),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .homeSubscriptionList, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func carplayListenNowEnvelope(limit: Int) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "limit": limit,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .carplayListenNow, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func carplayShowsEnvelope(limit: Int) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "limit": limit,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .carplayShows, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func carplayShowEpisodesEnvelope(podcastID: UUID, limit: Int) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "podcast_id": podcastID.uuidString,
            "limit": limit,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .carplayShowEpisodes, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func carplayDownloadsEnvelope(limit: Int) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "limit": limit,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .carplayDownloads, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func libraryShowEpisodesEnvelope(podcastID: UUID, limit: Int) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "podcast_id": podcastID.uuidString,
            "limit": limit,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .libraryShowEpisodes, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func libraryPodcastStatsEnvelope(podcastIDs: [UUID]) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "podcast_ids": podcastIDs.map(\.uuidString),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .libraryPodcastStats, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func libraryEpisodeForAudioURLEnvelope(audioURL: String, podcastID: UUID) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "audio_url": audioURL,
            "podcast_id": podcastID.uuidString,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .libraryEpisodeForAudioUrl, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func librarySummaryEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = podcastAppString(handle, endpoint: .librarySummary) else {
            return nil
        }
        return result
    }

    func libraryAllEpisodesEnvelope(filter: String, query: String, limit: Int) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "filter": filter,
            "query": query,
            "limit": limit,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .libraryAllEpisodes, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func libraryAllPodcastsEnvelope(query: String) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "query": query,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .libraryAllPodcasts, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func libraryFollowedPodcastsEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = podcastAppString(handle, endpoint: .libraryFollowedPodcasts) else {
            return nil
        }
        return result
    }

    func libraryOwnedPodcastsEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = podcastAppString(handle, endpoint: .libraryOwnedPodcasts) else {
            return nil
        }
        return result
    }

    func libraryCategoriesEnvelope(categories: [[String: Any]]) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "categories": categories,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .libraryCategories, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func libraryDownloadRowsEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = podcastAppString(handle, endpoint: .libraryDownloadRows) else {
            return nil
        }
        return result
    }

    func libraryStarredEpisodesEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = podcastAppString(handle, endpoint: .libraryStarredEpisodes) else {
            return nil
        }
        return result
    }

    func libraryEpisodeLookupEnvelope(reference: String) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "reference": reference,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .libraryEpisodeLookup, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func librarySubscriptionStatusEnvelope(feedURL: String?, ownerPubkey: String?, podcastID: String? = nil) -> String? {
        guard let handle = podcastHandle else { return nil }
        var payload: [String: Any] = [:]
        if let podcastID { payload["podcast_id"] = podcastID }
        if let feedURL { payload["feed_url"] = feedURL }
        if let ownerPubkey { payload["owner_pubkey"] = ownerPubkey }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .librarySubscriptionStatus, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func libraryPodcastForOwnerPubkeyEnvelope(ownerPubkey: String) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "owner_pubkey": ownerPubkey,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .libraryPodcastForOwnerPubkey, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }
}
