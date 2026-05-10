import Foundation

// MARK: - AppState

struct AppState: Codable, Sendable {
    /// Podcasts the user follows. Source of truth for Library + Home + Search.
    var subscriptions: [PodcastSubscription] = []
    /// All known episodes across all subscriptions. Reads filter by
    /// `subscriptionID` rather than maintaining per-subscription arrays so a
    /// single mutation surface (`upsertEpisodes(_:)`) works for any feed.
    var episodes: [Episode] = []
    var notes: [Note] = []
    var friends: [Friend] = []
    var agentMemories: [AgentMemory] = []
    var settings: Settings = Settings()
    var nostrAllowedPubkeys: Set<String> = []
    var nostrBlockedPubkeys: Set<String> = []
    var nostrPendingApprovals: [NostrPendingApproval] = []
    var agentActivity: [AgentActivityEntry] = []
    /// LLM-derived podcast categories covering the user's subscriptions.
    /// Recomputed on demand via `PodcastCategorizationService`; empty until
    /// the user runs the recompute action for the first time.
    var categories: [PodcastCategory] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case subscriptions, episodes
        case notes, friends, agentMemories, settings
        case nostrAllowedPubkeys, nostrBlockedPubkeys, nostrPendingApprovals
        case agentActivity
        case categories
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
        categories = try c.decodeIfPresent([PodcastCategory].self, forKey: .categories) ?? []
    }
}
