import Foundation
import os.log

/// Long-lived subscription that streams kind:10002 updates for every author
/// the user follows. Lives on the **indexer** relays (purplepag.es / primal)
/// rather than the user's own read set, since indexers are what aggregate
/// foreign authors' relay-list metadata. Each event refreshes the matching
/// entry in `OutboxRouter.authorWriteRelays` so subsequent set-cover passes
/// see current data.
@MainActor
enum FollowRelaySubscription {
    private static let logger = Logger.app("FollowRelaySubscription")
    static let subscriptionID = "outbox-follows-nip65"

    /// Open the long-lived REQ. Idempotent — calling again with the same
    /// pool replaces the previous subscription via the `id` collision.
    /// No-ops when `followPubkeys` is empty so we don't spray indexers with
    /// `authors: []` filters.
    static func subscribe(
        pool: RelayPool,
        indexerURLs: [String],
        followPubkeys: [String],
        router: OutboxRouter
    ) {
        guard !followPubkeys.isEmpty, !indexerURLs.isEmpty else {
            logger.debug("Skipping follow NIP-65 sub: \(followPubkeys.count) follows on \(indexerURLs.count) indexers")
            return
        }
        let filter: [[String: Any]] = [[
            "kinds": [10002],
            "authors": followPubkeys,
        ]]
        pool.subscribe(on: indexerURLs, id: subscriptionID, filter: filter) { event in
            handleEvent(event, router: router)
        }
    }

    private static func handleEvent(_ event: SignedNostrEvent, router: OutboxRouter) {
        guard event.kind == 10002 else { return }
        let entries = RelayConfigMerger.parseNIP65(tags: event.tags)
        let writeRelays = entries
            .filter(\.write)
            .map(\.url)
            .map(RelayConfig.normalizeURL)
        router.updateAuthorRelays(pubkey: event.pubkey, writeRelays: writeRelays)
    }
}
