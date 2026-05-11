import Foundation

// MARK: - PodcastAgentToolValues
//
// Value-type contracts surfaced by the podcast tool surface. These structs are
// the *result* envelopes that lane-10 tools emit — protocols (the "deps")
// produce them; the dispatcher renders them back to the agent.
//
// Kept in a separate file from the protocol surface (`PodcastAgentToolDeps.swift`)
// purely for file-size hygiene — both files import the same types from here.

// MARK: - Identifiers

/// Identifier for an episode. Stringly-typed at the tool boundary so we don't
/// couple lane 10 to lane 2/3's `Episode` model. The orchestrator's adapter
/// translates between this string ID and whatever underlying type wins.
public typealias EpisodeID = String

/// Identifier for a podcast subscription. Same rationale as `EpisodeID`.
public typealias PodcastID = String

// MARK: - Search hits

/// A search hit returned by `search_episodes` or `find_similar_episodes`.
public struct EpisodeHit: Sendable, Equatable {
    public let episodeID: EpisodeID
    public let podcastID: PodcastID
    public let title: String
    public let podcastTitle: String
    public let publishedAt: Date?
    public let durationSeconds: Int?
    public let snippet: String?
    public let score: Double?

    public init(
        episodeID: EpisodeID,
        podcastID: PodcastID,
        title: String,
        podcastTitle: String,
        publishedAt: Date? = nil,
        durationSeconds: Int? = nil,
        snippet: String? = nil,
        score: Double? = nil
    ) {
        self.episodeID = episodeID
        self.podcastID = podcastID
        self.title = title
        self.podcastTitle = podcastTitle
        self.publishedAt = publishedAt
        self.durationSeconds = durationSeconds
        self.snippet = snippet
        self.score = score
    }
}

/// A transcript chunk hit returned by `query_transcripts`.
public struct TranscriptHit: Sendable, Equatable {
    public let episodeID: EpisodeID
    public let startSeconds: Double
    public let endSeconds: Double
    public let speaker: String?
    public let text: String
    public let score: Double?

    public init(
        episodeID: EpisodeID,
        startSeconds: Double,
        endSeconds: Double,
        speaker: String? = nil,
        text: String,
        score: Double? = nil
    ) {
        self.episodeID = episodeID
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.speaker = speaker
        self.text = text
        self.score = score
    }
}

/// A wiki page hit returned by `query_wiki`.
public struct WikiHit: Sendable, Equatable {
    public let pageID: String
    public let title: String
    public let excerpt: String
    public let score: Double?

    public init(pageID: String, title: String, excerpt: String, score: Double? = nil) {
        self.pageID = pageID
        self.title = title
        self.excerpt = excerpt
        self.score = score
    }
}

// MARK: - Composer / summarizer / external lookup

/// A composed briefing artifact. The agent renders this back to the user as a
/// single hero card; lane 8 owns the actual TTS rendering.
public struct BriefingResult: Sendable, Equatable {
    public let briefingID: String
    public let title: String
    public let estimatedSeconds: Int
    public let episodeIDs: [EpisodeID]
    public let scriptPreview: String?

    public init(
        briefingID: String,
        title: String,
        estimatedSeconds: Int,
        episodeIDs: [EpisodeID],
        scriptPreview: String? = nil
    ) {
        self.briefingID = briefingID
        self.title = title
        self.estimatedSeconds = estimatedSeconds
        self.episodeIDs = episodeIDs
        self.scriptPreview = scriptPreview
    }
}

/// A summary returned by `summarize_episode`.
public struct EpisodeSummary: Sendable, Equatable {
    public let episodeID: EpisodeID
    public let summary: String
    public let bulletPoints: [String]

    public init(episodeID: EpisodeID, summary: String, bulletPoints: [String] = []) {
        self.episodeID = episodeID
        self.summary = summary
        self.bulletPoints = bulletPoints
    }
}

