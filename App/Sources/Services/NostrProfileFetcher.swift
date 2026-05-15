import Foundation
@preconcurrency import NDKSwiftCore
import os.log

/// One-shot kind:0 (`metadata`) fetcher backed by the shared `NDK` instance.
/// Subscribes for profile events for the given pubkeys, parses each event's
/// JSON content reactively as it arrives, and writes the freshest record per
/// pubkey into `AppStateStore.state.nostrProfileCache`.
///
/// Reactive: drains the subscription's `AsyncStream` until EOSE or the
/// caller-supplied timeout fires. No polling — relay pushes events; we
/// pull from the stream.
@MainActor
final class NostrProfileFetcher {

    nonisolated private static let logger = Logger.app("NostrProfileFetcher")

    private enum Wire {
        static let kindMetadata = 0
        static let timeout: Duration = .seconds(4)
    }

    private let store: AppStateStore

    init(store: AppStateStore) {
        self.store = store
    }

    /// Requests kind:0 events for `pubkeys` and caches whatever arrives
    /// before EOSE or timeout. Returns when the subscription terminates.
    func fetchProfiles(for pubkeys: [String]) async {
        guard !pubkeys.isEmpty else { return }
        guard let ndk = NostrStack.shared.ndk else {
            Self.logger.debug("fetchProfiles: no NDK available; skipping")
            return
        }

        let filter = NDKFilter(
            authors: pubkeys,
            kinds: [Wire.kindMetadata]
        )
        // One-shot fetch: close on EOSE so the AsyncStream terminates and
        // the consuming task returns. Timeout race below is a safety net
        // for relays that never send EOSE.
        let subscription = ndk.subscribe(filter: filter, closeOnEose: true)

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                guard let self else { return }
                for await batch in subscription.events {
                    for event in batch {
                        if let profile = self.parseProfile(from: event) {
                            await self.store.setNostrProfile(profile)
                        }
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: Wire.timeout)
            }
            await group.next()
            group.cancelAll()
        }
    }

    private nonisolated func parseProfile(from event: NDKEvent) -> NostrProfileMetadata? {
        let pubkey = event.pubkey
        let createdAt = Int(event.createdAt)
        let content = event.content

        guard let contentData = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any] else {
            return NostrProfileMetadata(
                pubkey: pubkey,
                name: nil, displayName: nil, about: nil, picture: nil, nip05: nil,
                fetchedFromCreatedAt: createdAt
            )
        }

        return NostrProfileMetadata(
            pubkey: pubkey,
            name: json["name"] as? String,
            displayName: (json["display_name"] as? String) ?? (json["displayName"] as? String),
            about: json["about"] as? String,
            picture: json["picture"] as? String,
            nip05: json["nip05"] as? String,
            fetchedFromCreatedAt: createdAt
        )
    }
}
