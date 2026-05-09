import Foundation

// MARK: - AppState

struct AppState: Codable, Sendable {
    var items: [Item] = []
    var notes: [Note] = []
    var friends: [Friend] = []
    var agentMemories: [AgentMemory] = []
    var settings: Settings = Settings()
    var nostrAllowedPubkeys: Set<String> = []
    var nostrBlockedPubkeys: Set<String> = []
    var nostrPendingApprovals: [NostrPendingApproval] = []
    var agentActivity: [AgentActivityEntry] = []
    /// User-defined display order for active (pending) items.
    /// Stores item UUIDs in the desired display sequence within each priority group.
    /// Items absent from this list (new/legacy) sort to the end of their group by createdAt.
    var itemOrder: [UUID] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case items, notes, friends, agentMemories, settings
        case nostrAllowedPubkeys, nostrBlockedPubkeys, nostrPendingApprovals
        case agentActivity, itemOrder
    }

    // Forward-compat: every field decoded with `decodeIfPresent` so adding new
    // fields never breaks decode of older persisted state.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
        notes = try c.decodeIfPresent([Note].self, forKey: .notes) ?? []
        friends = try c.decodeIfPresent([Friend].self, forKey: .friends) ?? []
        agentMemories = try c.decodeIfPresent([AgentMemory].self, forKey: .agentMemories) ?? []
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        nostrAllowedPubkeys = try c.decodeIfPresent(Set<String>.self, forKey: .nostrAllowedPubkeys) ?? []
        nostrBlockedPubkeys = try c.decodeIfPresent(Set<String>.self, forKey: .nostrBlockedPubkeys) ?? []
        nostrPendingApprovals = try c.decodeIfPresent([NostrPendingApproval].self, forKey: .nostrPendingApprovals) ?? []
        agentActivity = try c.decodeIfPresent([AgentActivityEntry].self, forKey: .agentActivity) ?? []
        itemOrder = try c.decodeIfPresent([UUID].self, forKey: .itemOrder) ?? []
    }

    // MARK: - Sorting

    /// Returns `pending` sorted by: pinned first → priority first → user drag order → createdAt.
    func sortedPendingItems(_ pending: [Item]) -> [Item] {
        let orderMap = Dictionary(uniqueKeysWithValues: itemOrder.enumerated().map { ($1, $0) })
        return pending.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            if lhs.isPriority != rhs.isPriority { return lhs.isPriority }
            let lIdx = orderMap[lhs.id] ?? Int.max
            let rIdx = orderMap[rhs.id] ?? Int.max
            if lIdx != rIdx { return lIdx < rIdx }
            return lhs.createdAt < rhs.createdAt
        }
    }
}
