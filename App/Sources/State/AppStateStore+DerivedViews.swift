import Foundation

// MARK: - Derived Views

extension AppStateStore {

    var activeItems: [Item] {
        let pending = state.items.filter { !$0.deleted && $0.status == .pending }
        return state.sortedPendingItems(pending)
    }

    /// Active items narrowed by the given `HomeFilter`.
    ///
    /// Sorting is the same as `activeItems` (priority-first, then chronological)
    /// so the relative order is preserved when the filter changes.
    func filteredActiveItems(_ filter: HomeFilter) -> [Item] {
        activeItems.filter { filter.matches($0) }
    }

    /// Number of active (pending, non-deleted) items whose due date is in the past.
    var overdueItemCount: Int {
        state.items.filter { !$0.deleted && $0.isOverdue }.count
    }

    /// Number of pending items marked as priority.
    var priorityItemCount: Int {
        activeItems.filter(\.isPriority).count
    }

    /// Number of pending items with a reminder set.
    var remindersItemCount: Int {
        activeItems.filter { $0.reminderAt != nil }.count
    }

    /// Number of pending, non-deleted items due on today's calendar date
    /// that are not yet overdue. Used to gate the "Due Today" filter menu item.
    var dueTodayCount: Int {
        state.items.filter { item in
            guard !item.deleted && item.status == .pending && !item.isOverdue,
                  let due = item.dueAt else { return false }
            return Calendar.current.isDateInToday(due)
        }.count
    }

    /// Number of active (pending, non-deleted) items due within the next 7 days
    /// that are not yet overdue. Used to gate the "Due This Week" filter menu item.
    var dueThisWeekCount: Int {
        let cutoff = Date().addingTimeInterval(7 * 24 * 60 * 60)
        return state.items.filter { item in
            !item.deleted
                && item.status == .pending
                && !item.isOverdue
                && (item.dueAt.map { $0 <= cutoff } ?? false)
        }.count
    }

    /// Friends who have at least one pending item — used to populate the
    /// "filter by friend" submenu in HomeView.
    var friendsWithPendingItems: [Friend] {
        state.friends.filter { pendingItemCount(forFriend: $0.id) > 0 }
    }

    /// Sorted, deduplicated list of all tags present on non-deleted items —
    /// used to populate the tag filter submenu in HomeView.
    var allTags: [String] {
        let tags = state.items
            .filter { !$0.deleted }
            .flatMap(\.tags)
        return Array(Set(tags)).sorted()
    }

    /// Count of pending (active) items per tag — used to show counts in the
    /// tag filter submenu, matching the pattern already applied to Priority/Reminders/Overdue.
    var activeItemCountByTag: [String: Int] {
        activeItems.reduce(into: [:]) { counts, item in
            for tag in item.tags { counts[tag, default: 0] += 1 }
        }
    }

    /// Ordered list of color tags actually applied to at least one non-deleted
    /// active item — used to populate the color filter submenu in HomeView.
    ///
    /// The order follows `ItemColorTag.allCases` so the submenu is stable
    /// across re-renders. `.none` is excluded because it represents "no color"
    /// and filtering by it would be confusing and rarely useful.
    var allColorTagsInUse: [ItemColorTag] {
        let usedColors = Set(
            state.items
                .filter { !$0.deleted && $0.status == .pending && $0.colorTag != .none }
                .map(\.colorTag)
        )
        return ItemColorTag.allCases.filter { $0 != .none && usedColors.contains($0) }
    }

