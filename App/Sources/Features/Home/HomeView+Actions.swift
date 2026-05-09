import SwiftUI

// MARK: - HomeView actions

extension HomeView {

    func toggleItem(_ item: Item) {
        let newStatus: ItemStatus = item.status == .done ? .pending : .done
        store.setItemStatus(item.id, status: newStatus)
        // Use distinct patterns so the user can feel the difference between
        // completing (celebration) and re-opening (reversal).
        if newStatus == .done {
            Haptics.itemComplete()
            postUndo(.completed(itemID: item.id, title: item.title))
        } else {
            Haptics.itemReopen()
            clearUndo()
        }
    }

    func togglePriority(_ item: Item) {
        store.toggleItemPriority(item.id)
        // Crisp rigid beat when adding priority; soft release when removing it.
        if item.isPriority {
            // item.isPriority still reflects the *old* state here (before the toggle).
            Haptics.priorityOff()
        } else {
            Haptics.priorityOn()
        }
    }

    func togglePin(_ item: Item) {
        store.toggleItemPin(item.id)
        Haptics.selection()
    }

    func deleteItem(_ item: Item) {
        store.deleteItem(item.id)
        // Firm, definitive impact — more emphatic than a bare selection click.
        Haptics.delete()
        postUndo(.deleted(itemID: item.id, title: item.title))
    }

    /// Moves all overdue items' due dates to today, giving them a fresh start without
    /// losing their due-date context entirely.
    func rescheduleAllOverdue() {
        let today = Calendar.current.startOfDay(for: Date())
        for item in overdueItems {
            store.setDueDate(item.id, date: today)
        }
        Haptics.selection()
    }

    /// Creates a copy of `item` with the same title, tags, and priority flag.
    /// Due date and reminders are intentionally excluded so the duplicate starts fresh.
    func duplicateItem(_ item: Item) {
        let newItem = store.addItem(title: item.title, source: .manual)
        if item.isPriority { store.setItemPriority(newItem.id, priority: true) }
        for tag in item.tags { store.addTag(tag, to: newItem.id) }
        Haptics.success()
    }

    /// Sets (or clears) the due date on an item from the context menu quick-set submenu.
    ///
    /// Passes `nil` to clear an existing due date. Uses `Haptics.selection()` to confirm
    /// the action without the heavier impact reserved for destructive operations.
    func setDueDate(_ item: Item, date: Date?) {
        store.setDueDate(item.id, date: date)
        Haptics.selection()
    }

