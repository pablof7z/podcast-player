import SwiftUI

// MARK: - HomeView item rows and section partitions

extension HomeView {

    // MARK: - Item rows / Section partitions
    //
    // Precedence: Overdue > Priority > Other.
    // An overdue item is not duplicated into Priority even if isPriority == true.

    /// Pinned items. Always shown first in their own "Pinned" section when any exist.
    var pinnedItems: [Item] {
        visibleItems.filter { $0.isPinned }
    }

    /// Items that are past their due date and NOT pinned. Shown in the "Overdue" section.
    var overdueItems: [Item] {
        visibleItems.filter { $0.isOverdue && !$0.isPinned }
    }

    /// Priority items that are NOT overdue and NOT pinned. Shown in the "Priority" section.
    var priorityNonOverdueItems: [Item] {
        visibleItems.filter { $0.isPriority && !$0.isOverdue && !$0.isPinned }
    }

    /// Non-priority, non-overdue, non-pinned items. Shown in the "Other" section.
    var otherItems: [Item] {
        visibleItems.filter { !$0.isPriority && !$0.isOverdue && !$0.isPinned }
    }

    /// `true` when the list should split into "Pinned", "Overdue", "Priority", and/or
    /// "Other" sections.
    ///
    /// Sectioning always activates when any items are pinned (the Pinned header is
    /// meaningful on its own). Otherwise it requires at least two non-empty groups
    /// to avoid a lone, redundant header. The filter must be `.all` since a filtered
    /// list is already scoped to a single conceptual group.
    var shouldShowSections: Bool {
        guard !effectiveFilter.isActive else { return false }
        if !pinnedItems.isEmpty { return true }
        let nonEmptyGroups = [overdueItems, priorityNonOverdueItems, otherItems]
            .filter { !$0.isEmpty }.count
        return nonEmptyGroups >= 2
    }

    @ViewBuilder
    var itemRows: some View {
        if shouldShowSections {
            if !pinnedItems.isEmpty {
                pinnedSection
            }
            if !overdueItems.isEmpty {
                overdueSection
            }
            if !priorityNonOverdueItems.isEmpty {
                prioritySection
            }
            if !otherItems.isEmpty {
                otherSection
            }
        } else {
            // Drag-to-reorder is only available in the unfiltered "All" view,
            // the unsectioned case (one priority group or one non-priority group),
            // and outside of bulk-edit mode.
            itemForEach(items: visibleItems) { source, destination in
                reorderItems(from: source, to: destination)
            }
        }
    }

