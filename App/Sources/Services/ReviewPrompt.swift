import StoreKit
import UIKit

/// Requests an in-app review at meaningful, well-timed moments rather than
/// after a generic action count. Each trigger fires at most once per install
/// (regardless of cooldown), and the underlying `SKStoreReviewController` call
/// is further gated by a 60-day cooldown so users are never pestered.
///
/// Trigger moments:
///   - **10th item completed** — user has established a real usage habit.
///   - **3-day streak** — first "streak milestone"; also fires at 7 days.
///   - **First item shared** — strong positive signal; user is proud of something.
@MainActor
enum ReviewPrompt {

    // MARK: - UserDefaults keys

    private static let lastRequestKey    = "reviewPrompt.lastRequestDate"
    private static let requestCountKey   = "reviewPrompt.requestCount"

    // Per-trigger "has already fired" flags
    private static let firedAt10Key      = "reviewPrompt.firedAt10Completions"
    private static let firedAt3StreakKey = "reviewPrompt.firedAt3DayStreak"
    private static let firedAt7StreakKey = "reviewPrompt.firedAt7DayStreak"
    private static let firedFirstShareKey = "reviewPrompt.firedFirstShare"

    // MARK: - Configuration

    /// Minimum seconds between successive review prompts (60 days).
    private static let cooldownSeconds: Double = 60 * 86_400

    /// Single access point for UserDefaults — avoids repeated `.standard` lookups.
    private static var defaults: UserDefaults { .standard }

    // MARK: - Public trigger points

    /// Call when an item is marked done. Pass the *new* total completed count.
    /// Fires at the 10th completion.
    static func recordItemCompleted(totalCompletions: Int) {
        guard !defaults.bool(forKey: firedAt10Key) else { return }
        guard totalCompletions >= 10 else { return }
        defaults.set(true, forKey: firedAt10Key)
        requestIfCooldownPassed()
    }

    /// Call after computing the current streak. Fires at the 3-day and 7-day
    /// milestones — each at most once per install.
    static func recordStreakMilestone(_ streak: Int) {
        if streak >= 7, !defaults.bool(forKey: firedAt7StreakKey) {
            defaults.set(true, forKey: firedAt7StreakKey)
            requestIfCooldownPassed()
        } else if streak >= 3, !defaults.bool(forKey: firedAt3StreakKey) {
            defaults.set(true, forKey: firedAt3StreakKey)
            requestIfCooldownPassed()
        }
    }

    /// Call when the user shares an item. Fires on the very first share.
    static func recordItemShared() {
        guard !defaults.bool(forKey: firedFirstShareKey) else { return }
        defaults.set(true, forKey: firedFirstShareKey)
        requestIfCooldownPassed()
    }

    // MARK: - Private

    /// Presents the review prompt only if the 60-day cooldown has elapsed.
    private static func requestIfCooldownPassed(in scene: UIWindowScene? = nil) {
        let lastRequest = defaults.double(forKey: lastRequestKey)
        let elapsed = lastRequest == 0 ? Double.infinity : Date().timeIntervalSince1970 - lastRequest
        guard elapsed > cooldownSeconds else { return }

        defaults.set(Date().timeIntervalSince1970, forKey: lastRequestKey)
        defaults.set(defaults.integer(forKey: requestCountKey) + 1, forKey: requestCountKey)

        if let scene {
            SKStoreReviewController.requestReview(in: scene)
        } else {
            SKStoreReviewController.requestReview()
        }
    }
}
