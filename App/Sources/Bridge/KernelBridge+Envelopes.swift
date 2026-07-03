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
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .itunesDirectorySearch, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func itunesLookupFeedEnvelope(collectionID: String) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload = ["collection_id": collectionID]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .itunesLookupFeedUrl, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
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
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .itunesTopPodcasts, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func threadingProjectionEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = podcastAppCString(handle, endpoint: .threadingProjection) else {
            return nil
        }
        defer { freePodcastCString(result) }
        return String(cString: result)
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
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .threadingActiveTopics, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
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
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .localSearch, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
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
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .homeContinueListening, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func homeTriageRollupEnvelope(podcastIDs: [UUID]) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "podcast_ids": podcastIDs.map(\.uuidString),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .homeTriageRollup, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
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
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .homeSubscriptionList, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func carplayListenNowEnvelope(limit: Int) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "limit": limit,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .carplayListenNow, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func carplayShowsEnvelope(limit: Int) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "limit": limit,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .carplayShows, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
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
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .carplayShowEpisodes, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func carplayDownloadsEnvelope(limit: Int) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "limit": limit,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .carplayDownloads, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
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
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .libraryShowEpisodes, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func libraryPodcastStatsEnvelope(podcastIDs: [UUID]) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "podcast_ids": podcastIDs.map(\.uuidString),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .libraryPodcastStats, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
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
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .libraryEpisodeForAudioUrl, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func librarySummaryEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = podcastAppCString(handle, endpoint: .librarySummary) else {
            return nil
        }
        defer { freePodcastCString(result) }
        return String(cString: result)
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
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .libraryAllEpisodes, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func libraryAllPodcastsEnvelope(query: String) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "query": query,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .libraryAllPodcasts, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func libraryFollowedPodcastsEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = podcastAppCString(handle, endpoint: .libraryFollowedPodcasts) else {
            return nil
        }
        defer { freePodcastCString(result) }
        return String(cString: result)
    }

    func libraryOwnedPodcastsEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = podcastAppCString(handle, endpoint: .libraryOwnedPodcasts) else {
            return nil
        }
        defer { freePodcastCString(result) }
        return String(cString: result)
    }

    func libraryCategoriesEnvelope(categories: [[String: Any]]) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "categories": categories,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .libraryCategories, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func libraryDownloadRowsEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = podcastAppCString(handle, endpoint: .libraryDownloadRows) else {
            return nil
        }
        defer { freePodcastCString(result) }
        return String(cString: result)
    }

    func libraryStarredEpisodesEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = podcastAppCString(handle, endpoint: .libraryStarredEpisodes) else {
            return nil
        }
        defer { freePodcastCString(result) }
        return String(cString: result)
    }

    func libraryEpisodeLookupEnvelope(reference: String) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "reference": reference,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .libraryEpisodeLookup, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
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
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .librarySubscriptionStatus, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func libraryPodcastForOwnerPubkeyEnvelope(ownerPubkey: String) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "owner_pubkey": ownerPubkey,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .libraryPodcastForOwnerPubkey, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }
}
