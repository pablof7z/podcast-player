import Foundation

// MARK: - Items

extension AppStateStore {

    @discardableResult
    func addItem(title: String, source: ItemSource = .manual, friendID: UUID? = nil, friendName: String? = nil) -> Item {
        var item = Item(title: title, source: source)
        item.requestedByFriendID = friendID
        item.requestedByDisplayName = friendName
        state.items.append(item)
        return item
    }

    func setItemStatus(_ id: UUID, status: ItemStatus) {
        mutateItem(id) { item in
            item.status = status
            item.updatedAt = Date()
            if status != .pending {
                // Cancel all reminder notifications (including weekday fan-out variants)
                // and clear reminder metadata so re-opening the item starts fresh.
                item.reminderAt = nil
                item.recurrence = .none
            }
        }
        // Side effects that depend on the new value — run after the single state write.
        if status != .pending {
            NotificationService.cancel(for: id)
        }
        if status == .done {
            let totalCompleted = state.items.filter { $0.status == .done }.count
            ReviewPrompt.recordItemCompleted(totalCompletions: totalCompleted)
        }
    }

    func itemStatus(_ id: UUID) -> ItemStatus? {
        state.items.first { $0.id == id }?.status
    }

    func restoreItem(_ id: UUID) {
        mutateItem(id) { item in
            item.deleted = false
            item.updatedAt = Date()
        }
    }

    func updateItem(_ item: Item) {
        mutateItem(item.id) { existing in
            existing = item
            existing.updatedAt = Date()
        }
    }

    func deleteItem(_ id: UUID) {
        mutateItem(id) { item in
            item.deleted = true
            // Intentionally does NOT update `updatedAt` — tombstone preserves the
            // original timestamp so deletion can be distinguished from edits.
        }
        NotificationService.cancel(for: id)
    }

    /// Clears the stored reminder date on an item without changing its status.
    /// Call this after cancelling a pending notification outside the normal edit flow.
    func clearReminderDate(for id: UUID) {
        mutateItem(id) { item in
            item.reminderAt = nil
            item.updatedAt = Date()
        }
    }

    func setReminderAt(_ id: UUID, date: Date?) {
        mutateItem(id) { item in
            item.reminderAt = date
            item.updatedAt = Date()
        }
    }

    func setRecurrence(_ id: UUID, recurrence: ItemRecurrence) {
        mutateItem(id) { item in
            item.recurrence = recurrence
            item.updatedAt = Date()
        }
    }

    func setDueDate(_ id: UUID, date: Date?) {
        mutateItem(id) { item in
            item.dueAt = date
            item.updatedAt = Date()
        }
    }

    func toggleItemPriority(_ id: UUID) {
        mutateItem(id) { item in
            item.isPriority.toggle()
            item.updatedAt = Date()
        }
    }

    func setItemPriority(_ id: UUID, priority: Bool) {
        mutateItem(id) { item in
            item.isPriority = priority
            item.updatedAt = Date()
        }
    }

    func setItemColorTag(_ id: UUID, colorTag: ItemColorTag) {
        mutateItem(id) { item in
            item.colorTag = colorTag
            item.updatedAt = Date()
        }
    }

    func toggleItemPin(_ id: UUID) {
        mutateItem(id) { item in
            item.isPinned.toggle()
            item.updatedAt = Date()
        }
    }

    func setItemPinned(_ id: UUID, pinned: Bool) {
        mutateItem(id) { item in
            item.isPinned = pinned
            item.updatedAt = Date()
        }
    }

    /// Sets or clears the estimated completion time for an item.
    /// Pass `nil` or `0` to remove the estimate.
    func setEstimatedMinutes(_ id: UUID, minutes: Int?) {
        mutateItem(id) { item in
            item.estimatedMinutes = (minutes ?? 0) > 0 ? minutes : nil
            item.updatedAt = Date()
        }
    }

    /// Persists a user-defined display order for active items.
    ///
    /// `ids` is the full ordered list of active-item UUIDs after a drag gesture
    /// completes. Priority partitioning is preserved by `activeItems` — this method
    /// simply records the sequence so the comparator can honor it within each group.
    ///
    /// Items deleted or completed since the drag started are silently pruned.
    func reorderActiveItems(_ ids: [UUID]) {
        // Keep only IDs that still belong to active (non-deleted, pending) items
        // so stale tombstones don't accumulate in itemOrder indefinitely.
        let activeIDs = Set(state.items.filter { !$0.deleted && $0.status == .pending }.map(\.id))
        state.itemOrder = ids.filter { activeIDs.contains($0) }
    }

    // MARK: - Item Tags

    /// Adds a tag to an item. Tags are stored lowercased and trimmed; no-ops if
    /// the tag already exists on the item or is empty after trimming.
    func addTag(_ tag: String, to id: UUID) {
        let normalized = tag.lowercased().trimmed
        guard !normalized.isEmpty else { return }
        guard let idx = state.items.firstIndex(where: { $0.id == id }) else { return }
        guard !state.items[idx].tags.contains(normalized) else { return }
        mutateItem(id) { item in
            item.tags.append(normalized)
            item.updatedAt = Date()
        }
    }

    /// Removes a tag from an item. No-ops if the item doesn't have the tag.
    func removeTag(_ tag: String, from id: UUID) {
        let normalized = tag.lowercased().trimmed
        mutateItem(id) { item in
            item.tags.removeAll { $0 == normalized }
            item.updatedAt = Date()
        }
    }

    /// Replaces all tags on an item with the given set. Normalizes each tag (lowercased, trimmed)
    /// and deduplicates before writing.
    func setTags(_ tags: [String], for id: UUID) {
        let normalized = Array(Set(tags.map { $0.lowercased().trimmed }.filter { !$0.isEmpty })).sorted()
        mutateItem(id) { item in
            item.tags = normalized
            item.updatedAt = Date()
        }
    }

    // MARK: - Tag rename

    /// Renames `oldTag` to `newTag` across all non-deleted items in a single state mutation.
    /// Merge semantics: if any item already has `newTag`, `oldTag` is simply removed.
    /// Returns the resolved new tag name, or `nil` when `newTag` is blank or equals `oldTag`.
    @discardableResult
    func renameTag(from oldTag: String, to newTag: String) -> String? {
        let normalizedOld = oldTag.lowercased().trimmed
        let normalizedNew = newTag.lowercased().trimmed
        guard !normalizedNew.isEmpty, normalizedOld != normalizedNew else { return nil }
        var updated = state.items
        for idx in updated.indices where !updated[idx].deleted && updated[idx].tags.contains(normalizedOld) {
            var tags = Set(updated[idx].tags)
            tags.remove(normalizedOld)
            tags.insert(normalizedNew)
            updated[idx].tags = tags.sorted()
            updated[idx].updatedAt = Date()
        }
        state.items = updated
        return normalizedNew
    }

    // MARK: - Private helper

    /// Finds the item with `id` in `state.items` and applies `mutate` to it in a
    /// single index write, producing one `state.didSet` notification instead of N.
    /// No-ops silently when `id` is not found.
    private func mutateItem(_ id: UUID, _ mutate: (inout Item) -> Void) {
        guard let idx = state.items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&state.items[idx])
    }
}
