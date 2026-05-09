import Foundation

// MARK: - PendingReminder

/// A view-model representing a pending `UNNotificationRequest` for a reminder.
struct PendingReminder: Identifiable {
    let id: String
    let itemID: UUID?
    let title: String
    let fireDate: Date
}

// MARK: - ReminderDateBucket

/// Forward-looking date grouping for the pending-reminders list.
enum ReminderDateBucket: String, CaseIterable {
    case today = "Today"
    case tomorrow = "Tomorrow"
    case thisWeek = "This Week"
    case later = "Later"

    /// Assigns a pending reminder to its bucket relative to `now`.
    static func bucket(for date: Date, now: Date, calendar: Calendar) -> ReminderDateBucket {
        if calendar.isDateInToday(date) { return .today }
        if calendar.isDateInTomorrow(date) { return .tomorrow }
        let weekOut = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        if date <= weekOut { return .thisWeek }
        return .later
    }
}
