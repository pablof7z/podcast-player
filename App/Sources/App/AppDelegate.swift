import UIKit
import UserNotifications
import os.log

// MARK: - App Delegate

/// Handles UIKit lifecycle events that pure SwiftUI cannot receive:
/// - App-icon quick-action (home-screen shortcut) selection.
/// - Foreground notification presentation.
///
/// Wired in via `@UIApplicationDelegateAdaptor` in `AppMain`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger.app("AppDelegate")

    // MARK: - Pending shortcut

    /// Shortcut selected while the app was not running (cold-launch path).
    /// `RootView` reads this on `.onAppear` and clears it after routing.
    var pendingShortcutURL: URL?

    // MARK: - UIApplicationDelegate

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
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

    /// Routes notification taps. Only new-episode notifications carry an
    /// `episodeID` payload — for those we synthesize a `podcastr://episode/<uuid>`
    /// deep-link and post it through `shortcutURLNotification`, which `RootView`
    /// already observes and routes via `handleDeepLink(_:)`.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        let userInfo = response.notification.request.content.userInfo
        guard let episodeID = userInfo["episodeID"] as? String,
              UUID(uuidString: episodeID) != nil,
              let url = URL(string: "podcastr://episode/\(episodeID)")
        else { return }
        // Hop onto the main actor to post — RootView listens on the main queue.
        Task { @MainActor in
            NotificationCenter.default.post(
                name: AppDelegate.shortcutURLNotification,
                object: url
            )
        }
    }
}

// MARK: - Notification names

extension AppDelegate {
    /// Posted when a quick-action URL is ready to route.
    static let shortcutURLNotification = Notification.Name("AppDelegate.shortcutURL")
}
