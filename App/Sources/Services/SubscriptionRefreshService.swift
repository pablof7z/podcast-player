import Foundation
import UIKit
import os.log

// MARK: - SubscriptionRefreshService

/// Background poller for the user's podcast subscriptions.
///
/// Owns the foreground refresh loop:
///   1. On `startPeriodicRefresh(...)` we kick a `Task` that waits one
///      `interval` then calls `refreshAll`. Re-entrant calls cancel and
///      replace the in-flight task so the call site is idempotent.
///   2. We register for `UIApplication.didEnterBackgroundNotification` to
///      cancel the loop when the app suspends, and
///      `UIApplication.willEnterForegroundNotification` to restart it.
///   3. Every refresh round runs `FeedClient.fetch` against each subscription
///      in parallel, bounded by `maxConcurrent` so a 200-subscription user
///      doesn't open 200 simultaneous sockets.
///
/// `FeedClient.fetch` is async + `Sendable` — the network hop happens off the
/// main actor. The service hops back to the main actor to apply each parsed
/// result via `AppStateStore`'s mutation methods, which keeps the store's
/// `didSet` persistence path single-threaded.
///
/// A future `BackgroundTasks` (`BGAppRefreshTask`) wiring would call
/// `refreshAll` as well; that work is intentionally out of scope here.
@MainActor
final class SubscriptionRefreshService {

    // MARK: Singleton

    static let shared = SubscriptionRefreshService()

    // MARK: Configuration

    /// Default polling cadence when callers don't override `interval` —
    /// 30 minutes mirrors the baseline-podcast-features brief §2.
    static let defaultInterval: Duration = .seconds(30 * 60)

    // MARK: State

    private static let logger = Logger.app("SubscriptionRefreshService")
    private let client: FeedClient
    private var pollingTask: Task<Void, Never>?
    private var foregroundObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    /// Cached so a foreground-restart uses the same configuration the caller
    /// originally supplied.
    private weak var registeredStore: AppStateStore?
    private var registeredInterval: Duration = SubscriptionRefreshService.defaultInterval

    // MARK: Init

    init(client: FeedClient = FeedClient()) {
        self.client = client
    }

    // No `deinit` — the singleton lives for the lifetime of the process. The
    // main-actor isolation of stored properties means a nonisolated `deinit`
    // can't observe them under Swift 6 strict concurrency anyway, so leaving
    // it off avoids region-isolation noise in builds.

    // MARK: - Public API

    /// Refreshes a single subscription. Idempotent — issues a conditional
    /// GET via the subscription's stored `etag` / `lastModified`. A `304`
    /// only bumps `lastRefreshedAt`; an updated feed upserts every parsed
    /// episode and writes the new cache headers back via `updateSubscription`.
    func refresh(_ subscriptionID: UUID, store: AppStateStore) async throws {
        guard let subscription = store.subscription(id: subscriptionID) else {
            return
        }
        let result = try await client.fetch(subscription)
        switch result {
        case .notModified(let lastRefreshedAt):
            var bumped = subscription
            bumped.lastRefreshedAt = lastRefreshedAt
            store.updateSubscription(bumped)
        case .updated(let updatedSubscription, let episodes, _):
            // Snapshot the existing GUIDs *before* the upsert so the delta is
            // accurate. Anything in `episodes` whose GUID isn't already known
            // is brand-new and a notification candidate.
            let priorGUIDs = Set(store.episodes(forSubscription: subscriptionID).map(\.guid))
            store.upsertEpisodes(
                episodes,
                forSubscription: subscriptionID,
                evaluateAutoDownload: true
            )
            store.updateSubscription(updatedSubscription)
            notifyIfNeeded(
                priorGUIDs: priorGUIDs,
                incoming: episodes,
                subscription: updatedSubscription
            )
        }
    }

    /// Refreshes every subscription in `store.sortedSubscriptions`, bounded
    /// to `maxConcurrent` in-flight fetches. Errors are logged and swallowed
    /// per-subscription so one failing feed doesn't sink the whole sweep.
    func refreshAll(store: AppStateStore, maxConcurrent: Int = 4) async {
        let subscriptions = store.sortedSubscriptions
        guard !subscriptions.isEmpty else { return }
        let bounded = max(1, maxConcurrent)
        let client = self.client

        // Walk the subscription list in chunks of `bounded`, fanning each
        // chunk into a TaskGroup that performs the (off-actor) fetches in
        // parallel. The group returns a parsed result per subscription; we
        // then apply each mutation on the main actor sequentially. Keeping
        // the apply step single-threaded preserves the store's didSet
        // persistence ordering.
        var index = 0
        while index < subscriptions.count {
            let upper = min(index + bounded, subscriptions.count)
            let slice = Array(subscriptions[index..<upper])
            let outcomes = await withTaskGroup(
                of: SubscriptionRefreshOutcome.self,
                returning: [SubscriptionRefreshOutcome].self
            ) { group in
                for subscription in slice {
                    group.addTask {
                        do {
                            let result = try await client.fetch(subscription)
                            return .success(originalID: subscription.id, original: subscription, result: result)
                        } catch {
                            return .failure(originalID: subscription.id, error: error)
                        }
                    }
                }
                var collected: [SubscriptionRefreshOutcome] = []
                collected.reserveCapacity(slice.count)
                for await outcome in group {
                    collected.append(outcome)
                }
                return collected
            }

            for outcome in outcomes {
                apply(outcome: outcome, store: store)
            }

            index = upper
        }
    }

