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
    /// Categories produced by `PodcastCategorizationService`. The other
    /// agent owns generation; we store them here so settings + UI surfaces
    /// share one source of truth. Defaults to empty so an uncategorized
    /// install behaves exactly as before.
    var categories: [PodcastCategory] = []
    /// Per-category user preferences keyed by `PodcastCategory.id`.
    var categorySettings: [UUID: CategorySettings] = [:]
    var settings: Settings = Settings()
    var nostrAllowedPubkeys: Set<String> = []
    var nostrBlockedPubkeys: Set<String> = []
    var nostrPendingApprovals: [NostrPendingApproval] = []
    var agentActivity: [AgentActivityEntry] = []
    /// User-authored transcript excerpts. See `Clip` and the composer in
    /// `App/Sources/Features/EpisodeDetail/Clip/`.
    var clips: [Clip] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case subscriptions, episodes
        case notes, friends, agentMemories, settings
        case categories, categorySettings
        case nostrAllowedPubkeys, nostrBlockedPubkeys, nostrPendingApprovals
        case agentActivity
        case clips
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
        categories = try c.decodeIfPresent([PodcastCategory].self, forKey: .categories) ?? []
        categorySettings = try c.decodeIfPresent([UUID: CategorySettings].self, forKey: .categorySettings) ?? [:]
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        nostrAllowedPubkeys = try c.decodeIfPresent(Set<String>.self, forKey: .nostrAllowedPubkeys) ?? []
        nostrBlockedPubkeys = try c.decodeIfPresent(Set<String>.self, forKey: .nostrBlockedPubkeys) ?? []
        nostrPendingApprovals = try c.decodeIfPresent([NostrPendingApproval].self, forKey: .nostrPendingApprovals) ?? []
        agentActivity = try c.decodeIfPresent([AgentActivityEntry].self, forKey: .agentActivity) ?? []
        clips = try c.decodeIfPresent([Clip].self, forKey: .clips) ?? []
    }
}
