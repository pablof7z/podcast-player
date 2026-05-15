import Foundation
import os.log

/// Bootstrap sequence for the relay subsystem. Called once per signer
/// activation (both local-key and NIP-46 paths).
///
/// 1. Local configs are already loaded by `RelayConfigStore.init`.
/// 2. Pool reconciles to local configs so the user can read/write
///    against their last-known relay set immediately.
/// 3. One-shot fetch of fresh kind:10002 + kind:30078 from the indexer
///    relays (fallback: purplepag.es + relay.primal.net).
/// 4. Merge fetched with local → update store → pool re-reconciles.
/// 5. Long-lived subscription on read relays so subsequent updates to
///    the user's own kind:10002 / kind:30078 trigger another merge.
enum RelayBootstrapService {
    private static let logger = Logger.app("RelayBootstrapService")
    private static let fallbackIndexers: [String] = [
        "wss://purplepag.es",
        "wss://relay.primal.net",
    ].map(RelayConfig.normalizeURL)
    private static let liveSubID = "relay-config-self"
    private static let fetchTimeout: Duration = .seconds(4)

    struct FetchedRelayEvents: Sendable {
        var nip65: SignedNostrEvent?
        var nip78: SignedNostrEvent?
    }

    @MainActor
    static func bootstrap(
        configStore: RelayConfigStore,
        pool: RelayPool,
        signer _: any NostrSigner,
        userPubkey: String
    ) async {
        configStore.attachRelayPool(pool)

        let indexerURLs = configStore.relays.filter(\.indexer).map(\.url)
        let targets = indexerURLs.isEmpty ? fallbackIndexers : indexerURLs

        let fetched = await fetchSelfRelayEvents(targets: targets, userPubkey: userPubkey)

        if fetched.nip65 != nil || fetched.nip78 != nil {
            mergeAndApply(fetched: fetched, configStore: configStore)
        }

        subscribeForLiveUpdates(pool: pool, configStore: configStore, userPubkey: userPubkey)
    }

    // MARK: - Merge

    @MainActor
    private static func mergeAndApply(fetched: FetchedRelayEvents, configStore: RelayConfigStore) {
        let nip65Entries: [RelayConfigMerger.NIP65Entry] = fetched.nip65
            .map { RelayConfigMerger.parseNIP65(tags: $0.tags) } ?? []
        let nip78Entries: [RelayConfigMerger.NIP78Entry] = fetched.nip78
            .map { RelayConfigMerger.parseNIP78(content: $0.content) } ?? []
        let merged = RelayConfigMerger.merge(nip65: nip65Entries, nip78: nip78Entries)
        // Re-use importRelays to preserve user-local rooms/indexer flags via OR-merge
        // for read/write, while letting NIP-78 fields drive rooms/indexer.
        configStore.importRelays(merged)
    }

    // MARK: - Live updates

    @MainActor
    private static func subscribeForLiveUpdates(
        pool: RelayPool,
        configStore: RelayConfigStore,
        userPubkey: String
    ) {
        let filter: [[String: Any]] = [[
            "kinds": [10002, 30078],
            "authors": [userPubkey],
        ]]
        pool.subscribeOnReadRelays(
            id: liveSubID,
            filter: filter,
            configs: configStore.relays
        ) { event in
            handleLiveEvent(event, configStore: configStore)
        }
    }

    @MainActor
    private static func handleLiveEvent(_ event: SignedNostrEvent, configStore: RelayConfigStore) {
        switch event.kind {
        case 10002:
            let entries = RelayConfigMerger.parseNIP65(tags: event.tags)
            let merged = RelayConfigMerger.merge(nip65: entries, nip78: [])
            configStore.importRelays(merged)
        case 30078:
            // NIP-78 kind is shared across apps; only act on our `d` tag.
            let isOurs = event.tags.contains { tag in
                tag.count >= 2 && tag[0] == "d" && tag[1] == NIP78RelayStore.dTag
            }
            guard isOurs else { return }
            let entries = RelayConfigMerger.parseNIP78(content: event.content)
            let merged = RelayConfigMerger.merge(nip65: [], nip78: entries)
            configStore.importRelays(merged)
        default: break
        }
    }

