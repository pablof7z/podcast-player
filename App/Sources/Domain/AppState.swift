import Foundation

// MARK: - AppState

struct AppState: Codable, Sendable {
    /// Podcasts the user follows. Source of truth for Library + Home + Search.
    var subscriptions: [PodcastSubscription] = []
    /// All known episodes across all subscriptions, hydrated from SQLite at
    /// launch. Reads filter by `subscriptionID` rather than maintaining
    /// per-subscription arrays so `upsertEpisodes(_:)` works for any feed.
    var episodes: [Episode] = []
    var notes: [Note] = []
    var friends: [Friend] = []
    var agentMemories: [AgentMemory] = []
    var settings: Settings = Settings()
    var nostrAllowedPubkeys: Set<String> = []
    var nostrBlockedPubkeys: Set<String> = []
    var nostrPendingApprovals: [NostrPendingApproval] = []
    var agentActivity: [AgentActivityEntry] = []
    /// Cross-episode threading topics inferred by `ThreadingInferenceService`.
    /// Empty until the user runs a recompute (or the seed-mock path fires in
    /// Debug). UX-09 surfaces are reserved for >=3-mention patterns.
    var threadingTopics: [ThreadingTopic] = []
    /// Per-topic mentions powering the timeline view. One row per transcript
    /// span. Carries its own `topicID` so adapters can build the mention list
    /// without scanning the topic array.
    var threadingMentions: [ThreadingMention] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case subscriptions, episodes
        case notes, friends, agentMemories, settings
        case nostrAllowedPubkeys, nostrBlockedPubkeys, nostrPendingApprovals
        case agentActivity
        case threadingTopics, threadingMentions
    }

    // Forward-compat: every field decoded with `decodeIfPresent` so adding new
    // fields never breaks decode of older persisted state. Legacy `items` /
    // `itemOrder` keys (from the inherited todo template) are silently ignored.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subscriptions = try c.decodeIfPresent([PodcastSubscription].self, forKey: .subscriptions) ?? []
        episodes = try c.decodeIfPresent([Episode].self, forKey: .episodes) ?? []
        notes = try c.decodeIfPresent([Note].self, forKey: .notes) ?? []
        friends = try c.decodeIfPresent([Friend].self, forKey: .friends) ?? []
        agentMemories = try c.decodeIfPresent([AgentMemory].self, forKey: .agentMemories) ?? []
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        nostrAllowedPubkeys = try c.decodeIfPresent(Set<String>.self, forKey: .nostrAllowedPubkeys) ?? []
        nostrBlockedPubkeys = try c.decodeIfPresent(Set<String>.self, forKey: .nostrBlockedPubkeys) ?? []
        nostrPendingApprovals = try c.decodeIfPresent([NostrPendingApproval].self, forKey: .nostrPendingApprovals) ?? []
        agentActivity = try c.decodeIfPresent([AgentActivityEntry].self, forKey: .agentActivity) ?? []
        threadingTopics = try c.decodeIfPresent([ThreadingTopic].self, forKey: .threadingTopics) ?? []
        threadingMentions = try c.decodeIfPresent([ThreadingMention].self, forKey: .threadingMentions) ?? []
    }
}
