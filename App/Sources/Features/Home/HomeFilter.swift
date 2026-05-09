import Foundation
import SwiftUI

// MARK: - HomeFilter

/// Filter applied to the active-items list on the Home screen.
///
/// `.all` is the default (no filter). The other cases narrow the visible items
/// to a meaningful subset without changing the underlying data.
enum HomeFilter: Equatable {
    /// Show all pending items (default, no filtering).
    case all
    /// Show only items marked as priority.
    case priority
    /// Show only items that have a reminder set.
    case reminders
    /// Show only items whose due date has passed.
    case overdue
    /// Show only items due on the current calendar day (excluding already-overdue items).
    case dueToday
    /// Show only items due within the next 7 days (excluding already-overdue items).
    case dueThisWeek
    /// Show only items requested by a specific friend.
    case friend(id: UUID, displayName: String)
    /// Show only items that have a specific tag.
    case tag(String)
    /// Show only items with a specific color label.
    case color(ItemColorTag)

    // MARK: - Display

    /// Short label shown in the toolbar filter menu and active-filter chip.
    var label: String {
        switch self {
        case .all:              return "All"
        case .priority:         return "Priority"
        case .reminders:        return "Reminders"
        case .overdue:          return "Overdue"
        case .dueToday:         return "Due Today"
        case .dueThisWeek:      return "Due This Week"
        case .friend(_, let n): return n
        case .tag(let t):       return "#\(t)"
        case .color(let c):     return c.label
        }
    }

    /// SF Symbol name for the menu item.
    var icon: String {
        switch self {
        case .all:          return "line.3.horizontal.decrease.circle"
        case .priority:     return "star.fill"
        case .reminders:    return "bell.fill"
        case .overdue:      return "clock.badge.exclamationmark.fill"
        case .dueToday:     return "calendar.badge.clock"
        case .dueThisWeek:  return "calendar.badge.clock"
        case .friend:       return "person.fill"
        case .tag:          return "tag.fill"
        case .color:        return "circle.fill"
        }
    }

    /// The accent color used for the active-filter chip.
    ///
    /// Color filters surface the actual swatch color so the chip reflects the
    /// chosen label; `.dueThisWeek` uses orange for urgency context; every other
    /// filter defaults to the app's accent color.
    var chipColor: Color {
        if case .color(let c) = self { return c.color }
        if case .overdue     = self { return .red }
        if case .priority    = self { return .orange }
        if case .dueToday    = self { return .orange }
        if case .dueThisWeek = self { return .orange }
        return Color.accentColor
    }

    /// Whether this filter is non-trivial (i.e. not `.all`).
    var isActive: Bool {
        if case .all = self { return false }
        return true
    }

    /// Tag value for `.tag` filters; nil for all other cases.
    var tagValue: String? {
        if case .tag(let t) = self { return t }
        return nil
    }

    // MARK: - Predicate

    /// Returns `true` if the given item should be visible under this filter.
    func matches(_ item: Item) -> Bool {
        switch self {
        case .all:
            return true
        case .priority:
            return item.isPriority
        case .reminders:
            return item.reminderAt != nil
        case .overdue:
            return item.isOverdue
        case .dueToday:
            guard let due = item.dueAt, !item.isOverdue else { return false }
            return Calendar.current.isDateInToday(due)
        case .dueThisWeek:
            // Must have a due date, must NOT already be overdue (overdue filter owns those),
            // and due within 7 days from now.
            guard let due = item.dueAt, !item.isOverdue else { return false }
            return due <= Date().addingTimeInterval(7 * 24 * 60 * 60)
        case .friend(let id, _):
            return item.requestedByFriendID == id
        case .tag(let tag):
            return item.tags.contains(tag)
        case .color(let colorTag):
            return item.colorTag == colorTag
        }
    }

    // MARK: - Empty-state text

    /// Title shown in `ContentUnavailableView` when no items match the active filter.
    var emptyTitle: String {
        switch self {
        case .all:              return "Nothing to do"
        case .priority:         return "No priority items"
        case .reminders:        return "No reminders set"
        case .overdue:          return "No overdue items"
        case .dueToday:         return "Nothing due today"
        case .dueThisWeek:      return "Nothing due this week"
        case .friend(_, let n): return "Nothing from \(n)"
        case .tag(let t):       return "No items tagged #\(t)"
        case .color(let c):     return "No \(c.label.lowercased()) items"
        }
    }

    /// Supporting description shown below the empty-state title.
    var emptyDescription: String {
        switch self {
        case .all:
            return "Tap + to add an item, or ask your agent to create one for you."
        case .priority:
            return "Swipe right on any item or use the context menu to mark it as priority."
        case .reminders:
            return "Open an item's detail view to set a reminder."
        case .overdue:
            return "Items with a past due date appear here. Great job staying on top of things!"
        case .dueToday:
            return "Items due on today's date will appear here."
        case .dueThisWeek:
            return "Items with a due date in the next 7 days will appear here."
        case .friend:
            return "Items requested by this friend will appear here."
        case .tag:
            return "Items with this tag will appear here."
        case .color:
            return "Items with this color label will appear here. Open an item to assign a color."
        }
    }
}