/// A Perplexity search result.
public struct PerplexityResult: Sendable, Equatable {
    public struct Source: Sendable, Equatable {
        public let title: String
        public let url: String
        public init(title: String, url: String) {
            self.title = title
            self.url = url
        }
    }
    public let answer: String
    public let sources: [Source]

    public init(answer: String, sources: [Source]) {
        self.answer = answer
        self.sources = sources
    }
}

// MARK: - Mutation results

/// Result returned by episode-state mutation tools.
public struct EpisodeMutationResult: Sendable, Equatable {
    public let episodeID: EpisodeID
    public let podcastID: PodcastID?
    public let episodeTitle: String
    public let podcastTitle: String?
    public let state: String

    public init(
        episodeID: EpisodeID,
        podcastID: PodcastID? = nil,
        episodeTitle: String,
        podcastTitle: String? = nil,
        state: String
    ) {
        self.episodeID = episodeID
        self.podcastID = podcastID
        self.episodeTitle = episodeTitle
        self.podcastTitle = podcastTitle
        self.state = state
    }
}

/// Result returned when transcript ingestion is requested.
public struct TranscriptRequestResult: Sendable, Equatable {
    public let episodeID: EpisodeID
    public let status: String
    public let source: String?
    public let message: String?

    public init(
        episodeID: EpisodeID,
        status: String,
        source: String? = nil,
        message: String? = nil
    ) {
        self.episodeID = episodeID
        self.status = status
        self.source = source
        self.message = message
    }
}

/// Result returned by feed-refresh tools.
public struct FeedRefreshResult: Sendable, Equatable {
    public let podcastID: PodcastID
    public let title: String
    public let episodeCount: Int
    public let newEpisodeCount: Int
    public let refreshedAt: Date?

    public init(
        podcastID: PodcastID,
        title: String,
        episodeCount: Int,
        newEpisodeCount: Int,
        refreshedAt: Date? = nil
    ) {
        self.podcastID = podcastID
        self.title = title
        self.episodeCount = episodeCount
        self.newEpisodeCount = newEpisodeCount
        self.refreshedAt = refreshedAt
    }
}

/// Result returned by TENEX-compatible delegation.
public struct DelegationResult: Sendable, Equatable {
    public let eventID: String
    public let recipient: String
    public let prompt: String
    public let status: String
    public let createdAt: Date
    public let nostrKind: Int
    public let tags: [[String]]
    public let warning: String?

    public init(
        eventID: String,
        recipient: String,
        prompt: String,
        status: String,
        createdAt: Date,
        nostrKind: Int = 1,
        tags: [[String]],
        warning: String? = nil
    ) {
        self.eventID = eventID
        self.recipient = recipient
        self.prompt = prompt
        self.status = status
        self.createdAt = createdAt
        self.nostrKind = nostrKind
        self.tags = tags
        self.warning = warning
    }
}

// MARK: - Inventory rows

/// One subscription row returned by `list_subscriptions`. Compact on purpose:
/// the agent uses this to pick a `PodcastID` for a follow-up tool call (e.g.
/// `list_episodes(podcastID:)` or `query_wiki(scope:)`); detail pages are
/// rendered by other tools.
public struct SubscriptionSummary: Sendable, Equatable {
    public let podcastID: PodcastID
    public let title: String
    public let author: String?
    public let totalEpisodes: Int
    public let unplayedEpisodes: Int
    public let lastPublishedAt: Date?

    public init(
        podcastID: PodcastID,
        title: String,
        author: String?,
        totalEpisodes: Int,
        unplayedEpisodes: Int,
        lastPublishedAt: Date?
    ) {
        self.podcastID = podcastID
        self.title = title
        self.author = author
        self.totalEpisodes = totalEpisodes
        self.unplayedEpisodes = unplayedEpisodes
        self.lastPublishedAt = lastPublishedAt
    }
}

// MARK: - Category rows

