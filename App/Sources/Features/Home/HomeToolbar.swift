import SwiftUI

// MARK: - HomeToolbar

/// Toolbar content, completed button, and filter menu for HomeView.
///
/// Extracted from HomeView to keep that file under the 300-line soft limit.
struct HomeToolbar: ToolbarContent {
    @Environment(AppStateStore.self) var store

    let visibleItems: [Item]
    @Binding var isEditMode: Bool
    @Binding var selectedIDs: Set<UUID>
    @Binding var showCompleted: Bool
    @Binding var showSearch: Bool
    @Binding var showAgentChat: Bool
    @Binding var showAddItem: Bool
    @Binding var newItemDraft: String
    /// Called when the toolbar needs to request keyboard focus for the add-item field.
    var onRequestAddFocus: () -> Void
    @Binding var activeFilter: HomeFilter

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: AppTheme.Spacing.xs) {
                if isEditMode {
                    HomeBulkSelectionBar(
                        totalCount: visibleItems.count,
                        selectedCount: selectedIDs.count,
                        onSelectAll: { selectedIDs = Set(visibleItems.map(\.id)) },
                        onDeselectAll: { selectedIDs.removeAll() }
                    )
                } else {
                    completedButton
                    filterMenu
                }
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Haptics.selection()
                withAnimation(AppTheme.Animation.spring) {
                    isEditMode.toggle()
                    if !isEditMode {
                        selectedIDs.removeAll()
                        showAddItem = false
                        newItemDraft = ""
                    }
                }
            } label: {
                Text(isEditMode ? "Done" : "Edit")
                    .fontWeight(isEditMode ? .semibold : .regular)
            }
            .buttonStyle(.glass)
            .disabled(visibleItems.isEmpty && !isEditMode)
            .accessibilityLabel(isEditMode ? "Done editing" : "Edit items")
            // ⌘E — toggle edit/selection mode (iPad / hardware keyboard)
            .keyboardShortcut("e", modifiers: .command)
        }

        if !isEditMode {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Search")
                // ⌘F — universal search
                .keyboardShortcut("f", modifiers: .command)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button { showAgentChat = true } label: {
                    Image(systemName: "sparkles")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Open Agent")
                // ⌘⇧A — open agent chat
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(AppTheme.Animation.springFast) {
                        showAddItem.toggle()
                        if showAddItem {
                            onRequestAddFocus()
                        } else {
                            newItemDraft = ""
                        }
                    }
                } label: {
                    Image(systemName: showAddItem ? "xmark.circle.fill" : "plus")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(showAddItem ? "Cancel" : "Add item")
                // ⌘N — toggle add-item field
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    // MARK: - Completed button

    private var completedButton: some View {
        Button { showCompleted = true } label: {
            Image(systemName: "checkmark.circle")
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("View completed items")
        // ⌘⇧C — view completed items (iPad / hardware keyboard)
        .keyboardShortcut("c", modifiers: [.command, .shift])
        .overlay(alignment: .topTrailing) {
            if store.completedItems.count > 0 {
                Text("\(min(store.completedItems.count, 99))")
                    .font(AppTheme.Typography.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppTheme.Spacing.xs)
                    .background(.green, in: Capsule())
                    .offset(x: 6, y: -6)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Filter menu

    private var filterMenu: some View {
        Menu {
            Button {
                withAnimation(AppTheme.Animation.spring) { activeFilter = .all }
            } label: {
                Label("All Items", systemImage: activeFilter == .all ? "checkmark" : HomeFilter.all.icon)
            }

            Divider()

            Button {
                withAnimation(AppTheme.Animation.spring) { activeFilter = .priority }
            } label: {
                let n = store.priorityItemCount
                Label(n > 0 ? "Priority (\(n))" : "Priority",
                      systemImage: activeFilter == .priority ? "checkmark" : HomeFilter.priority.icon)
            }

            Button {
                withAnimation(AppTheme.Animation.spring) { activeFilter = .reminders }
            } label: {
                let n = store.remindersItemCount
                Label(n > 0 ? "Reminders (\(n))" : "Reminders",
                      systemImage: activeFilter == .reminders ? "checkmark" : HomeFilter.reminders.icon)
            }

            if store.overdueItemCount > 0 {
                Button {
                    withAnimation(AppTheme.Animation.spring) { activeFilter = .overdue }
                } label: {
                    Label("Overdue (\(store.overdueItemCount))",
                          systemImage: activeFilter == .overdue ? "checkmark" : HomeFilter.overdue.icon)
                }
            }

            if store.dueTodayCount > 0 {
                Button {
                    withAnimation(AppTheme.Animation.spring) { activeFilter = .dueToday }
                } label: {
                    Label("Due Today (\(store.dueTodayCount))",
                          systemImage: activeFilter == .dueToday ? "checkmark" : HomeFilter.dueToday.icon)
                }
            }

            if store.dueThisWeekCount > 0 {
                Button {
                    withAnimation(AppTheme.Animation.spring) { activeFilter = .dueThisWeek }
                } label: {
                    Label("Due This Week (\(store.dueThisWeekCount))",
                          systemImage: activeFilter == .dueThisWeek ? "checkmark" : HomeFilter.dueThisWeek.icon)
                }
            }

            let friendsWithItems = store.friendsWithPendingItems
            if !friendsWithItems.isEmpty {
                Divider()
                ForEach(friendsWithItems) { friend in
                    let filter = HomeFilter.friend(id: friend.id, displayName: friend.displayName)
                    Button {
                        withAnimation(AppTheme.Animation.spring) { activeFilter = filter }
                    } label: {
                        Label(friend.displayName,
                              systemImage: activeFilter == filter ? "checkmark" : filter.icon)
                    }
                }
            }

            let tags = store.allTags
            if !tags.isEmpty {
                let tagCounts = store.activeItemCountByTag
                Divider()
                ForEach(tags, id: \.self) { tag in
                    Button {
                        withAnimation(AppTheme.Animation.spring) { activeFilter = .tag(tag) }
                    } label: {
                        let n = tagCounts[tag] ?? 0
                        Label(n > 0 ? "#\(tag) (\(n))" : "#\(tag)",
                              systemImage: activeFilter == .tag(tag) ? "checkmark" : HomeFilter.tag(tag).icon)
                    }
                }
            }

            let colorTagsInUse = store.allColorTagsInUse
            if !colorTagsInUse.isEmpty {
                Divider()
                ForEach(colorTagsInUse, id: \.self) { colorTag in
                    Button {
                        withAnimation(AppTheme.Animation.spring) { activeFilter = .color(colorTag) }
                    } label: {
                        Label(colorTag.label,
                              systemImage: activeFilter == .color(colorTag) ? "checkmark" : HomeFilter.color(colorTag).icon)
                    }
                    .tint(colorTag.color)
                }
            }
        } label: {
            Image(systemName: activeFilter.isActive
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
                .foregroundStyle(activeFilter.isActive ? Color.accentColor : .secondary)
                .symbolEffect(.bounce, value: activeFilter.isActive)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(activeFilter.isActive ? "Filter: \(activeFilter.label)" : "Filter items")
    }
}
