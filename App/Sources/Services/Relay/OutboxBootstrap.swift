import Foundation

/// Steps 6–7 of the relay bootstrap, split out from `RelayBootstrapService`
/// to stay under the file-length limit. Opens the long-lived follows'
/// kind:10002 subscription on indexer relays, performs the initial outbox
/// computation after a short settle window, then drives the periodic
/// cleanup loop until the bootstrap task is cancelled (sign-out / identity
/// switch).
@MainActor
enum OutboxBootstrap {
    static func run(
        router: OutboxRouter,
        pool: RelayPool,
        configStore: RelayConfigStore,
        followPubkeys: [String],
        settleDelay: Duration,
        cleanupInterval: Duration,
        fallbackIndexers: [String]
    ) async {
        guard !followPubkeys.isEmpty else { return }

        let configuredIndexers = configStore.relays.filter(\.indexer).map(\.url)
        let outboxIndexers: [String]
        if configuredIndexers.isEmpty {
            // The pinned-invariants pass guarantees `purplepag.es` is always
            // an indexer in `configStore.relays`, so this branch is effectively
            // dead today. Open the fallbacks as transient just in case a future
            // change relaxes that invariant — `pool.subscribe` silently skips
            // URLs with no connection, which would leave outbox quietly broken.
            outboxIndexers = fallbackIndexers
            pool.connectTransient(urls: fallbackIndexers)
        } else {
            outboxIndexers = configuredIndexers
        }
        FollowRelaySubscription.subscribe(
            pool: pool,
            indexerURLs: outboxIndexers,
            followPubkeys: followPubkeys,
            router: router
        )

        try? await Task.sleep(for: settleDelay)
        if Task.isCancelled { return }
        recomputeAndApply(
            router: router,
            pool: pool,
            configStore: configStore,
            followPubkeys: followPubkeys
        )

        await runCleanupLoop(
            router: router,
            pool: pool,
            configStore: configStore,
            followPubkeys: followPubkeys,
            interval: cleanupInterval
        )
    }

    private static func recomputeAndApply(
        router: OutboxRouter,
        pool: RelayPool,
        configStore: RelayConfigStore,
        followPubkeys: [String]
    ) {
        let userReadRelays = configStore.relays.filter(\.read).map(\.url)
        let assignments = router.relaysForAuthors(followPubkeys, userReadRelays: userReadRelays)
        router.applyOutboxRelays(
            assignments: assignments,
            pool: pool,
            existingConfigs: configStore.relays
        )
    }

    /// Periodic cleanup tick. Lives inside the bootstrap task so the existing
    /// `tearDownRelaySession` cancellation kills the loop on sign-out without
    /// any additional plumbing. Re-applies outbox assignments before sweeping
    /// stale relays so new follows seen on the NIP-65 stream pick up
    /// connections on the same cadence.
    private static func runCleanupLoop(
        router: OutboxRouter,
        pool: RelayPool,
        configStore: RelayConfigStore,
        followPubkeys: [String],
        interval: Duration
    ) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            if Task.isCancelled { return }
            recomputeAndApply(
                router: router,
                pool: pool,
                configStore: configStore,
                followPubkeys: followPubkeys
            )
            router.cleanupStaleOutboxRelays(pool: pool)
        }
    }
}
