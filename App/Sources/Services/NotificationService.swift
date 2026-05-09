import Foundation
import UserNotifications
import os.log

/// Schedules and cancels local reminder notifications for Items.
///
/// Permissions are requested lazily — only when a user actually sets a
/// reminder — so the app never bothers users who don't use this feature.
///
/// Notification identifiers are namespaced as "reminder:<item-uuid>" so
/// cancellation is exact and never touches unrelated system notifications.
///
/// Actionable reminders: notifications include "Snooze 10m", "Snooze 1h",
/// and "Mark Done" action buttons that users can tap without opening the app.
@MainActor
enum NotificationService {

    private static let logger = Logger.app("NotificationService")

    // MARK: - Constants

    private enum Content {
        static let reminderTitle = "Reminder"
        static let reminderDefaultBody = "You have a task due."
        static let approvalTitle = "New contact request"
        static let approvalBody = "Someone wants to reach your agent. Open the app to review."
        static let reminderIDPrefix = "reminder:"
        static let approvalIDPrefix = "nostr-approval:"
    }

    /// Notification identifier prefix for all reminder requests. Used by
    /// `NotificationSettingsView` to filter displayed requests.
    static let reminderIDPrefix = Content.reminderIDPrefix

    // MARK: - Notification category & action identifiers

    enum Category {
        /// Applied to all reminder notifications.
        static let reminder = "REMINDER"
    }

    enum Action {
        static let snooze10m = "SNOOZE_10M"
        static let snooze1h  = "SNOOZE_1H"
        static let markDone  = "MARK_DONE"
    }

    // MARK: - Category registration