    var completedItems: [Item] {
        state.items
            .filter { !$0.deleted && $0.status == .done }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func clearCompletedItems() {
        // Extract, mutate, reassign — one `state.didSet` instead of N.
        var updated = state.items
        for idx in updated.indices where !updated[idx].deleted && updated[idx].status == .done {
            updated[idx].deleted = true
        }
        state.items = updated
    }

    /// Number of items completed today (status == .done, updatedAt is today).
    var completedTodayCount: Int {
        state.items.filter {
            !$0.deleted
                && $0.status == .done
                && Calendar.current.isDateInToday($0.updatedAt)
        }.count
    }

    var activeNotes: [Note] {
        state.notes.filter { !$0.deleted }
    }

    // MARK: - Friend-scoped helpers

    /// All friends sorted alphabetically by display name — the canonical order
    /// for any list that shows friends without an explicit user-defined sort.
    var sortedFriends: [Friend] {
        state.friends.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// Returns the live item record matching `id`, or `nil` when not found.
    func item(id: UUID) -> Item? {
        state.items.first { $0.id == id }
    }

    /// Total count of non-deleted items across all statuses (pending, done, dropped).
    /// Used for data-export record counts and similar totals.
    var nonDeletedItemCount: Int {
        state.items.filter { !$0.deleted }.count
    }

    /// Returns the live friend record matching `id`, or `nil` when not found.
    func friend(id: UUID) -> Friend? {
        state.friends.first { $0.id == id }
    }

    /// Returns the live friend record whose Nostr identifier (pubkey hex or npub)
    /// matches `identifier`, or `nil` when not found.
    func friend(identifier: String) -> Friend? {
        state.friends.first { $0.identifier == identifier }
    }

    /// Number of pending (non-deleted, status == .pending) items requested by the given friend.
    func pendingItemCount(forFriend friendID: UUID) -> Int {
        state.items.filter {
            !$0.deleted && $0.status == .pending && $0.requestedByFriendID == friendID
        }.count
    }

    /// Most recent activity date associated with a friend — the latest of:
    /// - items they requested (createdAt or updatedAt, whichever is newer)
    /// - notes targeting the friend (Anchor.friend) or their items (Anchor.item)
    /// Falls back to `nil` when the friend has no associated data at all.
    func lastActivity(forFriend friendID: UUID) -> Date? {
        let friendItemIDs: Set<UUID> = Set(
            state.items
                .filter { !$0.deleted && $0.requestedByFriendID == friendID }
                .map(\.id)
        )
        let itemDates = state.items
            .filter { !$0.deleted && $0.requestedByFriendID == friendID }
            .map { max($0.createdAt, $0.updatedAt) }
        let noteDates = state.notes
            .filter { note -> Bool in
                guard !note.deleted, let target = note.target else { return false }
                switch target {
                case .friend(let id): return id == friendID
                case .item(let id):   return friendItemIDs.contains(id)
                case .note:           return false
                }
            }
            .map(\.createdAt)
        return (itemDates + noteDates).max()
    }

    // MARK: - Streak & weekly trend

    /// Number of items completed today plus each prior consecutive calendar day
    /// with at least one completion.
    ///
    /// Rule: if today has no completions yet, the streak is based on trailing
    /// days (so it doesn't reset the moment a new day starts). Streak breaks when
    /// a full calendar day with zero completions is found while walking backwards.
    var completionStreak: Int {
        let cal = Calendar.current
        let completedDates = state.items
            .filter { !$0.deleted && $0.status == .done }
            .map { cal.startOfDay(for: $0.updatedAt) }
        let uniqueDays = Set(completedDates)
        guard !uniqueDays.isEmpty else { return 0 }

        var streak = 0
        var cursor = cal.startOfDay(for: Date())
        // Walk backwards from today. If today has no completions, skip it
        // gracefully — the streak extends from yesterday.
        while uniqueDays.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// Completion counts for the 7 most recent calendar days (oldest first).
    /// Index 0 = 6 days ago, index 6 = today. Always exactly 7 elements.
    var weeklyCompletions: [Int] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let completed = state.items.filter { !$0.deleted && $0.status == .done }
        return (0..<7).map { offset -> Int in
            guard let day = cal.date(byAdding: .day, value: offset - 6, to: today) else { return 0 }
            return completed.filter { cal.isDate($0.updatedAt, inSameDayAs: day) }.count
        }
    }

    // MARK: - Item suggestions

    /// Heuristic, context-aware suggestions to surface in the home list.
    /// Generates at most 2 suggestions so the card stays compact.
    var itemSuggestions: [ItemSuggestion] {
        var suggestions: [ItemSuggestion] = []
        let overdue = overdueItemCount
        if overdue > 0 {
            let label = overdue == 1 ? "1 overdue item" : "\(overdue) overdue items"
            suggestions.append(ItemSuggestion(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                icon: "exclamationmark.circle",
                color: .red,
                title: "Review overdue tasks",
                subtitle: label,
                action: .showOverdue
            ))
        }
        let thisWeek = dueThisWeekCount
        if suggestions.count < 2 && thisWeek > 0 {
            let label = thisWeek == 1 ? "1 item due in the next 7 days" : "\(thisWeek) items due in the next 7 days"
            suggestions.append(ItemSuggestion(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                icon: "calendar.badge.clock",
                color: .orange,
                title: "Due this week",
                subtitle: label,
                action: .showDueThisWeek
            ))
        }
        if suggestions.count < 2 && completionStreak == 0 && activeItems.count > 0 {
            suggestions.append(ItemSuggestion(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                icon: "star.fill",
                color: .orange,
                title: "Mark a top priority",
                subtitle: "Highlight what matters most today",
                action: .addItem(prefill: nil)
            ))
        }
        return suggestions
    }
}
