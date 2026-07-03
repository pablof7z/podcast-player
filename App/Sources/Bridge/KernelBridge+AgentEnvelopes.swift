import Foundation

// ─── Agent / TTS / storage / categorization / remaining envelopes ─────────

extension PodcastHandle {
    func agentInventoryEnvelope(request: [String: Any]) -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .agentInventory, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func agentEmptyStateEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = podcastAppCString(handle, endpoint: .agentEmptyState) else {
            return nil
        }
        defer { freePodcastCString(result) }
        return String(cString: result)
    }

    func libraryCategorizationPromptEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = podcastAppCString(handle, endpoint: .libraryCategorizationPrompt) else {
            return nil
        }
        defer { freePodcastCString(result) }
        return String(cString: result)
    }

    func libraryCategorizationParseEnvelope(rawContent: String) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "raw_content": rawContent,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .libraryCategorizationParse, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func agentChatTitlePromptEnvelope(messages: [[String: String]]) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "messages": messages,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .agentChatTitlePrompt, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func agentChatTitleParseEnvelope(rawContent: String) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "raw_content": rawContent,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .agentChatTitleParse, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func agentNostrPeerPromptEnvelope(
        peerPubkey: String,
        peerDisplayName: String?,
        peerAbout: String?,
        ownerPubkey: String?
    ) -> String? {
        guard let handle = podcastHandle else { return nil }
        var payload: [String: Any] = [
            "peer_pubkey": peerPubkey,
        ]
        if let peerDisplayName { payload["peer_display_name"] = peerDisplayName }
        if let peerAbout { payload["peer_about"] = peerAbout }
        if let ownerPubkey { payload["owner_pubkey"] = ownerPubkey }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .agentNostrPeerPrompt, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func agentSystemPromptEnvelope(request: [String: Any]) -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .agentSystemPrompt, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func agentConversationHistoryEnvelope(request: [String: Any]) -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .agentConversationHistory, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func libraryCategoryChangeEnvelope(request: [String: Any]) -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .libraryCategoryChange, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func storageBreakdownEnvelope(files: [[String: Any]]) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "files": files,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .storageBreakdown, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func homeCategoryCardsEnvelope(categories: [[String: Any]]) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "categories": categories,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .homeCategoryCards, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func agentTTSEpisodePlanEnvelope(request: [String: Any]) -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = podcastAppCString(handle, endpoint: .agentTtsEpisodePlan, request: ptr) else {
                return nil
            }
            defer { freePodcastCString(result) }
            return String(cString: result)
        }
    }

    func agentTTSDefaultVoiceEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = podcastAppCString(handle, endpoint: .agentTtsDefaultVoice) else {
            return nil
        }
        defer { freePodcastCString(result) }
        return String(cString: result)
    }

    func agentGeneratedPodcastDescriptorEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = podcastAppCString(handle, endpoint: .agentGeneratedPodcastDescriptor) else {
            return nil
        }
        defer { freePodcastCString(result) }
        return String(cString: result)
    }
}