    /// "Pinned" section — always shown first when any items are pinned.
    var pinnedSection: some View {
        let items = pinnedItems
        return Section {
            itemForEach(items: items) { source, destination in
                reorderItemsInGroup(items, partition: .pinned, from: source, to: destination)
            }
        } header: {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "pin.fill")
                    .rotationEffect(.degrees(45))
                    .accessibilityHidden(true)
                Text("Pinned · \(items.count)")
            }
            .foregroundStyle(Color.accentColor)
            .font(AppTheme.Typography.caption.weight(.semibold))
            .textCase(nil)
        }
    }

    /// "Overdue" section — shown when overdue items exist and `shouldShowSections` is true.
    var overdueSection: some View {
        let items = overdueItems
        return Section {
            itemForEach(items: items) { source, destination in
                reorderItemsInGroup(items, partition: .overdue, from: source, to: destination)
            }
        } header: {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "clock.badge.exclamationmark.fill")
                    .accessibilityHidden(true)
                Text("Overdue · \(items.count)")
                Spacer(minLength: 0)
                if items.count >= 2 {
                    Button("Reschedule All") { rescheduleAllOverdue() }
                        .accessibilityLabel("Reschedule all overdue items to today")
                }
            }
            .foregroundStyle(.red)
            .font(AppTheme.Typography.caption.weight(.semibold))
            .textCase(nil)
        }
    }

    /// "Priority" section — shown when priority-non-overdue items exist and `shouldShowSections` is true.
    var prioritySection: some View {
        let items = priorityNonOverdueItems
        return Section {
            itemForEach(items: items) { source, destination in
                reorderItemsInGroup(items, partition: .priority, from: source, to: destination)
            }
        } header: {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "star.fill")
                    .accessibilityHidden(true)
                Text("Priority · \(items.count)")
            }
            .foregroundStyle(.orange)
            .font(AppTheme.Typography.caption.weight(.semibold))
            .textCase(nil)
        }
    }

    /// "Other" section — shown when other items exist and `shouldShowSections` is true.
    var otherSection: some View {
        let items = otherItems
        return Section {
            itemForEach(items: items) { source, destination in
                reorderItemsInGroup(items, partition: .other, from: source, to: destination)
            }
        } header: {
            Text("Other · \(items.count)")
                .font(AppTheme.Typography.caption.weight(.semibold))
                .textCase(nil)
        }
    }

    /// Renders a `ForEach` of item rows with an optional drag-to-reorder handler.
    ///
    /// Keeping `.onMove` on the `ForEach` directly (rather than on a wrapper
    /// `some View`) satisfies the compiler — `ForEach` exposes `.onMove` natively.
    @ViewBuilder
    func itemForEach(
        items: [Item],
        onMove: ((IndexSet, Int) -> Void)? = nil
    ) -> some View {
        let activeTag: String? = {
            if case .tag(let t) = effectiveFilter { return t }
            return nil
        }()
        ForEach(items) { item in
            if isEditMode {
                HomeItemRow(
                    item: item,
                    isSelected: selectedIDs.contains(item.id),
                    isEditMode: true,
                    onTap: { toggleSelection(item) },
                    onToggle: { toggleItem(item) },
                    onTogglePriority: { togglePriority(item) },
                    onDelete: { deleteItem(item) },
                    highlightedTag: activeTag
                )
            } else {
                HomeItemRow(
                    item: item,
                    isSelected: false,
                    isEditMode: false,
                    onTap: { selectedItemID = item.id },
                    onToggle: { toggleItem(item) },
                    onTogglePriority: { togglePriority(item) },
                    onDelete: { deleteItem(item) },
                    onTagTap: { tag in
                        withAnimation(AppTheme.Animation.spring) {
                            activeFilter = .tag(tag)
                        }
                    },
                    onSetDueDate: { date in setDueDate(item, date: date) },
                    onSetColorTag: { colorTag in
                        store.setItemColorTag(item.id, colorTag: colorTag)
                        Haptics.selection()
                    },
                    onTogglePin: { togglePin(item) },
                    onSetDuration: { minutes in
                        store.setEstimatedMinutes(item.id, minutes: minutes)
                        Haptics.selection()
                    },
                    onDuplicate: { duplicateItem(item) },
                    highlightedTag: activeTag
                )
            }
        }
        .onMove(perform: canReorder ? onMove : nil)
    }

    /// `true` when drag-to-reorder is available to the user.
    var canReorder: Bool {
        !isEditMode && !effectiveFilter.isActive
    }

    /// Identifies which section partition is being reordered.
    enum SectionPartition {
        case pinned, overdue, priority, other
    }

    /// Persists the new item order after the user completes a drag gesture on the
    /// full unsectioned list.
    ///
    /// `visibleItems` equals `activeItems` when the filter is `.all`, so we
    /// apply the move to that snapshot and write the resulting UUID sequence
    /// to `AppStateStore`. The store's `activeItems` comparator then recreates
    /// the list in the same order on the next render.
    func reorderItems(from source: IndexSet, to destination: Int) {
        Haptics.selection()
        var reordered = visibleItems
        reordered.move(fromOffsets: source, toOffset: destination)
        store.reorderActiveItems(reordered.map(\.id))
    }

    /// Persists the new item order after a drag gesture within a single section
    /// (Pinned, Overdue, Priority, or Other). Merges the reordered group back into
    /// the full active list, always placing Pinned first, Overdue second, Priority
    /// third, Other fourth.
    func reorderItemsInGroup(_ group: [Item], partition: SectionPartition, from source: IndexSet, to destination: Int) {
        Haptics.selection()
        var reorderedGroup = group
        reorderedGroup.move(fromOffsets: source, toOffset: destination)
        // Build the canonical four-partition order: Pinned → Overdue → Priority → Other.
        // The reordered partition replaces its slot; other partitions keep their current order.
        let newPinned   = partition == .pinned   ? reorderedGroup : pinnedItems
        let newOverdue  = partition == .overdue  ? reorderedGroup : overdueItems
        let newPriority = partition == .priority ? reorderedGroup : priorityNonOverdueItems
        let newOther    = partition == .other    ? reorderedGroup : otherItems
        let merged: [Item] = newPinned + newOverdue + newPriority + newOther
        store.reorderActiveItems(merged.map(\.id))
    }
}
