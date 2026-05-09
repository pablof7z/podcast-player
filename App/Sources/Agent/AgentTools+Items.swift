import Foundation

// MARK: - Item tool handlers

extension AgentTools {

    /// Handles create_item, set_item_priority, update_item, mark_item_done, and delete_item.
    @MainActor
    static func dispatchItems(name: String, args: [String: Any], store: AppStateStore, batchID: UUID) async -> String {
        switch name {
        case Names.createItem:
            return createItem(args: args, store: store, batchID: batchID)
        case Names.setItemPriority:
            return setItemPriority(args: args, store: store, batchID: batchID)
        case Names.updateItem:
            return updateItem(args: args, store: store, batchID: batchID)
        case Names.markItemDone:
            return markItemDone(args: args, store: store, batchID: batchID)
        case Names.deleteItem:
            return deleteItem(args: args, store: store, batchID: batchID)
        case Names.addTag:
            return addTag(args: args, store: store, batchID: batchID)
        case Names.removeTag:
            return removeTag(args: args, store: store, batchID: batchID)
        case Names.setItemColorTag:
            return setItemColorTag(args: args, store: store, batchID: batchID)
        case Names.setEstimatedMinutes:
            return setEstimatedMinutes(args: args, store: store, batchID: batchID)
        case Names.clearEstimatedMinutes:
            return clearEstimatedMinutes(args: args, store: store, batchID: batchID)
        case Names.pinItem:
            return pinItem(args: args, store: store, batchID: batchID)
        case Names.unpinItem:
            return unpinItem(args: args, store: store, batchID: batchID)
        case Names.renameTag:
            return renameTag(args: args, store: store, batchID: batchID)
        default:
            return toolError("Unknown item tool: \(name)")
        }
    }

    // MARK: - create_item

    @MainActor
    private static func createItem(args: [String: Any], store: AppStateStore, batchID: UUID) -> String {
        guard let title = args["title"] as? String, !title.isEmpty else {
            return toolError("Missing or empty 'title'")
        }
        var item = store.addItem(title: title, source: .agent)
        if let isPriority = args["is_priority"] as? Bool, isPriority {
            store.setItemPriority(item.id, priority: true)
            item.isPriority = true
        }
        store.recordAgentActivity(.init(
            batchID: batchID,
            kind: .itemCreated(itemID: item.id),
            summary: "Created \(item.isPriority ? "★ " : "")\"\(item.title)\""
        ))
        return toolSuccess(["id": item.id.uuidString, "title": item.title, "is_priority": item.isPriority])
    }

    // MARK: - set_item_priority

    @MainActor
    private static func setItemPriority(args: [String: Any], store: AppStateStore, batchID: UUID) -> String {
        guard let idStr = args["id"] as? String, let id = UUID(uuidString: idStr) else {
            return toolError("Invalid or missing 'id'")
        }
        guard let priority = args["priority"] as? Bool else {
            return toolError("Missing 'priority'")
        }
        guard let item = store.item(id: id) else {
            return toolError("Item not found")
        }
        let priorPriority = item.isPriority
        store.setItemPriority(id, priority: priority)
        store.recordAgentActivity(.init(
            batchID: batchID,
            kind: .itemPrioritySet(itemID: id, priorPriority: priorPriority),
            summary: priority ? "Marked ★ \"\(item.title)\" as priority" : "Removed priority from \"\(item.title)\""
        ))
        return toolSuccess(["id": idStr, "priority": priority])
    }

    // MARK: - update_item

    @MainActor
    private static func updateItem(args: [String: Any], store: AppStateStore, batchID: UUID) -> String {
        guard let idStr = args["id"] as? String, let id = UUID(uuidString: idStr) else {
            return toolError("Invalid or missing 'id'")
        }
        // At least one of title or details must be provided.
        let newTitle = (args["title"] as? String)?.trimmed
        let newDetails = args["details"] as? String
        guard newTitle != nil || newDetails != nil else {
            return toolError("Provide at least one of 'title' or 'details'")
        }
        guard let item = store.item(id: id) else {
            return toolError("Item not found")
        }
        var updated = item

        // Apply title change if provided and non-empty.
        if let t = newTitle, !t.isEmpty {
            let priorTitle = item.title
            updated.title = t
            store.recordAgentActivity(.init(
                batchID: batchID,
                kind: .itemTitleUpdated(itemID: id, priorTitle: priorTitle),
                summary: "Renamed \"\(priorTitle.prefix(summaryTruncationLength))\" → \"\(t.prefix(summaryTruncationLength))\""
            ))
        }

        // Apply details change if provided (empty string clears details).
        if let d = newDetails {
            let priorDetails = item.details
            updated.details = d
            let displayDetails = d.isEmpty ? "(cleared)" : "\"\(truncated(d))\""
            store.recordAgentActivity(.init(
                batchID: batchID,
                kind: .itemDetailsUpdated(itemID: id, priorDetails: priorDetails),
                summary: "Updated details for \"\(updated.title.prefix(summaryTruncationLength))\": \(displayDetails)"
            ))
        }

        store.updateItem(updated)
        return toolSuccess(["id": idStr, "title": updated.title, "details": updated.details])
    }

