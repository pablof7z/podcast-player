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
    /// leave existing connections alone (don't drop & re-open).
    func reconcile(with configs: [RelayConfig]) {
        let desiredURLs = Set(configs.filter(\.hasAnyRole).map(\.url))
        let currentURLs = Set(connections.keys)

        for url in desiredURLs.subtracting(currentURLs) {
            let conn = RelayConnection(url: url, signer: signer)
            connections[url] = conn
            Task { await conn.connect() }
        }

        for url in currentURLs.subtracting(desiredURLs) {
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

    // MARK: - Diagnostics

    var onlineCount: Int { connections.values.filter { $0.status.isConnected }.count }
    var totalCount: Int { connections.count }
}
