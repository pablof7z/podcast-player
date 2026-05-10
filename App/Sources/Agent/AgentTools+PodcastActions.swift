import Foundation

// MARK: - Podcast action tools

extension AgentTools {

    // MARK: - Playback controls

    static func pausePlaybackTool(args: [String: Any], deps: PodcastAgentToolDeps) async -> String {
        await deps.playback.pausePlayback()
        return toolSuccess(["state": "paused"])
    }

    static func setPlaybackRateTool(args: [String: Any], deps: PodcastAgentToolDeps) async -> String {
        guard let requested = podcastActionNumericArg(args["rate"]) else {
            return toolError("Missing or invalid 'rate'")
        }
        guard requested > 0 else {
            return toolError("'rate' must be greater than 0")
        }
        let applied = await deps.playback.setPlaybackRate(requested)
        return toolSuccess([
            "requested_rate": requested,
            "rate": applied,
        ])
    }

    static func setSleepTimerTool(args: [String: Any], deps: PodcastAgentToolDeps) async -> String {
        guard let mode = (args["mode"] as? String)?.trimmed.nilIfEmpty else {
            return toolError("Missing or empty 'mode'")
        }
        let normalized = mode.lowercased()
        guard ["off", "minutes", "end_of_episode"].contains(normalized) else {
            return toolError("'mode' must be one of: off, minutes, end_of_episode")
        }
        let minutes: Int?
        if normalized == "minutes" {
            guard let rawMinutes = podcastActionIntArg(args["minutes"]), rawMinutes > 0 else {
                return toolError("'minutes' is required when mode is 'minutes'")
            }
            minutes = min(180, rawMinutes)
        } else {
            minutes = nil
        }
        let label = await deps.playback.setSleepTimer(mode: normalized, minutes: minutes)
        var payload: [String: Any] = [
            "mode": normalized,
            "label": label,
        ]
        if let minutes { payload["minutes"] = minutes }
        return toolSuccess(payload)
    }

    // MARK: - Episode state

    static func markEpisodePlayedTool(args: [String: Any], deps: PodcastAgentToolDeps) async -> String {
        await episodeMutationTool(
            args: args,
            deps: deps,
            action: "mark_episode_played",
            mutate: deps.library.markEpisodePlayed
        )
    }

    static func markEpisodeUnplayedTool(args: [String: Any], deps: PodcastAgentToolDeps) async -> String {
        await episodeMutationTool(
            args: args,
            deps: deps,
            action: "mark_episode_unplayed",
            mutate: deps.library.markEpisodeUnplayed
        )
    }

    static func downloadEpisodeTool(args: [String: Any], deps: PodcastAgentToolDeps) async -> String {
        await episodeMutationTool(
            args: args,
            deps: deps,
            action: "download_episode",
            mutate: deps.library.downloadEpisode
        )
    }

    private static func episodeMutationTool(
        args: [String: Any],
        deps: PodcastAgentToolDeps,
        action: String,
        mutate: @escaping (EpisodeID) async throws -> EpisodeMutationResult
    ) async -> String {
        guard let episodeID = (args["episode_id"] as? String)?.trimmed, !episodeID.isEmpty else {
            return toolError("Missing or empty 'episode_id'")
        }
        let exists = await deps.fetcher.episodeExists(episodeID: episodeID)
        guard exists else {
            return toolError("Episode not found: \(episodeID)")
        }
        do {
            return toolSuccess(serializeEpisodeMutation(try await mutate(episodeID)))
        } catch {
            return toolError("\(action) failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Transcript + feed

    static func requestTranscriptionTool(args: [String: Any], deps: PodcastAgentToolDeps) async -> String {
        guard let episodeID = (args["episode_id"] as? String)?.trimmed, !episodeID.isEmpty else {
            return toolError("Missing or empty 'episode_id'")
        }
        let exists = await deps.fetcher.episodeExists(episodeID: episodeID)
        guard exists else {
            return toolError("Episode not found: \(episodeID)")
        }
        do {
            let result = try await deps.library.requestTranscription(episodeID: episodeID)
            var payload: [String: Any] = [
                "episode_id": result.episodeID,
                "status": result.status,
            ]
            if let source = result.source { payload["source"] = source }
            if let message = result.message { payload["message"] = message }
            return toolSuccess(payload)
        } catch {
            return toolError("request_transcription failed: \(error.localizedDescription)")
        }
    }

    static func refreshFeedTool(args: [String: Any], deps: PodcastAgentToolDeps) async -> String {
        guard let podcastID = (args["podcast_id"] as? String)?.trimmed, !podcastID.isEmpty else {
            return toolError("Missing or empty 'podcast_id'")
        }
        do {
            let result = try await deps.library.refreshFeed(podcastID: podcastID)
            var payload: [String: Any] = [
                "podcast_id": result.podcastID,
                "title": result.title,
                "episode_count": result.episodeCount,
                "new_episode_count": result.newEpisodeCount,
            ]
            if let refreshedAt = result.refreshedAt {
                payload["refreshed_at"] = iso8601Basic.string(from: refreshedAt)
            }
            return toolSuccess(payload)
        } catch {
            return toolError("refresh_feed failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Delegation

    static func delegateTool(args: [String: Any], deps: PodcastAgentToolDeps) async -> String {
        guard let recipient = (args["recipient"] as? String)?.trimmed, !recipient.isEmpty else {
            return toolError("Missing or empty 'recipient'")
        }
        guard let prompt = (args["prompt"] as? String)?.trimmed, !prompt.isEmpty else {
            return toolError("Missing or empty 'prompt'")
        }
        do {
            let result = try await deps.delegation.delegate(recipient: recipient, prompt: prompt)
            var payload: [String: Any] = [
                "delegation_event_id": result.eventID,
                "recipient": result.recipient,
                "status": result.status,
                "created_at": iso8601Basic.string(from: result.createdAt),
                "nostr_kind": result.nostrKind,
                "tags": result.tags,
                "stop_for_turn": true,
            ]
            if let warning = result.warning { payload["warning"] = warning }
            return toolSuccess(payload)
        } catch {
            return toolError("delegate failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private static func serializeEpisodeMutation(_ result: EpisodeMutationResult) -> [String: Any] {
        var payload: [String: Any] = [
            "episode_id": result.episodeID,
            "episode_title": result.episodeTitle,
            "state": result.state,
        ]
        if let podcastID = result.podcastID { payload["podcast_id"] = podcastID }
        if let podcastTitle = result.podcastTitle { payload["podcast_title"] = podcastTitle }
        return payload
    }

    private static func podcastActionNumericArg(_ raw: Any?) -> Double? {
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        if let n = raw as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func podcastActionIntArg(_ raw: Any?) -> Int? {
        if let i = raw as? Int { return i }
        if let d = raw as? Double { return Int(d) }
        if let n = raw as? NSNumber { return n.intValue }
        return nil
    }
}

// `nilIfEmpty` lives at internal scope on `String` in
// `AgentTools+Podcast.swift` so all three `AgentTools+*.swift` files
// share one definition.