    func toggleSelection(_ item: Item) {
        Haptics.selection()
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    // MARK: - Bulk actions

    func bulkComplete() {
        let ids = Array(selectedIDs)
        let count = ids.count
        for id in ids {
            store.setItemStatus(id, status: .done)
        }
        // Double-beat pattern marks the plural nature of the operation.
        Haptics.bulkAction()
        exitEditMode()
        postUndo(.bulkCompleted(itemIDs: ids, count: count))
    }

    func bulkTogglePriority() {
        // If *all* selected items are already priority, clear all; otherwise set all.
        let allPriority = selectedIDs.allSatisfy { id in
            store.item(id: id)?.isPriority == true
        }
        for id in selectedIDs {
            store.setItemPriority(id, priority: !allPriority)
        }
        // Mirror the single-item priority patterns: rigid on, soft off.
        if allPriority {
            Haptics.priorityOff()
        } else {
            Haptics.priorityOn()
        }
        exitEditMode()
    }

    func bulkDelete() {
        let ids = Array(selectedIDs)
        let count = ids.count
        for id in ids {
            store.deleteItem(id)
        }
        // Double-beat delete pattern for batch removal.
        Haptics.bulkAction()
        exitEditMode()
        postUndo(.bulkDeleted(itemIDs: ids, count: count))
    }

    /// Adds `tag` to every selected item, skipping items that already carry it.
    ///
    /// The store's `addTag(_:to:)` normalizes (lowercased, trimmed) and
    /// deduplicates, so no extra work is needed here.
    func bulkAddTag(_ tag: String) {
        for id in selectedIDs {
            store.addTag(tag, to: id)
        }
        // Double-beat bulk pattern mirrors bulkComplete / bulkDelete for
        // plural emphasis — distinct from single-item selection feedback.
        Haptics.bulkAction()
        exitEditMode()
    }

    func bulkSetDuration(_ minutes: Int?) {
        for id in selectedIDs {
            store.setEstimatedMinutes(id, minutes: minutes)
        }
        Haptics.bulkAction()
        exitEditMode()
    }

    func exitEditMode() {
        withAnimation(AppTheme.Animation.spring) {
            isEditMode = false
            selectedIDs.removeAll()
        }
    }

    // MARK: - Deep-link / quick-action routing

    /// Converts a `HomeAction` dispatched by deep-link or home-screen quick action
    /// into the appropriate local navigation/UI state. Runs after `pendingHomeAction`
    /// is observed and cleared in the `.onChange` modifier above.
    func handlePendingAction(_ action: HomeAction) {
        switch action {
        case .addItem(let prefill):
            withAnimation(AppTheme.Animation.spring) {
                isEditMode = false
                showAddItem = true
            }
            if let prefill, !prefill.isEmpty {
                newItemDraft = prefill
            }
            // Focus the field on the next run-loop tick so it lands after the
            // row finishes animating into position.
            Task { @MainActor in
                addFieldFocused = true
            }
        case .showOverdue:
            withAnimation(AppTheme.Animation.spring) {
                activeFilter = .overdue
            }
        case .showDueThisWeek:
            withAnimation(AppTheme.Animation.spring) {
                activeFilter = .dueThisWeek
            }
        case .openAgent:
            showAgentChat = true
        case .openItem(let id):
            // Opened from a Spotlight continuation — present the detail sheet
            // directly. The item may be in any filter state; clear the filter
            // so the row is visible if the user dismisses the sheet.
            withAnimation(AppTheme.Animation.spring) {
                activeFilter = .all
                isEditMode = false
            }
            selectedItemID = id
        }
    }

    // MARK: - Focus mode filter

    /// Reads the Focus filter choice written by `FocusFilterIntent` and updates
    /// `focusOverride` accordingly. Called every time the scene becomes `.active`
    /// so the override is applied whether the app was backgrounded during Focus
    /// activation or was already in the foreground.
    ///
    /// Focus override takes precedence over the user's manual `activeFilter`
    /// but does not overwrite it — when the Focus ends `focusOverride` becomes
    /// `nil` and the list reverts to whatever `activeFilter` was set to.
    func applyFocusFilterIfNeeded() {
        guard let choice = FocusFilterStore.load() else {
            if focusOverride != nil {
                withAnimation(AppTheme.Animation.spring) { focusOverride = nil }
            }
            return
        }
        let newOverride: HomeFilter
        switch choice {
        case .all:         newOverride = .all
        case .priority:    newOverride = .priority
        case .tag(let t):  newOverride = .tag(t)
        }
        // Only animate when the override actually changes to avoid a spurious
        // re-render on every scene-active event.
        guard focusOverride != newOverride else { return }
        withAnimation(AppTheme.Animation.spring) { focusOverride = newOverride }
    }

    // MARK: - Undo

    /// Replaces (or sets) the pending undo action with a new one.
    /// Replacing triggers the toast to reset and show fresh.
    func postUndo(_ kind: UndoAction.Kind) {
        withAnimation(AppTheme.Animation.spring) {
            pendingUndo = UndoAction(kind: kind)
        }
    }

    func clearUndo() {
        withAnimation(AppTheme.Animation.spring) {
            pendingUndo = nil
        }
    }

    /// Reverses the mutation described by `action` then clears the toast.
    func applyUndo(_ action: UndoAction) {
        switch action.kind {
        case .completed(let id, _):
            store.setItemStatus(id, status: .pending)
        case .deleted(let id, _):
            store.restoreItem(id)
        case .bulkCompleted(let ids, _):
            for id in ids { store.setItemStatus(id, status: .pending) }
        case .bulkDeleted(let ids, _):
            for id in ids { store.restoreItem(id) }
        }
        // Reversal pattern — light-then-medium — signals "going backwards".
        Haptics.undo()
        withAnimation(AppTheme.Animation.spring) {
            pendingUndo = nil
        }
    }
}