    // MARK: - mark_item_done

    @MainActor
    private static func markItemDone(args: [String: Any], store: AppStateStore, batchID: UUID) -> String {
        guard let idStr = args["id"] as? String, let id = UUID(uuidString: idStr) else {
            return toolError("Invalid or missing 'id'")
        }
        guard let prior = store.itemStatus(id) else {
            return toolError("Item not found")
        }
        store.setItemStatus(id, status: .done)
        let title = store.item(id: id)?.title ?? unknownItemTitle
        store.recordAgentActivity(.init(
            batchID: batchID,
            kind: .itemMarkedDone(itemID: id, priorStatus: prior),
            summary: "Marked \"\(title)\" done"
        ))
        return toolSuccess(["id": idStr])
    }

    // MARK: - delete_item

    @MainActor
    private static func deleteItem(args: [String: Any], store: AppStateStore, batchID: UUID) -> String {
        guard let idStr = args["id"] as? String, let id = UUID(uuidString: idStr) else {
            return toolError("Invalid or missing 'id'")
        }
        let title = store.item(id: id)?.title ?? unknownItemTitle
        store.deleteItem(id)
        store.recordAgentActivity(.init(
            batchID: batchID,
            kind: .itemDeleted(itemID: id),
            summary: "Deleted \"\(title)\""
        ))
        return toolSuccess(["id": idStr])
    }

    // MARK: - add_tag

    @MainActor
    private static func addTag(args: [String: Any], store: AppStateStore, batchID: UUID) -> String {
        guard let idStr = args["id"] as? String, let id = UUID(uuidString: idStr) else {
            return toolError("Invalid or missing 'id'")
        }
        guard let tag = args["tag"] as? String, !tag.isBlank else {
            return toolError("Missing or empty 'tag'")
        }
        guard let item = store.item(id: id) else {
            return toolError("Item not found")
        }
        let normalized = tag.lowercased().trimmed
        store.addTag(normalized, to: id)
        store.recordAgentActivity(.init(
            batchID: batchID,
            kind: .itemTagsUpdated(itemID: id),
            summary: "Added tag #\(normalized) to \"\(truncated(item.title))\""
        ))
        return toolSuccess(["id": idStr, "tag": normalized])
    }

    // MARK: - remove_tag

    @MainActor
    private static func removeTag(args: [String: Any], store: AppStateStore, batchID: UUID) -> String {
        guard let idStr = args["id"] as? String, let id = UUID(uuidString: idStr) else {
            return toolError("Invalid or missing 'id'")
        }
        guard let tag = args["tag"] as? String, !tag.isBlank else {
            return toolError("Missing or empty 'tag'")
        }
        guard let item = store.item(id: id) else {
            return toolError("Item not found")
        }
        let normalized = tag.lowercased().trimmed
        store.removeTag(normalized, from: id)
        store.recordAgentActivity(.init(
            batchID: batchID,
            kind: .itemTagsUpdated(itemID: id),
            summary: "Removed tag #\(normalized) from \"\(truncated(item.title))\""
        ))
        return toolSuccess(["id": idStr, "tag": normalized])
    }

    // MARK: - set_item_color_tag

    @MainActor
    private static func setItemColorTag(args: [String: Any], store: AppStateStore, batchID: UUID) -> String {
        guard let idStr = args["id"] as? String, let id = UUID(uuidString: idStr) else {
            return toolError("Invalid or missing 'id'")
        }
        guard let colorStr = args["color_tag"] as? String else {
            return toolError("Missing 'color_tag'")
        }
        guard let colorTag = ItemColorTag(rawValue: colorStr) else {
            let valid = ItemColorTag.allCases.map(\.rawValue).joined(separator: ", ")
            return toolError("Invalid color_tag '\(colorStr)'. Valid values: \(valid)")
        }
        guard let item = store.item(id: id) else {
            return toolError("Item not found")
        }
        let prior = item.colorTag
        store.setItemColorTag(id, colorTag: colorTag)
        let summary = colorTag == .none
            ? "Removed color label from \"\(truncated(item.title))\""
            : "Set \(colorTag.label) color on \"\(truncated(item.title))\""
        store.recordAgentActivity(.init(
            batchID: batchID,
            kind: .itemColorTagUpdated(itemID: id, priorColorTag: prior),
            summary: summary
        ))
        return toolSuccess(["id": idStr, "color_tag": colorTag.rawValue])
    }

    // MARK: - set_estimated_minutes

