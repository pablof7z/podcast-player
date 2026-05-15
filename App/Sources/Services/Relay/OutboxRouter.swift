import Foundation
import Observation

/// Outbox-model fan-out planner (NIP-65).
///
/// Caches each followed author's write relays (their kind:10002), then runs
/// greedy set-cover to pick the smallest set of relays that covers the union
/// of authors we want to query. Authors with no known write relays fall back
/// to one of the user's own read relays so we still get a chance at their
/// events without spraying every read relay with the residual set.
///
/// Connection lifecycle: discovered relays that aren't in the user's
/// `RelayConfig` set are opened as **transient** read-only sockets on the
/// pool (`pool.connectTransient`). The router keeps a reference-counted entry
/// per transient URL; `cleanupStaleOutboxRelays` calls
/// `pool.disconnectTransient` for entries that fall to zero references or
/// haven't been touched within the grace window.
@MainActor
@Observable
final class OutboxRouter {
    /// Cached write relays per author pubkey, populated from kind:10002 events.
    private(set) var authorWriteRelays: [String: [String]] = [:]

    /// Transiently-connected outbox relays with reference counting.
    private(set) var activeOutboxRelays: [String: OutboxRelayEntry] = [:]

    struct OutboxRelayEntry {
        let url: String
        var referenceCount: Int
        var connectedSince: Date
        var lastReferenced: Date
    }

    // MARK: - Cache updates

    /// Replace the cached write relays for `pubkey`. Empty `writeRelays`
    /// removes the entry — an author advertising zero write relays would
    /// otherwise pin a stale set across NIP-65 churn.
    func updateAuthorRelays(pubkey: String, writeRelays: [String]) {
        let normalized = writeRelays
            .map(RelayConfig.normalizeURL)
            .filter { !$0.isEmpty }
        if normalized.isEmpty {
            authorWriteRelays.removeValue(forKey: pubkey)
        } else {
            authorWriteRelays[pubkey] = normalized
        }
    }

    /// Bulk-update from a batch of kind:10002 events. Each tuple is the
    /// event's `pubkey` + `tags`; tags are parsed via
    /// `RelayConfigMerger.parseNIP65` so we honour `read`/`write` markers.
    func updateAuthorsFromNIP65Events(_ events: [(pubkey: String, tags: [[String]])]) {
        for event in events {
            let entries = RelayConfigMerger.parseNIP65(tags: event.tags)
            let writeRelays = entries
                .filter(\.write)
                .map(\.url)
                .map(RelayConfig.normalizeURL)
            if !writeRelays.isEmpty {
                authorWriteRelays[event.pubkey] = writeRelays
            }
        }
    }

    // MARK: - Greedy set-cover

    /// Compute relay → pubkeys assignments.
    ///
    /// Algorithm: build a `[relay: Set<pubkey>]` inverse map, then greedily
    /// pick the relay covering the most uncovered pubkeys, subtract its
    /// coverage, and repeat. Authors with no cached write relays go to a
    /// single user read relay (the first one) — not all of them — to avoid
    /// duplicating the same REQ across the user's read set.
    func relaysForAuthors(_ pubkeys: [String], userReadRelays: [String]) -> [String: [String]] {
        let uniquePubkeys = Set(pubkeys)
        var relayToPubkeys: [String: Set<String>] = [:]
        var unknownAuthors: [String] = []

        for pubkey in uniquePubkeys {
            if let relays = authorWriteRelays[pubkey], !relays.isEmpty {
                for relay in relays {
                    relayToPubkeys[relay, default: []].insert(pubkey)
                }
            } else {
                unknownAuthors.append(pubkey)
            }
        }

        var uncovered = uniquePubkeys.subtracting(unknownAuthors)
        var result: [String: [String]] = [:]

        while !uncovered.isEmpty {
            var bestRelay: String?
            var bestCoverage: Set<String> = []
            for (relay, covers) in relayToPubkeys {
                let intersection = covers.intersection(uncovered)
                if intersection.count > bestCoverage.count {
                    bestCoverage = intersection
                    bestRelay = relay
                }
            }
            guard let relay = bestRelay, !bestCoverage.isEmpty else { break }
            result[relay] = Array(bestCoverage)
            uncovered.subtract(bestCoverage)
            relayToPubkeys.removeValue(forKey: relay)
        }

        // Fall back: pubkeys with no known write relays go to ONE user read
        // relay so we don't fan the same REQ across every read endpoint.
        if !unknownAuthors.isEmpty,
           let fallback = userReadRelays.first.map(RelayConfig.normalizeURL) {
            let existing = result[fallback] ?? []
            result[fallback] = Array(Set(existing).union(unknownAuthors))
        }

        return result
    }

    // MARK: - Transient relay lifecycle

    /// Open transient pool connections for assignments that aren't already
    /// covered by user-configured relays, and refresh reference counts on
    /// the entries we already have open.
    func applyOutboxRelays(
        assignments: [String: [String]],
        pool: RelayPool,
        existingConfigs: [RelayConfig]
    ) {
        let existingURLs = Set(existingConfigs.filter(\.hasAnyRole).map(\.url))
        let neededURLs = Set(assignments.keys)
        let transientNeeded = neededURLs.subtracting(existingURLs)

        let now = Date()
        var newEntries: [String: OutboxRelayEntry] = [:]
        for url in transientNeeded {
            let pubkeys = assignments[url] ?? []
            newEntries[url] = OutboxRelayEntry(
                url: url,
                referenceCount: pubkeys.count,
                connectedSince: activeOutboxRelays[url]?.connectedSince ?? now,
                lastReferenced: now
            )
        }

        let previousURLs = Set(activeOutboxRelays.keys)
        let toRelease = previousURLs.subtracting(transientNeeded)
        let toAdd = transientNeeded.subtracting(previousURLs)

        activeOutboxRelays = newEntries

        if !toAdd.isEmpty {
            pool.connectTransient(urls: Array(toAdd))
        }
        if !toRelease.isEmpty {
            pool.disconnectTransient(urls: Array(toRelease))
        }
    }

    /// Drop transient relays whose reference count is zero or that haven't
    /// been touched within `gracePeriod`. Must be called periodically — the
    /// pool's own reconcile only triggers on config changes and would leave
    /// these sockets open indefinitely otherwise.
    func cleanupStaleOutboxRelays(pool: RelayPool, gracePeriod: TimeInterval = 300) {
        let now = Date()
        let staleURLs = activeOutboxRelays.compactMap { url, entry -> String? in
            if entry.referenceCount == 0 { return url }
            if now.timeIntervalSince(entry.lastReferenced) > gracePeriod { return url }
            return nil
        }
        guard !staleURLs.isEmpty else { return }
        for url in staleURLs {
            activeOutboxRelays.removeValue(forKey: url)
        }
        pool.disconnectTransient(urls: staleURLs)
    }

    /// Tear-down hook used on sign-out / identity switch. Drops every
    /// transient connection and clears the author cache so the next user
    /// doesn't inherit the previous user's outbox state.
    func reset(pool: RelayPool) {
        let urls = Array(activeOutboxRelays.keys)
        activeOutboxRelays.removeAll()
        authorWriteRelays.removeAll()
        if !urls.isEmpty {
            pool.disconnectTransient(urls: urls)
        }
    }
}
