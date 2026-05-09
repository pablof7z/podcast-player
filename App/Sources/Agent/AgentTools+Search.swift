import Foundation

// MARK: - Search tool handlers

extension AgentTools {

    /// Handles find_items.
    @MainActor
    static func dispatchSearch(args: [String: Any], store: AppStateStore) -> String {
        guard let query = args["query"] as? String, !query.isEmpty else {
            return toolError("Missing or empty 'query'")
        }
        let statusFilter = args["status"] as? String ?? "all"
        let requestedLimit = args["limit"] as? Int ?? findItemsDefaultLimit
        let limit = min(max(1, requestedLimit), findItemsMaxLimit)

        let matches = store.state.items
            .filter { item in
                guard !item.deleted else { return false }
                switch statusFilter {
                case "pending": guard item.status == .pending else { return false }
                case "done":    guard item.status == .done    else { return false }
                case "dropped": guard item.status == .dropped else { return false }
                default: break  // "all" — no status filter
                }
                return item.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)

        let payload: [String: Any] = [
            "items": matches.map { item -> [String: Any] in
                var row: [String: Any] = [
                    "id":          item.id.uuidString,
                    "title":       item.title,
                    "status":      item.status.rawValue,
                    "is_priority": item.isPriority,
                    "is_pinned":   item.isPinned,
                ]
                let trimmedDetails = item.details.trimmed
                if !trimmedDetails.isEmpty {
                    row["details"] = trimmedDetails
                }
                if !item.tags.isEmpty {
                    row["tags"] = item.tags
                }
                if let reminder = item.reminderAt {
                    row["reminder_at"] = iso8601Basic.string(from: reminder)
                    if item.recurrence != .none {
                        row["recurrence"] = item.recurrence.rawValue
                    }
                }
                if let due = item.dueAt {
                    row["due_at"] = iso8601Basic.string(from: due)
                }
                if item.colorTag != .none {
                    row["color_tag"] = item.colorTag.rawValue
                }
                if let mins = item.estimatedMinutes, mins > 0 {
                    row["estimated_minutes"] = mins
                }
                return row
            },
            "total_found": matches.count,
        ]
        return toolSuccess(payload)
    }
}
