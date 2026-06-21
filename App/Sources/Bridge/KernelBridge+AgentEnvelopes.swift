import Foundation

// ─── Agent / TTS / storage / categorization / remaining envelopes ─────────

extension PodcastHandle {
    func agentInventoryEnvelope(request: [String: Any]) -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = nmp_app_podcast_agent_inventory(handle, ptr) else {
                return nil
            }
            defer { nmp_free_string(result) }
            return String(cString: result)
        }
    }

    func agentEmptyStateEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = nmp_app_podcast_agent_empty_state(handle) else {
            return nil
        }
        defer { nmp_free_string(result) }
        return String(cString: result)
    }

    func libraryCategorizationPromptEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = nmp_app_podcast_library_categorization_prompt(handle) else {
            return nil
        }
        defer { nmp_free_string(result) }
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
            guard let result = nmp_app_podcast_library_categorization_parse(handle, ptr) else {
                return nil
            }
            defer { nmp_free_string(result) }
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
            guard let result = nmp_app_podcast_agent_chat_title_prompt(handle, ptr) else {
                return nil
            }
            defer { nmp_free_string(result) }
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
            guard let result = nmp_app_podcast_agent_chat_title_parse(handle, ptr) else {
                return nil
            }
            defer { nmp_free_string(result) }
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
            guard let result = nmp_app_podcast_agent_nostr_peer_prompt(handle, ptr) else {
                return nil
            }
            defer { nmp_free_string(result) }
            return String(cString: result)
        }
    }

    func agentSystemPromptEnvelope(request: [String: Any]) -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = nmp_app_podcast_agent_system_prompt(handle, ptr) else {
                return nil
            }
            defer { nmp_free_string(result) }
            return String(cString: result)
        }
    }

    func agentConversationHistoryEnvelope(request: [String: Any]) -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = nmp_app_podcast_agent_conversation_history(handle, ptr) else {
                return nil
            }
            defer { nmp_free_string(result) }
            return String(cString: result)
        }
    }

    func libraryCategoryChangeEnvelope(request: [String: Any]) -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = nmp_app_podcast_library_category_change(handle, ptr) else {
                return nil
            }
            defer { nmp_free_string(result) }
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
            guard let result = nmp_app_podcast_storage_breakdown(handle, ptr) else {
                return nil
            }
            defer { nmp_free_string(result) }
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
            guard let result = nmp_app_podcast_home_category_cards(handle, ptr) else {
                return nil
            }
            defer { nmp_free_string(result) }
            return String(cString: result)
        }
    }

    func agentTTSEpisodePlanEnvelope(request: [String: Any]) -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return nil }
        return jsonStr.withCString { ptr in
            guard let result = nmp_app_podcast_agent_tts_episode_plan(handle, ptr) else {
                return nil
            }
            defer { nmp_free_string(result) }
            return String(cString: result)
        }
    }

    func agentTTSDefaultVoiceEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = nmp_app_podcast_agent_tts_default_voice(handle) else {
            return nil
        }
        defer { nmp_free_string(result) }
        return String(cString: result)
    }

    func agentGeneratedPodcastDescriptorEnvelope() -> String? {
        guard let handle = podcastHandle else { return nil }
        guard let result = nmp_app_podcast_agent_generated_podcast_descriptor(handle) else {
            return nil
        }
        defer { nmp_free_string(result) }
        return String(cString: result)
    }
}
