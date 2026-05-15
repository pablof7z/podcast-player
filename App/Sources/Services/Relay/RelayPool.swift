import Foundation
import Observation
import os.log

/// Manages multiple `RelayConnection` instances with diff-and-apply
/// reconciliation. Reconcile is called from `RelayConfigStore` on every
/// config mutation and from `RelayBootstrapService` on live NIP-65 updates.
@MainActor
@Observable
final class RelayPool {
    nonisolated static let logger = Logger.app("RelayPool")

    private(set) var connections: [String: RelayConnection] = [:]
    private let signer: any NostrSigner

    /// URLs currently wanted by `RelayConfigStore` (user-configured relays).
    /// Tracked separately from `transientURLs` so transient outbox connections
    /// survive a config-driven reconcile that no longer mentions them.
    private var configURLs: Set<String> = []

    /// URLs the outbox router has asked us to keep open. These are read-only
    /// fetch endpoints discovered from follows' kind:10002 and have no
    /// matching `RelayConfig` row.
    private var transientURLs: Set<String> = []

    init(signer: any NostrSigner) {
        self.signer = signer
    }

    struct PublishOutcome: Sendable {
        let url: String
        let success: Bool
        let message: String?
    }

    // MARK: - Reconciliation

    /// Diff-and-apply: connect new relays, disconnect removed relays,
    /// leave existing connections alone (don't drop & re-open). Transient
    /// outbox connections (see `connectTransient`) are preserved across
    /// reconciles even when no config row mentions them.
    func reconcile(with configs: [RelayConfig]) {
        configURLs = Set(configs.filter(\.hasAnyRole).map(\.url))
        syncConnections()
    }

    // MARK: - Transient outbox connections

    /// Ask the pool to keep read-only connections open to the given URLs
    /// without writing them into the user's `RelayConfig` set. Used by the
    /// outbox router for follows' write relays we've never user-configured.
    func connectTransient(urls: [String]) {
        let normalized = urls.map(RelayConfig.normalizeURL)
        transientURLs.formUnion(normalized)
        syncConnections()
    }

    /// Release the given transient URLs. URLs still claimed by configs (a
    /// transient relay the user later added by hand) stay connected.
    func disconnectTransient(urls: [String]) {
        let normalized = urls.map(RelayConfig.normalizeURL)
        transientURLs.subtract(normalized)
        syncConnections()
    }

    /// Reconcile `connections` against the union of `configURLs` and
    /// `transientURLs`. Centralised so every entry point (reconcile,
    /// connectTransient, disconnectTransient) goes through the same diff.
    private func syncConnections() {
        let desired = configURLs.union(transientURLs)
        let current = Set(connections.keys)

        for url in desired.subtracting(current) {
            let conn = RelayConnection(url: url, signer: signer)
            connections[url] = conn
            Task { await conn.connect() }
        }

        for url in current.subtracting(desired) {
            connections[url]?.disconnect()
            connections.removeValue(forKey: url)
        }
    }

    // MARK: - Publishing

    /// Publish to all given write URLs concurrently. Returns one outcome per URL.
    /// Both the relay's OK `accepted` boolean and the trailing message are surfaced —
    /// relays sometimes ack `accepted=true` with a message like `duplicate:` or
    /// `rate-limited:`; callers should not collapse the two.
    func publishToWriteRelays(_ event: SignedNostrEvent, writeURLs: [String]) async -> [PublishOutcome] {
        let normalized = writeURLs.map(RelayConfig.normalizeURL)
        return await withTaskGroup(of: PublishOutcome.self) { group in
            for url in normalized {
                group.addTask { [weak self] in
                    guard let self else {
                        return PublishOutcome(url: url, success: false, message: "Pool released")
                    }
                    return await self.sendOne(event: event, url: url)
                }
            }
            var outcomes: [PublishOutcome] = []
            outcomes.reserveCapacity(normalized.count)
            for await outcome in group { outcomes.append(outcome) }
            return outcomes
        }
    }

    private func sendOne(event: SignedNostrEvent, url: String) async -> PublishOutcome {
        guard let conn = connections[url] else {
            return PublishOutcome(url: url, success: false, message: "No connection")
        }
        let result = await conn.send(event: event)
        return PublishOutcome(url: url, success: result.success, message: result.message)
    }

    /// Publish to a single specific relay (for NIP-29 scoped sends).
    func publishToRelay(_ event: SignedNostrEvent, url: String) async -> (success: Bool, message: String?) {
        let normalized = RelayConfig.normalizeURL(url)
        guard let conn = connections[normalized] else {
            return (false, "No connection")
        }
        let result = await conn.send(event: event)
        return (result.success, result.message)
    }

    // MARK: - Subscriptions

    /// Subscribe on a specific set of relay URLs. Each per-relay subscription
    /// gets the id `"\(id)|\(url)"` so `unsubscribe(id:)` can close them all.
    func subscribe(
        on urls: [String],
        id: String,
        filter: [[String: Any]],
        handler: @escaping (SignedNostrEvent) -> Void
    ) {
        let normalized = urls.map(RelayConfig.normalizeURL)
        for url in normalized {
            guard let conn = connections[url] else { continue }
            conn.subscribe(id: "\(id)|\(url)", filter: filter, handler: handler)
        }
    }

    /// Subscribe on every relay marked `read` in the given configs.
    func subscribeOnReadRelays(
        id: String,
        filter: [[String: Any]],
        configs: [RelayConfig],
        handler: @escaping (SignedNostrEvent) -> Void
    ) {
        let readURLs = configs.filter(\.read).map(\.url)
        subscribe(on: readURLs, id: id, filter: filter, handler: handler)
    }

    /// Close a subscription on every connection that holds it.
    func unsubscribe(id: String) {
        for (url, conn) in connections {
            conn.unsubscribe(id: "\(id)|\(url)")
        }
    }

    /// Tear down every connection and drop them from the pool. Used by the
    /// identity teardown path so signing out / switching accounts doesn't
    /// leave the previous user's WebSockets running.
    func disconnectAll() {
        for conn in connections.values { conn.disconnect() }
        connections.removeAll()
        configURLs.removeAll()
        transientURLs.removeAll()
    }

    // MARK: - Diagnostics

    var onlineCount: Int { connections.values.filter { $0.status.isConnected }.count }
    var totalCount: Int { connections.count }
}
