import Foundation
@preconcurrency import NDKSwiftCore
import os.log

/// One-shot NIP-10 conversation fetcher backed by the shared `NDK` instance.
/// Pulls the root event (by id) plus every kind:1 that e-tags it, so the
/// peer-agent responder can assemble message history before invoking the LLM.
///
/// Reactive model mirrors `NostrProfileFetcher`: two parallel `ndk.subscribe`
/// calls — one for the root, one for replies — drained concurrently into a
/// shared accumulator. Each closes on EOSE; an outer timeout races as a
/// safety net for relays that never send EOSE. No polling.
@MainActor
final class NostrThreadFetcher {

    nonisolated private static let logger = Logger.app("NostrThreadFetcher")

    private enum Wire {
        static let kindTextNote = 1
        static let timeout: Duration = .seconds(4)
    }

    /// Wire-shape of an inbound kind:1 the responder needs to assemble a
    /// conversation. Keeps the responder decoupled from `NDKEvent` so the
    /// transport can swap without rippling into call sites.
    struct Event: Sendable, Equatable {
        let id: String
        let pubkey: String
        let createdAt: Int
        let content: String
        let tags: [[String]]
    }

    /// Per-instance accumulator. Each `fetch` builds a fresh fetcher so
    /// concurrent fetches don't share state.
    private var collected: [String: Event] = [:]

    /// Fetch the root (by id) and all kind:1 replies that e-tag it via the
    /// shared `NDK`. The `relayURL` parameter is preserved for API
    /// compatibility but is no longer consulted — NDK uses its connected
    /// relay pool. Results are de-duplicated by event id and sorted ascending
    /// by `created_at`. Returns an empty array on any hard failure.
    static func fetch(rootID: String, relayURL: URL) async -> [Event] {
        await NostrThreadFetcher().run(rootID: rootID, relayURL: relayURL)
    }

    private init() {}

    private func run(rootID: String, relayURL: URL) async -> [Event] {
        guard let ndk = NostrStack.shared.ndk else {
            Self.logger.debug("fetch: no NDK available; returning empty")
            return []
        }
        guard NostrStack.shared.relaysConnected else {
            Self.logger.debug("fetch: relays not connected; returning empty")
            return []
        }

        // Two parallel subscriptions:
        //   1) the root event itself, by id
        //   2) replies that e-tag the root, restricted to kind:1
        // Both close on EOSE so their AsyncStreams terminate naturally; the
        // outer timeout races as a backstop for missing-EOSE relays.
        let rootSub = ndk.subscribe(
            filter: NDKFilter(ids: [rootID]),
            closeOnEose: true
        )
        let repliesSub = ndk.subscribe(
            filter: NDKFilter(kinds: [Wire.kindTextNote], events: [rootID]),
            closeOnEose: true
        )

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                guard let self else { return }
                for await batch in rootSub.events {
                    for event in batch {
                        await self.absorb(event)
                    }
                }
            }
            group.addTask { [weak self] in
                guard let self else { return }
                for await batch in repliesSub.events {
                    for event in batch {
                        await self.absorb(event)
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: Wire.timeout)
            }
            await group.next()
            group.cancelAll()
        }

        return collected.values.sorted { $0.createdAt < $1.createdAt }
    }

    /// Funnels an inbound `NDKEvent` into the shared accumulator. Same id
    /// arriving from both subscriptions is harmlessly idempotent (replace).
    private func absorb(_ event: NDKEvent) {
        collected[event.id] = Event(
            id: event.id,
            pubkey: event.pubkey,
            createdAt: Int(event.createdAt),
            content: event.content,
            tags: event.tags
        )
    }
}
