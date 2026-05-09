import UIKit
import UserNotifications
import os.log

// MARK: - App Delegate

/// Handles UIKit lifecycle events that pure SwiftUI cannot receive:
/// - App-icon quick-action (home-screen shortcut) selection.
/// - `UNUserNotificationCenterDelegate` — handles notification action buttons
///   (Snooze 10m, Snooze 1h, Mark Done) so the user can act directly from a
///   lock-screen or banner notification without opening the app.
///
/// Wired in via `@UIApplicationDelegateAdaptor` in `AppMain`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger.app("AppDelegate")

    // MARK: - Shortcut type constants

    private enum ShortcutType {
        /// Matches the type defined in Info.plist for the "Add Item" quick action.
        static let addItem = "add-item"
        /// Matches the type defined in Info.plist for the "View Overdue" quick action.
        static let viewOverdue = "view-overdue"
        /// Matches the type defined in Info.plist for the "Open Agent" quick action.
        static let openAgent = "open-agent"
    }

    // MARK: - Pending shortcut

    /// Shortcut selected while the app was not running (cold-launch path).
    /// `RootView` reads this on `.onAppear` and clears it after routing.
    var pendingShortcutURL: URL?

    // MARK: - UIApplicationDelegate

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Register actionable notification categories once at launch so the
        // system knows about our Snooze / Mark Done buttons.
        NotificationService.registerCategories()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Called when the user selects a quick action while the app is in the background.
    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let handled = handle(shortcutItem)
        completionHandler(handled)
    }

    // MARK: - Private

    /// Converts a shortcut item into a deep-link URL and posts it via NotificationCenter
    /// so `RootView` can route without a direct reference to the delegate.
    /// Returns `true` if the shortcut type was recognised.
    @discardableResult
    private func handle(_ item: UIApplicationShortcutItem) -> Bool {
        let suffix = item.type.components(separatedBy: ".").last ?? ""
        let urlString: String
        switch suffix {
        case ShortcutType.addItem:    urlString = "podcastr://new-item"
        case ShortcutType.viewOverdue: urlString = "podcastr://overdue"
        case ShortcutType.openAgent:  urlString = "podcastr://agent"
        default: return false
        }
        guard let url = URL(string: urlString) else { return false }
        NotificationCenter.default.post(
            name: AppDelegate.shortcutURLNotification,
            object: url
        )
        return true
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

    /// Shows banners even when the app is in the foreground (e.g. during testing).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Dispatches notification action-button taps to `AppStateStore`.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard
            let uuidString = userInfo["itemID"] as? String,
            let itemID = UUID(uuidString: uuidString)
        else {
            logger.error("Notification action missing itemID in userInfo")
            completionHandler()
            return
        }

        let body = response.notification.request.content.body
        let actionID = response.actionIdentifier

        // Call completionHandler immediately — the system only requires it's called
        // before the app returns to the background; our async work below is safe to
        // complete independently.
        completionHandler()

        Task { @MainActor in
            await handleNotificationAction(actionID, itemID: itemID, body: body)
        }
    }

    @MainActor
    private func handleNotificationAction(_ actionID: String, itemID: UUID, body: String) async {
        switch actionID {
        case NotificationService.Action.snooze10m:
            logger.info("Snooze 10m for item \(itemID, privacy: .public)")
            await NotificationService.snoozeReminder(for: itemID, title: body, interval: 10 * 60)
            NotificationCenter.default.post(
                name: AppDelegate.reminderSnoozedNotification,
                object: nil,
                userInfo: ["itemID": itemID, "snoozeInterval": 10 * 60.0]
            )

        case NotificationService.Action.snooze1h:
            logger.info("Snooze 1h for item \(itemID, privacy: .public)")
            await NotificationService.snoozeReminder(for: itemID, title: body, interval: 3_600)
            NotificationCenter.default.post(
                name: AppDelegate.reminderSnoozedNotification,
                object: nil,
                userInfo: ["itemID": itemID, "snoozeInterval": 3_600.0]
            )

        case NotificationService.Action.markDone:
            logger.info("Mark done for item \(itemID, privacy: .public)")
            NotificationCenter.default.post(
                name: AppDelegate.reminderMarkDoneNotification,
                object: nil,
                userInfo: ["itemID": itemID]
            )

        default:
            break // Default tap — system opens the app; no extra action needed.
        }
    }
}

// MARK: - Notification names

extension AppDelegate {
    /// Posted when a quick-action URL is ready to route.
    static let shortcutURLNotification = Notification.Name("AppDelegate.shortcutURL")

    /// Posted when the user taps a Snooze action on a reminder notification.
    /// `userInfo` contains `"itemID": UUID` and `"snoozeInterval": TimeInterval`.
    static let reminderSnoozedNotification = Notification.Name("AppDelegate.reminderSnoozed")

    /// Posted when the user taps "Mark Done" on a reminder notification.
    /// `userInfo` contains `"itemID": UUID`.
    static let reminderMarkDoneNotification = Notification.Name("AppDelegate.reminderMarkDone")
}
