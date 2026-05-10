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

    /// Shared formatter for the inventory serializers. `ISO8601DateFormatter`
    /// is expensive to allocate (touches Foundation locale tables) and is
    /// thread-safe for reads after construction, so the per-row allocations
    /// in `serializeCategory` / `serializeInventoryRow` / `listSubscriptionsTool`
    /// were pure waste — a 200-episode `list_episodes` response was minting
    /// 200 formatters and discarding them. One shared instance is reused
    /// across calls.
    nonisolated(unsafe) private static let iso8601 = ISO8601DateFormatter()

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
                row["last_published_at"] = Self.iso8601.string(from: date)
            }
            return row
        }
        return toolSuccess([
            "subscriptions": payload,
            "count": payload.count,
        ])
    }

    static func listCategoriesTool(
        args: [String: Any],
        deps: PodcastAgentToolDeps
    ) async -> String {
        let limit = clampedInventoryLimit(args["limit"])
        let includePodcasts = boolArg(args["include_podcasts"], default: true)
        let categories = await deps.categories.listCategories(
            limit: limit,
            includePodcasts: includePodcasts
        )
        return toolSuccess([
            "categories": categories.map { serializeCategory($0, includePodcasts: includePodcasts) },
            "count": categories.count,
        ])
    }

    static func changePodcastCategoryTool(
        args: [String: Any],
        deps: PodcastAgentToolDeps
    ) async -> String {
        guard let podcastID = (args["podcast_id"] as? String)?.trimmed, !podcastID.isEmpty else {
            return toolError("Missing or empty 'podcast_id'")
        }
        let reference = PodcastCategoryReference(
            id: (args["category_id"] as? String)?.trimmed.nilIfEmpty,
            slug: (args["category_slug"] as? String)?.trimmed.nilIfEmpty,
            name: (args["category_name"] as? String)?.trimmed.nilIfEmpty
        )
        guard !reference.isEmpty else {
            return toolError("Provide one of 'category_id', 'category_slug', or 'category_name'")
        }
        do {
            let result = try await deps.categories.changePodcastCategory(
                podcastID: podcastID,
                category: reference
            )
            return toolSuccess(serializeCategoryChange(result))
        } catch {
            return toolError("change_podcast_category failed: \(error.localizedDescription)")
        }
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

    static func boolArg(_ raw: Any?, default defaultValue: Bool) -> Bool {
        if let value = raw as? Bool { return value }
        if let number = raw as? NSNumber { return number.boolValue }
        if let string = (raw as? String)?.trimmed.lowercased() {
            switch string {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: break
            }
        }
        return defaultValue
    }

    static func serializeCategory(
        _ category: PodcastCategorySummary,
        includePodcasts: Bool
    ) -> [String: Any] {
        var out: [String: Any] = [
            "category_id": category.categoryID,
            "name": category.name,
            "slug": category.slug,
            "description": category.description,
            "subscription_count": category.subscriptionCount,
            "generated_at": Self.iso8601.string(from: category.generatedAt),
        ]
        if let colorHex = category.colorHex { out["color_hex"] = colorHex }
        if let model = category.model { out["model"] = model }
        if includePodcasts {
            out["subscriptions"] = category.subscriptions.map { sub in
                var row: [String: Any] = [
                    "podcast_id": sub.podcastID,
                    "title": sub.title,
                ]
                if let author = sub.author { row["author"] = author }
                return row
            }
        }
        return out
    }

    static func serializeCategoryChange(_ result: PodcastCategoryChangeResult) -> [String: Any] {
        var out: [String: Any] = [
            "podcast_id": result.podcastID,
            "title": result.title,
            "category_id": result.categoryID,
            "category_name": result.categoryName,
            "category_slug": result.categorySlug,
        ]
        if let id = result.previousCategoryID { out["previous_category_id"] = id }
        if let name = result.previousCategoryName { out["previous_category_name"] = name }
        return out
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
            out["published_at"] = Self.iso8601.string(from: date)
        }
        if let dur = row.durationSeconds { out["duration_seconds"] = dur }
        return out
    }
}
