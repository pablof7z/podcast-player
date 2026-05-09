import Foundation

// MARK: - Due date tool handlers

extension AgentTools {

    /// Handles set_due_date and clear_due_date.
    @MainActor
    static func dispatchDueDates(name: String, args: [String: Any], store: AppStateStore, batchID: UUID) -> String {
        switch name {
        case Names.setDueDate:
            return setDueDate(args: args, store: store, batchID: batchID)
        case Names.clearDueDate:
            return clearDueDate(args: args, store: store, batchID: batchID)
        default:
            return toolError("Unknown due-date tool: \(name)")
        }
    }

    // MARK: - set_due_date

    @MainActor
    private static func setDueDate(args: [String: Any], store: AppStateStore, batchID: UUID) -> String {
        guard let idStr = args["id"] as? String, let id = UUID(uuidString: idStr) else {
            return toolError("Invalid or missing 'id'")
        }
        guard let dateStr = args["date"] as? String else {
            return toolError("Missing 'date'")
        }
        let parsedDate = iso8601WithFractional.date(from: dateStr) ?? iso8601Basic.date(from: dateStr)
        guard let dueDate = parsedDate else {
            return toolError("Invalid date format — use ISO 8601 (e.g. 2025-06-15)")
        }
        guard let item = store.item(id: id) else {
            return toolError("Item not found")
        }
        let priorDate = item.dueAt
        store.setDueDate(id, date: dueDate)
        store.recordAgentActivity(.init(
            batchID: batchID,
            kind: .dueDateSet(itemID: id, priorDate: priorDate),
            summary: "Set due date for \"\(truncated(item.title))\" → \(dateStr)"
        ))
        return toolSuccess(["id": idStr, "due_date": dateStr])
    }

    // MARK: - clear_due_date

    @MainActor
    private static func clearDueDate(args: [String: Any], store: AppStateStore, batchID: UUID) -> String {
        guard let idStr = args["id"] as? String, let id = UUID(uuidString: idStr) else {
            return toolError("Invalid or missing 'id'")
        }
        guard let item = store.item(id: id) else {
            return toolError("Item not found")
        }
        guard let priorDate = item.dueAt else {
            return toolError("Item has no due date to clear")
        }
        store.setDueDate(id, date: nil)
        store.recordAgentActivity(.init(
            batchID: batchID,
            kind: .dueDateCleared(itemID: id, priorDate: priorDate),
            summary: "Cleared due date for \"\(truncated(item.title))\""
        ))
        return toolSuccess(["id": idStr])
    }
}