    // MARK: - One-shot fetch

    /// Open transient WebSockets to each target indexer in parallel, send a
    /// single combined REQ for the user's own kind:10002 and kind:30078, and
    /// return the newest event of each kind seen before EOSE or timeout.
    private static func fetchSelfRelayEvents(targets: [String], userPubkey: String) async -> FetchedRelayEvents {
        await withTaskGroup(of: FetchedRelayEvents.self) { group in
            for urlString in targets {
                guard let url = URL(string: urlString) else { continue }
                group.addTask {
                    await fetchFromSingleRelay(url: url, userPubkey: userPubkey)
                }
            }
            var combined = FetchedRelayEvents()
            for await partial in group {
                combined.nip65 = newer(combined.nip65, partial.nip65)
                combined.nip78 = newer(combined.nip78, partial.nip78)
            }
            return combined
        }
    }

    private static func newer(_ a: SignedNostrEvent?, _ b: SignedNostrEvent?) -> SignedNostrEvent? {
        switch (a, b) {
        case (nil, nil): return nil
        case (let x?, nil): return x
        case (nil, let y?): return y
        case (let x?, let y?): return x.created_at >= y.created_at ? x : y
        }
    }

    private static func fetchFromSingleRelay(url: URL, userPubkey: String) async -> FetchedRelayEvents {
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        let subID = "boot-\(UUID().uuidString.prefix(8))"
        let req: [Any] = [
            "REQ", subID,
            ["kinds": [10002], "authors": [userPubkey]] as [String: Any],
            ["kinds": [30078], "authors": [userPubkey], "#d": [NIP78RelayStore.dTag]] as [String: Any],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: req),
              let text = String(data: data, encoding: .utf8) else { return FetchedRelayEvents() }
        do { try await task.send(.string(text)) }
        catch {
            logger.notice("bootstrap fetch send failed (\(url.absoluteString, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            return FetchedRelayEvents()
        }

        return await withTaskGroup(of: FetchedRelayEvents.self) { group in
            group.addTask { await readUntilEose(task: task, subID: subID) }
            group.addTask {
                try? await Task.sleep(for: fetchTimeout)
                return FetchedRelayEvents()
            }
            let first = await group.next() ?? FetchedRelayEvents()
            group.cancelAll()
            return first
        }
    }

    private static func readUntilEose(task: URLSessionWebSocketTask, subID: String) async -> FetchedRelayEvents {
        var fetched = FetchedRelayEvents()
        while !Task.isCancelled {
            let msg: URLSessionWebSocketTask.Message
            do { msg = try await task.receive() } catch { return fetched }
            guard case .string(let text) = msg,
                  let data = text.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  let kind = array.first as? String else { continue }
            switch kind {
            case "EVENT":
                guard array.count >= 3,
                      let id = array[1] as? String,
                      id == subID,
                      let dict = array[2] as? [String: Any],
                      let event = parseEvent(dict) else { continue }
                if event.kind == 10002 { fetched.nip65 = newer(fetched.nip65, event) }
                if event.kind == 30078 { fetched.nip78 = newer(fetched.nip78, event) }
            case "EOSE":
                return fetched
            default: continue
            }
        }
        return fetched
    }

    private static func parseEvent(_ dict: [String: Any]) -> SignedNostrEvent? {
        guard let id = dict["id"] as? String,
              let pubkey = dict["pubkey"] as? String,
              let createdAt = dict["created_at"] as? Int,
              let kind = dict["kind"] as? Int,
              let content = dict["content"] as? String,
              let sig = dict["sig"] as? String,
              let tags = dict["tags"] as? [[String]] else { return nil }
        return SignedNostrEvent(
            id: id, pubkey: pubkey, created_at: createdAt,
            kind: kind, tags: tags, content: content, sig: sig
        )
    }
}
