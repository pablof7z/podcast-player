import Foundation

// MARK: - Podcast inventory tools (lane 10 — library queries)
//
// The four "what's in my library?" tools — `list_subscriptions`,
// `list_episodes`, `list_in_progress`, `list_recent_unplayed`. These let
// the agent answer plain-English questions about the user's existing
// library state without spending a search or RAG call. Split out of
// `AgentTools+Podcast.swift` to keep that file under the 500-line hard
// limit set by `AGENTS.md`.

extension AgentTools {

    // MARK: - Tool dispatch entry points

    static func listSubscriptionsTool(
        args: [String: Any],
        deps: PodcastAgentToolDeps
    ) async -> String {
        let limit = clampedInventoryLimit(args["limit"])
        let subs = await deps.inventory.listSubscriptions(limit: limit)
        let payload: [[String: Any]] = subs.map { sub in
            var row: [String: Any] = [
                "podcast_id": sub.podcastID,
                "title": sub.title,
                "total_episodes": sub.totalEpisodes,
                "unplayed_episodes": sub.unplayedEpisodes,
            ]
            if let author = sub.author, !author.isEmpty { row["author"] = author }
            if let date = sub.lastPublishedAt {
                row["last_published_at"] = ISO8601DateFormatter().string(from: date)
            }
            return row
        }
        return toolSuccess([
            "subscriptions": payload,
            "count": payload.count,
        ])
    }

    static func listEpisodesTool(
        args: [String: Any],
        deps: PodcastAgentToolDeps
    ) async -> String {
        guard let podcastID = (args["podcast_id"] as? String)?.trimmed, !podcastID.isEmpty else {
            return toolError("Missing or empty 'podcast_id'")
        }
        let limit = clampedInventoryLimit(args["limit"])
        guard let rows = await deps.inventory.listEpisodes(podcastID: podcastID, limit: limit) else {
            return toolError("Unknown podcast: \(podcastID)")
        }
        return toolSuccess([
            "podcast_id": podcastID,
            "episodes": rows.map(serializeInventoryRow),
            "count": rows.count,
        ])
    }

    static func listInProgressTool(
        args: [String: Any],
        deps: PodcastAgentToolDeps
    ) async -> String {
        let limit = clampedInventoryLimit(args["limit"])
        let rows = await deps.inventory.listInProgress(limit: limit)
        return toolSuccess([
            "episodes": rows.map(serializeInventoryRow),
            "count": rows.count,
        ])
    }

    static func listRecentUnplayedTool(
        args: [String: Any],
        deps: PodcastAgentToolDeps
    ) async -> String {
        let limit = clampedInventoryLimit(args["limit"])
        let rows = await deps.inventory.listRecentUnplayed(limit: limit)
        return toolSuccess([
            "episodes": rows.map(serializeInventoryRow),
            "count": rows.count,
        ])
    }

    // MARK: - Helpers

    private static let inventoryDefaultLimit = 25
    private static let inventoryMaxLimit = 100

    static func clampedInventoryLimit(_ raw: Any?) -> Int {
        guard let n = numericArg(raw) else { return inventoryDefaultLimit }
        return max(1, min(Int(n), inventoryMaxLimit))
    }

    static func serializeInventoryRow(_ row: EpisodeInventoryRow) -> [String: Any] {
        var out: [String: Any] = [
            "episode_id": row.episodeID,
            "podcast_id": row.podcastID,
            "title": row.title,
            "podcast_title": row.podcastTitle,
            "played": row.played,
            "playback_position_seconds": row.playbackPositionSeconds,
            "is_in_progress": row.isInProgress,
        ]
        if let date = row.publishedAt {
            out["published_at"] = ISO8601DateFormatter().string(from: date)
        }
        if let dur = row.durationSeconds { out["duration_seconds"] = dur }
        return out
    }
}
