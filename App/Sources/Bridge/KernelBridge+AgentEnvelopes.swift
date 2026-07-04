import Foundation

// ─── Agent / TTS / storage / categorization / remaining envelopes ─────────

extension PodcastHandle {
    func agentInventoryEnvelope(request: [String: Any]) -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .agentInventory, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func agentEmptyStateEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = podcastAppString(handle, endpoint: .agentEmptyState) else {
            return nil
        }
        return result
    }

    func libraryCategorizationPromptEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = podcastAppString(handle, endpoint: .libraryCategorizationPrompt) else {
            return nil
        }
        return result
    }

    func libraryCategorizationParseEnvelope(rawContent: String) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "raw_content": rawContent,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .libraryCategorizationParse, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func agentChatTitlePromptEnvelope(messages: [[String: String]]) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "messages": messages,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .agentChatTitlePrompt, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func agentChatTitleParseEnvelope(rawContent: String) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "raw_content": rawContent,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .agentChatTitleParse, request: jsonStr) else {
                return nil
            }
            return result
        }()
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
        return {
            guard let result = podcastAppString(handle, endpoint: .agentNostrPeerPrompt, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func agentSystemPromptEnvelope(request: [String: Any]) -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .agentSystemPrompt, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func agentConversationHistoryEnvelope(request: [String: Any]) -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .agentConversationHistory, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func libraryCategoryChangeEnvelope(request: [String: Any]) -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .libraryCategoryChange, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func storageBreakdownEnvelope(files: [[String: Any]]) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "files": files,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .storageBreakdown, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func homeCategoryCardsEnvelope(categories: [[String: Any]]) -> String? {
        guard let handle = podcastHandle else { return nil }
        let payload: [String: Any] = [
            "categories": categories,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .homeCategoryCards, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func agentTTSEpisodePlanEnvelope(request: [String: Any]) -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return {
            guard let result = podcastAppString(handle, endpoint: .agentTtsEpisodePlan, request: jsonStr) else {
                return nil
            }
            return result
        }()
    }

    func agentTTSDefaultVoiceEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = podcastAppString(handle, endpoint: .agentTtsDefaultVoice) else {
            return nil
        }
        return result
    }

    func agentGeneratedPodcastDescriptorEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = podcastAppString(handle, endpoint: .agentGeneratedPodcastDescriptor) else {
            return nil
        }
        return result
    }
}