/// Compact subscription row nested under `list_categories` results.
public struct CategorySubscriptionSummary: Sendable, Equatable {
    public let podcastID: PodcastID
    public let title: String
    public let author: String?

    public init(podcastID: PodcastID, title: String, author: String?) {
        self.podcastID = podcastID
        self.title = title
        self.author = author
    }
}

/// One LLM-derived category returned by `list_categories`.
public struct PodcastCategorySummary: Sendable, Equatable {
    public let categoryID: String
    public let name: String
    public let slug: String
    public let description: String
    public let colorHex: String?
    public let subscriptionCount: Int
    public let generatedAt: Date
    public let model: String?
    public let subscriptions: [CategorySubscriptionSummary]

    public init(
        categoryID: String,
        name: String,
        slug: String,
        description: String,
        colorHex: String?,
        subscriptionCount: Int,
        generatedAt: Date,
        model: String?,
        subscriptions: [CategorySubscriptionSummary]
    ) {
        self.categoryID = categoryID
        self.name = name
        self.slug = slug
        self.description = description
        self.colorHex = colorHex
        self.subscriptionCount = subscriptionCount
        self.generatedAt = generatedAt
        self.model = model
        self.subscriptions = subscriptions
    }
}

/// Category lookup supplied by `change_podcast_category`. The tool accepts ID,
/// slug, or display name so the agent can use whatever `list_categories`
/// returned in the prior turn.
public struct PodcastCategoryReference: Sendable, Equatable {
    public let id: String?
    public let slug: String?
    public let name: String?

    public init(id: String? = nil, slug: String? = nil, name: String? = nil) {
        self.id = id
        self.slug = slug
        self.name = name
    }

    public var isEmpty: Bool {
        [id, slug, name].allSatisfy { ($0 ?? "").isBlank }
    }
}

/// Result returned after moving a show between generated categories.
public struct PodcastCategoryChangeResult: Sendable, Equatable {
    public let podcastID: PodcastID
    public let title: String
    public let previousCategoryID: String?
    public let previousCategoryName: String?
    public let categoryID: String
    public let categoryName: String
    public let categorySlug: String

    public init(
        podcastID: PodcastID,
        title: String,
        previousCategoryID: String?,
        previousCategoryName: String?,
        categoryID: String,
        categoryName: String,
        categorySlug: String
    ) {
        self.podcastID = podcastID
        self.title = title
        self.previousCategoryID = previousCategoryID
        self.previousCategoryName = previousCategoryName
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.categorySlug = categorySlug
    }
}

/// One episode row returned by `list_episodes` / `list_in_progress` /
/// `list_recent_unplayed`. Distinct from `EpisodeHit` (search/RAG result) —
/// inventory rows carry the user's *state* (played, position) instead of a
/// search score.
public struct EpisodeInventoryRow: Sendable, Equatable {
    public let episodeID: EpisodeID
    public let podcastID: PodcastID
    public let title: String
    public let podcastTitle: String
    public let publishedAt: Date?
    public let durationSeconds: Int?
    public let played: Bool
    /// Seconds into the episode the user has reached. `0` for unplayed
    /// or freshly-marked-played; non-zero for in-progress.
    public let playbackPositionSeconds: Double
    /// Convenience flag: `playbackPositionSeconds > 0 && !played`.
    public let isInProgress: Bool

    public init(
        episodeID: EpisodeID,
        podcastID: PodcastID,
        title: String,
        podcastTitle: String,
        publishedAt: Date?,
        durationSeconds: Int?,
        played: Bool,
        playbackPositionSeconds: Double,
        isInProgress: Bool
    ) {
        self.episodeID = episodeID
        self.podcastID = podcastID
        self.title = title
        self.podcastTitle = podcastTitle
        self.publishedAt = publishedAt
        self.durationSeconds = durationSeconds
        self.played = played
        self.playbackPositionSeconds = playbackPositionSeconds
        self.isInProgress = isInProgress
    }
}
