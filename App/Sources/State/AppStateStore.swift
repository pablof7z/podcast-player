import Foundation
import Observation
import WidgetKit
import os.log

// MARK: - Navigation intents

/// Ephemeral, non-persisted navigation requests dispatched by deep-links,
/// home-screen quick actions, and Spotlight continuations.
///
/// `HomeView` (and any other consumer) observes this via `.onChange` and
/// clears it immediately after acting so the intent fires exactly once.
enum HomeAction: Equatable {
    /// Open the inline "Add Item" row pre-filled with an optional title.
    case addItem(prefill: String?)
    /// Switch the active filter to `.overdue` so past-due items are surfaced.
    case showOverdue
    /// Switch the active filter to `.dueThisWeek` so upcoming items are surfaced.
    case showDueThisWeek
    /// Open the AI agent chat sheet.
    case openAgent
    /// Open the detail sheet for a specific item (e.g. from a Spotlight tap).
    case openItem(UUID)
}

/// Pre-filled data for an incoming friend invite deep-link.
/// Consumed by `AgentFriendsView` to open `AddFriendSheet` with values already typed in.
struct PendingFriendInvite: Equatable, Identifiable {
    /// Bech32-encoded public key of the person being added (full `npub1…` string).
    let npub: String
    /// Display name suggested by the invite link; the user can change it before adding.
    let name: String?

    /// Stable identity derived from the public key — two invites for the same key are the same.
    var id: String { npub }
}

/// Single source of truth. All mutations route through here so the `didSet`
/// observer can persist automatically. UI and agent both call the same methods.
@MainActor
@Observable
final class AppStateStore {

    private static let logger = Logger.app("AppStateStore")

    // MARK: - Navigation

    /// Pending navigation intent set by deep-link / quick-action routing.
    /// Consumed and cleared by `HomeView` on `.onChange`.
    var pendingHomeAction: HomeAction?

    /// Pending friend invite dispatched by an `apptemplate://friend/add` deep-link.
    /// Consumed and cleared by `AgentFriendsView` on `.onChange` so it fires exactly once.
    var pendingFriendInvite: PendingFriendInvite?

    var state: AppState {
        didSet {
            Persistence.save(state)
            SpotlightIndexer.reindex(state: state)
            Task { await BadgeManager.sync(pendingCount: self.activeItems.count) }
            // Notify WidgetKit so home/lock-screen widgets refresh immediately on
            // every state mutation rather than waiting for the 15-minute poll.
            WidgetCenter.shared.reloadAllTimelines()
            // Push the current settings to iCloud KV store. The sync service
            // internally no-ops if an inbound merge is already in progress.
            iCloudSettingsSync.shared.push(state.settings)
        }
    }

    /// Retained observer token for iCloud external-change notifications.
    private var iCloudObserver: NSObjectProtocol?
    /// Retained observer tokens for notification-action events from AppDelegate.
    private var notificationActionObservers: [NSObjectProtocol] = []

    init() {
        var loadedState: AppState
        do {
            loadedState = try Persistence.load()
        } catch {
            Self.logger.error("Persistence.load failed: \(error, privacy: .public) — starting with empty state")
            loadedState = AppState()
        }
        Self.migrateLegacyOpenRouterSecretIfNeeded(in: &loadedState)
        // Start iCloud KV sync before assigning state so that the first
        // push (triggered by the `didSet` below) reflects the merged values.
        iCloudSettingsSync.shared.start(mergingInto: &loadedState.settings)
        self.state = loadedState
        // Prune agent-activity entries older than 30 days so the persisted log
        // doesn't grow unboundedly across many months of use. This fires one
        // Persistence.save only when stale entries are actually found.
        pruneStaleActivityEntries()
        // Seed Spotlight with whatever was persisted before this launch — the
        // index can be wiped out independently of our app data (device reset,
        // reinstall, user clearing system search).
        SpotlightIndexer.reindex(state: loadedState)
        // Observe external iCloud changes so settings stay in sync while the
        // app is running on multiple devices simultaneously.
        iCloudObserver = NotificationCenter.default.addObserver(
            forName: iCloudSettingsSync.settingsDidChangeExternallyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyExternalSettingsChange()
            }
        }
        // Observe notification action buttons (Snooze / Mark Done) dispatched
        // by AppDelegate after the user acts on a banner or lock-screen notification.
        subscribeToNotificationActions()
    }

    // MARK: - Notification action subscription

    private func subscribeToNotificationActions() {
        let markDone = NotificationCenter.default.addObserver(
            forName: AppDelegate.reminderMarkDoneNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let itemID = note.userInfo?["itemID"] as? UUID else { return }
            MainActor.assumeIsolated {
                self.setItemStatus(itemID, status: .done)
                self.clearReminderDate(for: itemID)
                Haptics.success()
                Self.logger.info("Notification action: marked item \(itemID, privacy: .public) done")
            }
        }

        let snoozed = NotificationCenter.default.addObserver(
            forName: AppDelegate.reminderSnoozedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let itemID = note.userInfo?["itemID"] as? UUID,
                  let interval = note.userInfo?["snoozeInterval"] as? TimeInterval else { return }
            MainActor.assumeIsolated {
                let snoozeDate = Date().addingTimeInterval(interval)
                self.setReminderAt(itemID, date: snoozeDate)
                Haptics.selection()
                Self.logger.info("Notification action: snoozed item \(itemID, privacy: .public) by \(interval)s")
            }
        }

        notificationActionObservers = [markDone, snoozed]
    }

    /// Pulls the latest iCloud values into `state.settings`.
    /// Called when `iCloudSettingsSync` reports an external change.
    private func applyExternalSettingsChange() {
        let sync = iCloudSettingsSync.shared
        sync.isApplyingRemoteChange = true
        defer { sync.isApplyingRemoteChange = false }
        var updated = state.settings
        sync.merge(from: NSUbiquitousKeyValueStore.default, into: &updated)
        guard updated != state.settings else { return }
        Self.logger.info("iCloudSettingsSync: applying remote settings update")
        // Assign directly (bypassing updateSettings) to avoid a redundant push.
        state.settings = updated
    }

    private static func migrateLegacyOpenRouterSecretIfNeeded(in state: inout AppState) {
        let legacyKey = state.settings.legacyOpenRouterAPIKey.trimmedOrEmpty
        guard !legacyKey.isEmpty else {
            state.settings.legacyOpenRouterAPIKey = nil
            return
        }

        do {
            try OpenRouterCredentialStore.saveAPIKey(legacyKey)
            state.settings.markOpenRouterManual()
        } catch {
            logger.error("Failed to migrate legacy OpenRouter key to keychain: \(error, privacy: .public)")
            state.settings.clearOpenRouterCredential()
        }
        Persistence.save(state)
    }

    // MARK: - Settings

    func updateSettings(_ settings: Settings) {
        state.settings = settings
    }

    /// Wipes all user data while preserving API credentials and Nostr identity.
    func clearAllData() {
        let itemIDs = state.items.compactMap { $0.reminderAt != nil ? $0.id : nil }
        NotificationService.cancelAll(for: itemIDs)
        let preserved = state.settings
        state = AppState()
        state.settings = preserved
        Persistence.save(state)
        SpotlightIndexer.clearAll()
    }
}