    /// Registers the `REMINDER` notification category with its action buttons.
    /// Call once at app launch (from `AppDelegate.application(_:didFinishLaunchingWithOptions:)`).
    static func registerCategories() {
        let snooze10 = UNNotificationAction(
            identifier: Action.snooze10m,
            title: "Snooze 10 min",
            options: []
        )
        let snooze1h = UNNotificationAction(
            identifier: Action.snooze1h,
            title: "Snooze 1 hour",
            options: []
        )
        let markDone = UNNotificationAction(
            identifier: Action.markDone,
            title: "Mark Done",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: Category.reminder,
            actions: [snooze10, snooze1h, markDone],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Identifier

    static func identifier(for itemID: UUID) -> String {
        "\(Content.reminderIDPrefix)\(itemID.uuidString)"
    }

    /// Extracts the item UUID from a reminder notification identifier, or `nil` if not a reminder.
    static func itemID(fromIdentifier id: String) -> UUID? {
        guard id.hasPrefix(Content.reminderIDPrefix) else { return nil }
        let uuidString = String(id.dropFirst(Content.reminderIDPrefix.count))
        return UUID(uuidString: uuidString)
    }

    // MARK: - Authorization

    /// Requests authorization for alerts, sounds, and badges.
    /// Returns `true` if permission was granted (or already granted).
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                logger.error("requestAuthorization failed: \(error, privacy: .public)")
                return false
            }
        @unknown default:
            return false
        }
    }

    // MARK: - Schedule

    /// Schedules a reminder notification for an item at the given date.
    ///
    /// Automatically cancels any existing notification for the same item
    /// before scheduling a new one, so calling this on edit is idempotent.
    ///
    /// - Parameters:
    ///   - itemID: The item's UUID (used as the notification identifier).
    ///   - title: The item title shown in the notification body.
    ///   - date: The anchor date / time for the first fire.
    ///   - recurrence: How often the notification repeats. Defaults to `.none` (one-shot).
    /// - Returns: `false` if notification permission was denied.
    @discardableResult
    static func scheduleReminder(
        for itemID: UUID,
        title: String,
        at date: Date,
        recurrence: ItemRecurrence = .none
    ) async -> Bool {
        // For non-repeating reminders the anchor must be in the future.
        // For repeating ones we still require it — the user sets a meaningful
        // first-fire time (e.g. "every Monday at 9am") and we honour the
        // weekday / day-of-month extracted from that date.
        guard date > Date() || recurrence != .none else { return false }

        let granted = await requestAuthorization()
        guard granted else { return false }

        // Cancel any previous reminder for this item before scheduling.
        cancel(for: itemID)

        let content = UNMutableNotificationContent()
        content.title = Content.reminderTitle
        content.body = title.isEmpty ? Content.reminderDefaultBody : title
        content.sound = .default
        content.categoryIdentifier = Category.reminder
        // Embed the item UUID in userInfo so the delegate can act without parsing the identifier.
        content.userInfo = ["itemID": itemID.uuidString]

        // Build the DateComponents that match the recurrence pattern.
        // `UNCalendarNotificationTrigger(repeats: true)` fires whenever
        // *all* specified components match the current date — so omitting
        // the `year`/`month`/`day` from a daily trigger makes it fire every day.
        let cal = Calendar.current
        let trigger: UNCalendarNotificationTrigger
        switch recurrence {
        case .none:
            // One-shot: match full date & time.
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        case .daily:
            // Fire every day at the same hour and minute.
            let comps = cal.dateComponents([.hour, .minute], from: date)
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        case .weekdays:
            // Fire each weekday at the same time. We schedule five separate
            // notifications (Mon–Fri) and use a compound identifier suffix.
            // The primary identifier fires on the weekday of `date`; the others
            // are scheduled by `scheduleWeekdayReminders` below.
            let comps = cal.dateComponents([.hour, .minute], from: date)
            // Use a dedicated helper so we can fan out to Mon–Fri triggers.
            return await scheduleWeekdayReminders(
                for: itemID, title: title, timeComponents: comps
            )

        case .weekly:
            // Fire once a week on the same weekday + time.
            let comps = cal.dateComponents([.weekday, .hour, .minute], from: date)
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        case .monthly:
            // Fire once a month on the same day-of-month + time.
            let comps = cal.dateComponents([.day, .hour, .minute], from: date)
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        }

        let request = UNNotificationRequest(
            identifier: identifier(for: itemID),
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            logger.error("scheduleReminder failed for item \(itemID, privacy: .public): \(error, privacy: .public)")
            return false
        }
    }

    // MARK: - Weekday fan-out

    /// Schedules five separate weekday (Mon–Fri) repeating reminders.
    ///
    /// Each uses a deterministic identifier suffix (`reminder:<uuid>:wd<N>`)
    /// so `cancel(for:)` can remove all five via the `wd-` prefix scan.
    private static func scheduleWeekdayReminders(
        for itemID: UUID,
        title: String,
        timeComponents: DateComponents
    ) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = Content.reminderTitle
        content.body = title.isEmpty ? Content.reminderDefaultBody : title
        content.sound = .default
        content.categoryIdentifier = Category.reminder
        content.userInfo = ["itemID": itemID.uuidString]

        // Weekday values: 2 = Monday … 6 = Friday (Calendar.current, Sunday = 1).
        let weekdays = 2...6
        var allOk = true
        for wd in weekdays {
            var comps = timeComponents
            comps.weekday = wd
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let id = "\(Content.reminderIDPrefix)\(itemID.uuidString):wd\(wd)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                logger.error("weekday reminder wd\(wd) failed for \(itemID, privacy: .public): \(error, privacy: .public)")
                allOk = false
            }
        }
        return allOk
    }

    // MARK: - Snooze

    /// Re-schedules a reminder `interval` seconds from now, using the original item title from the notification.
    @discardableResult
    static func snoozeReminder(for itemID: UUID, title: String, interval: TimeInterval) async -> Bool {
        let snoozeDate = Date().addingTimeInterval(interval)
        return await scheduleReminder(for: itemID, title: title, at: snoozeDate)
    }

    // MARK: - Cancel

    /// Cancels all pending reminders for the given item, including any
    /// weekday fan-out notifications (`reminder:<uuid>:wd<N>`).
    static func cancel(for itemID: UUID) {
        let base = identifier(for: itemID)
        // Weekday variants use the base prefix + ":wd<N>".
        let weekdayIDs = (2...6).map { "\(base):wd\($0)" }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [base] + weekdayIDs)
    }

    // MARK: - Batch cancel

    /// Cancels pending reminders for multiple items. Useful during clearAllData.
    static func cancelAll(for itemIDs: [UUID]) {
        var ids: [String] = []
        for itemID in itemIDs {
            let base = identifier(for: itemID)
            ids.append(base)
            ids.append(contentsOf: (2...6).map { "\(base):wd\($0)" })
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Nostr approval

    /// Fires an immediate notification when an unknown Nostr sender requests access.
    /// Deduped by pubkey — won't fire again if one is already pending for that key.
    static func notifyPendingApproval(pubkeyHex: String) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let id = "\(Content.approvalIDPrefix)\(pubkeyHex)"
        guard !pending.contains(where: { $0.identifier == id }) else { return }

        let granted = await requestAuthorization()
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = Content.approvalTitle
        content.body = Content.approvalBody
        content.sound = .default

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            logger.error("notifyPendingApproval failed for pubkey \(pubkeyHex, privacy: .public): \(error, privacy: .public)")
        }
    }
}
