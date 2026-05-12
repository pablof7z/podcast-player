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
    /// LLM-consolidated paragraph summarizing the active `agentMemories`.
    /// Produced by `AgentMemoryCompiler` after agent turns. When non-nil,
    /// `AgentPrompt` injects this single paragraph in place of the raw
    /// memory bullets so the prompt stays compact as memories accumulate.
    var compiledMemory: CompiledAgentMemory?
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
    /// One record per Nostr conversation root (NIP-10) the agent has
    /// participated in. Surfaces in Settings > Agent > Conversations.
    var nostrConversations: [NostrConversationRecord] = []
    /// Cached kind:0 profile metadata keyed by hex pubkey. Hydrated lazily
    /// when new pubkeys land in pending approvals or conversations.
    var nostrProfileCache: [String: NostrProfileMetadata] = [:]
    /// Event ids the agent has already produced a reply for (or has
    /// deliberately decided to skip). Persisted so a relay re-delivery
    /// across app restarts can't trigger a duplicate reply.
    var nostrRespondedEventIDs: Set<String> = []
    /// Highest `created_at` we've observed on an inbound kind:1 routed to
    /// the agent. Persisted so a future REQ can carry `since:` and skip
    /// already-seen events; bumped before the model runs so a crash
    /// mid-reply still advances the cursor (dedup via
    /// `nostrRespondedEventIDs` covers the small overlap window).
    var nostrSinceCursor: Int?
    /// Roots that have been wrapped — either we acknowledged a peer's
    /// end signal or the per-root turn cap was hit. In-memory only:
    /// `nostrRespondedEventIDs` is the persistent half of the gate, so
    /// stragglers replayed across a restart are still dropped before they
    /// ever get to the ended-root check.
    var nostrEndedRootIDs: Set<String> = []
    var agentActivity: [AgentActivityEntry] = []
    /// User-authored transcript excerpts. See `Clip` and the composer in
    /// `App/Sources/Features/EpisodeDetail/Clip/`.
    var clips: [Clip] = []
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
        case notes, friends, agentMemories, compiledMemory, settings
        case categories, categorySettings
        case nostrAllowedPubkeys, nostrBlockedPubkeys, nostrPendingApprovals
        case nostrConversations, nostrProfileCache
        case nostrRespondedEventIDs, nostrSinceCursor
        // `nostrEndedRootIDs` is intentionally omitted — persistence is
        // carried by `nostrRespondedEventIDs`, which gates the same
        // straggler-after-restart case more cheaply.
        case agentActivity
        case clips
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
        compiledMemory = try c.decodeIfPresent(CompiledAgentMemory.self, forKey: .compiledMemory)
        categories = try c.decodeIfPresent([PodcastCategory].self, forKey: .categories) ?? []
        categorySettings = try c.decodeIfPresent([UUID: CategorySettings].self, forKey: .categorySettings) ?? [:]
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        nostrAllowedPubkeys = try c.decodeIfPresent(Set<String>.self, forKey: .nostrAllowedPubkeys) ?? []
        nostrBlockedPubkeys = try c.decodeIfPresent(Set<String>.self, forKey: .nostrBlockedPubkeys) ?? []
        nostrPendingApprovals = try c.decodeIfPresent([NostrPendingApproval].self, forKey: .nostrPendingApprovals) ?? []
        nostrConversations = try c.decodeIfPresent([NostrConversationRecord].self, forKey: .nostrConversations) ?? []
        nostrProfileCache = try c.decodeIfPresent([String: NostrProfileMetadata].self, forKey: .nostrProfileCache) ?? [:]
        nostrRespondedEventIDs = try c.decodeIfPresent(Set<String>.self, forKey: .nostrRespondedEventIDs) ?? []
        nostrSinceCursor = try c.decodeIfPresent(Int.self, forKey: .nostrSinceCursor)
        agentActivity = try c.decodeIfPresent([AgentActivityEntry].self, forKey: .agentActivity) ?? []
        clips = try c.decodeIfPresent([Clip].self, forKey: .clips) ?? []
        threadingTopics = try c.decodeIfPresent([ThreadingTopic].self, forKey: .threadingTopics) ?? []
        threadingMentions = try c.decodeIfPresent([ThreadingMention].self, forKey: .threadingMentions) ?? []
    }
}
