import Foundation
import UserNotifications
import os.log

/// Local notifications for non-task surfaces (currently: Nostr contact requests).
@MainActor
enum NotificationService {

    private static let logger = Logger.app("NotificationService")

    private enum Content {
        static let approvalTitle = "New contact request"
        static let approvalBody = "Someone wants to reach your agent. Open the app to review."
        static let approvalIDPrefix = "nostr-approval:"
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
