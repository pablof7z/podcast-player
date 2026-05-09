import Foundation

// MARK: - Agent Activity
// One row per agent-driven mutation, capturing just enough to render a
// human-readable summary and undo the effect by flipping a soft-delete or
// restoring a prior status. Grouped by `batchID` (one batch per agent run).

enum AgentActivityKind: Codable, Hashable, Sendable {
    case itemCreated(itemID: UUID)
    case itemMarkedDone(itemID: UUID, priorStatus: ItemStatus)
    case itemDeleted(itemID: UUID)
    case noteCreated(noteID: UUID)
    case memoryRecorded(memoryID: UUID)
    case reminderSet(itemID: UUID)
    case reminderCleared(itemID: UUID, priorDate: Date)
    case itemPrioritySet(itemID: UUID, priorPriority: Bool)
    case itemTitleUpdated(itemID: UUID, priorTitle: String)
    case itemDetailsUpdated(itemID: UUID, priorDetails: String)
    /// Agent set a due date (priorDate is nil if no prior due date existed).
    case dueDateSet(itemID: UUID, priorDate: Date?)
    /// Agent cleared a due date.
    case dueDateCleared(itemID: UUID, priorDate: Date)
    /// Agent added or removed a tag on an item.
    case itemTagsUpdated(itemID: UUID)
    /// Agent changed the color label on an item.
    case itemColorTagUpdated(itemID: UUID, priorColorTag: ItemColorTag)
    /// Agent set or cleared the estimated minutes on an item.
    case itemEstimatedMinutesSet(itemID: UUID, priorMinutes: Int?)
    /// Agent pinned or unpinned an item.
    case itemPinned(itemID: UUID, priorPinned: Bool)
    /// Agent renamed a tag across all items.
    case tagRenamed(priorTag: String, newTag: String)
}

struct AgentActivityEntry: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var batchID: UUID
    var timestamp: Date
    var kind: AgentActivityKind
    var summary: String
    var undone: Bool

    init(batchID: UUID, kind: AgentActivityKind, summary: String) {
        self.id = UUID()
        self.batchID = batchID
        self.timestamp = Date()
        self.kind = kind
        self.summary = summary
        self.undone = false
    }
}