    /// Starts the periodic refresh loop. Idempotent — the existing in-flight
    /// loop is cancelled and replaced if `start` is called twice. Also
    /// registers for foreground / background lifecycle notifications so the
    /// loop pauses while the app is suspended.
    func startPeriodicRefresh(
        store: AppStateStore,
        interval: Duration = SubscriptionRefreshService.defaultInterval
    ) {
        registeredStore = store
        registeredInterval = interval
        registerLifecycleObserversIfNeeded()
        startLoop(store: store, interval: interval)
    }

    /// Cancels the active polling loop, if any. Lifecycle observers stay
    /// registered so a later `startPeriodicRefresh` can re-arm without
    /// re-installing them.
    func stopPeriodicRefresh() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Private

    private func apply(outcome: SubscriptionRefreshOutcome, store: AppStateStore) {
        switch outcome {
        case .success(_, let original, let result):
            switch result {
            case .notModified(let lastRefreshedAt):
                var bumped = original
                bumped.lastRefreshedAt = lastRefreshedAt
                store.updateSubscription(bumped)
            case .updated(let updatedSubscription, let episodes, _):
                // Same delta-before-upsert dance as `refresh(_:)`: snapshot
                // the old GUID set, then write, then notify on the diff.
                let priorGUIDs = Set(
                    store.episodes(forSubscription: updatedSubscription.id).map(\.guid)
                )
                store.upsertEpisodes(
                    episodes,
                    forSubscription: updatedSubscription.id,
                    evaluateAutoDownload: true
                )
                store.updateSubscription(updatedSubscription)
                notifyIfNeeded(
                    priorGUIDs: priorGUIDs,
                    incoming: episodes,
                    subscription: updatedSubscription
                )
            }
        case .failure(let originalID, let error):
            Self.logger.notice(
                "refresh failed for \(originalID, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Fires new-episode notifications for the GUIDs that didn't appear in the
    /// store before this refresh. No-ops when notifications are disabled on
    /// the subscription, when the prior set is empty (first-ever fetch — the
    /// user just subscribed and doesn't want a flood), or when nothing's new.
    private func notifyIfNeeded(
        priorGUIDs: Set<String>,
        incoming: [Episode],
        subscription: PodcastSubscription
    ) {
        guard subscription.notificationsEnabled else { return }
        // First fetch: every episode would be "new". That's spammy and not
        // what the user wants right after subscribing — skip.
        guard !priorGUIDs.isEmpty else { return }
        let newOnes = incoming
            .filter { !priorGUIDs.contains($0.guid) }
            .sorted { $0.pubDate > $1.pubDate }
        guard !newOnes.isEmpty else { return }
        Task {
            await NotificationService.notifyNewEpisodes(newOnes, subscription: subscription)
        }
    }

    private func startLoop(store: AppStateStore, interval: Duration) {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            // First refresh fires after `interval` rather than immediately —
            // app launch already pulls feeds when the user opens Library
            // (pull-to-refresh, baseline §2). A 30-minute warm-up keeps
            // launch quiet.
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                if Task.isCancelled { return }
                guard let self else { return }
                await self.refreshAll(store: store)
            }
        }
    }

    private func registerLifecycleObserversIfNeeded() {
        if backgroundObserver == nil {
            backgroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.stopPeriodicRefresh()
                }
            }
        }
        if foregroundObserver == nil {
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self,
                          let store = self.registeredStore
                    else { return }
                    self.startLoop(store: store, interval: self.registeredInterval)
                }
            }
        }
    }
}

// MARK: - Outcome

/// Per-subscription result of a single `refreshAll` round. Carrying the
/// original subscription through lets the apply step bump `lastRefreshedAt`
/// on the cached value without a second store lookup, which would race with
/// concurrent mutations the caller might have made between the fetch
/// dispatch and the result arrival.
private enum SubscriptionRefreshOutcome: Sendable {
    case success(originalID: UUID, original: PodcastSubscription, result: FeedClient.FeedFetchResult)
    case failure(originalID: UUID, error: Error)
}