    @MainActor
    private static func setEstimatedMinutes(args: [String: Any], store: AppStateStore, batchID: UUID) -> String {
        guard let idStr = args["id"] as? String, let id = UUID(uuidString: idStr) else {
            return toolError("Invalid or missing 'id'")
        }
        guard let minutes = args["minutes"] as? Int, minutes > 0 else {
            return toolError("'minutes' must be a positive integer")
        }
        guard let item = store.item(id: id) else {
            return toolError("Item not found")
        }
        let prior = item.estimatedMinutes
        store.setEstimatedMinutes(id, minutes: minutes)
        let label = item.estimatedDurationLabel ?? "\(minutes) min"
        store.recordAgentActivity(.init(
            batchID: batchID,
            kind: .itemEstimatedMinutesSet(itemID: id, priorMinutes: prior),
            summary: "Set estimate \(label) on \"\(truncated(item.title))\""
        ))
        return toolSuccess(["id": idStr, "minutes": minutes])
    }

    // MARK: - clear_estimated_minutes

    @MainActor
    private static func clearEstimatedMinutes(args: [String: Any], store: AppStateStore, batchID: UUID) -> String {
        guard let idStr = args["id"] as? String, let id = UUID(uuidString: idStr) else {
            return toolError("Invalid or missing 'id'")
        }
        guard let item = store.item(id: id) else {
            return toolError("Item not found")
        }
        let prior = item.estimatedMinutes
        store.setEstimatedMinutes(id, minutes: nil)
        store.recordAgentActivity(.init(
            batchID: batchID,
            kind: .itemEstimatedMinutesSet(itemID: id, priorMinutes: prior),
            summary: "Cleared estimate from \"\(truncated(item.title))\""
        ))
        return toolSuccess(["id": idStr])
    }

    // MARK: - pin_item

    @MainActor
    private static func pinItem(args: [String: Any], store: AppStateStore, batchID: UUID) -> String {
        guard let idStr = args["id"] as? String, let id = UUID(uuidString: idStr) else {
            return toolError("Invalid or missing 'id'")
        }
        guard let item = store.item(id: id) else {
            return toolError("Item not found")
        }
        let prior = item.isPinned
        store.setItemPinned(id, pinned: true)
        store.recordAgentActivity(.init(
            batchID: batchID,
            kind: .itemPinned(itemID: id, priorPinned: prior),
            summary: "Pinned \"\(truncated(item.title))\""
        ))
        return toolSuccess(["id": idStr, "is_pinned": true])
    }

    // MARK: - unpin_item

    @MainActor
    private static func unpinItem(args: [String: Any], store: AppStateStore, batchID: UUID) -> String {
        guard let idStr = args["id"] as? String, let id = UUID(uuidString: idStr) else {
            return toolError("Invalid or missing 'id'")
        }
        guard let item = store.item(id: id) else {
            return toolError("Item not found")
        }
        let prior = item.isPinned
        store.setItemPinned(id, pinned: false)
        store.recordAgentActivity(.init(
            batchID: batchID,
            kind: .itemPinned(itemID: id, priorPinned: prior),
            summary: "Unpinned \"\(truncated(item.title))\""
        ))
        return toolSuccess(["id": idStr, "is_pinned": false])
    }

    // MARK: - rename_tag

    @MainActor
    private static func renameTag(args: [String: Any], store: AppStateStore, batchID: UUID) -> String {
        guard let oldTag = args["old_tag"] as? String, !oldTag.isBlank else {
            return toolError("Missing or empty 'old_tag'")
        }
        guard let newTag = args["new_tag"] as? String, !newTag.isBlank else {
            return toolError("Missing or empty 'new_tag'")
        }
        let normalizedOld = oldTag.lowercased().trimmed
        let normalizedNew = newTag.lowercased().trimmed
        // Count affected items before renaming so we can include the count in the summary.
        let affected = store.state.items.filter { !$0.deleted && $0.tags.contains(normalizedOld) }.count
        guard let resolvedNew = store.renameTag(from: normalizedOld, to: normalizedNew) else {
            if normalizedOld == normalizedNew {
                return toolError("'old_tag' and 'new_tag' are the same")
            }
            if affected == 0 {
                return toolError("No items found with tag '#\(normalizedOld)'")
            }
            return toolError("Rename failed — new tag name is empty")
        }
        let itemWord = affected == 1 ? "item" : "items"
        store.recordAgentActivity(.init(
            batchID: batchID,
            kind: .tagRenamed(priorTag: normalizedOld, newTag: resolvedNew),
            summary: "Renamed tag #\(normalizedOld) → #\(resolvedNew) on \(affected) \(itemWord)"
        ))
        return toolSuccess(["old_tag": normalizedOld, "new_tag": resolvedNew, "affected_items": affected])
    }
}
