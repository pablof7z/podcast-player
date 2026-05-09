import UIKit
import UserNotifications
import os.log

@MainActor
enum BadgeManager {
    private static let logger = Logger.app("BadgeManager")
    private static let center = UNUserNotificationCenter.current()

    /// Updates the app icon badge to reflect the number of pending items.
    /// Requests notification permission if needed (badge requires it on iOS).
    static func sync(pendingCount: Int) async {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            do {
                try await center.requestAuthorization(options: [.badge])
            } catch {
                logger.error("requestAuthorization failed: \(error, privacy: .public)")
            }
        }
        do {
            try await center.setBadgeCount(pendingCount)
        } catch {
            logger.error("setBadgeCount(\(pendingCount)) failed: \(error, privacy: .public)")
        }
    }

    /// Clears the badge (sets to 0).
    static func clear() async {
        do {
            try await center.setBadgeCount(0)
        } catch {
            logger.error("setBadgeCount(0) failed: \(error, privacy: .public)")
        }
    }
}
