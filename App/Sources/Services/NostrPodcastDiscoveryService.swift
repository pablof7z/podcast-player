import CryptoKit
import Foundation
@preconcurrency import NDKSwiftCore
import os.log

// MARK: - NostrPodcastDiscoveryService
//
// Queries the shared `NDK` instance for NIP-F4 podcast events:
//   kind:10154 — podcast show (replaceable; one per podcast keypair)
//   kind:54    — podcast episode (regular events authored by podcast pubkey)
//
// In NIP-F4 each podcast IS its own keypair: the pubkey alone identifies the
// show. Episodes are discovered by author, not by an `a`-tag reference.
//
// Each query uses one app-owned NDK subscription scoped to the selected relay.
// Results stream in via `subscription.events`; the collector waits for EOSE or
// an outer timeout, then closes the subscription after draining queued batches.

private actor NostrDiscoveryEventAccumulator {
    private var events: [NDKEvent] = []

    func append(_ batch: [NDKEvent]) {
        events.append(contentsOf: batch)
    }

    func snapshot() -> [NDKEvent] {
        events
    }
}

@MainActor
final class NostrPodcastDiscoveryService {

    nonisolated private static let logger = Logger.app("NostrPodcastDiscoveryService")

    private enum Wire {
        static let kindShow = 10154
        static let kindEpisode = 54
        static let showLimit = 100
        static let timeout: Duration = .seconds(8)
    }

    // MARK: - Public result types

    struct ShowResult: Identifiable, Sendable {
        /// Unique key: the podcast's pubkey hex.
        var id: String { pubkey }
        let coordinate: String   // "10154:<pubkey>"
        let pubkey: String
        let title: String
        let author: String
        let imageURL: URL?
        let description: String
        let categories: [String]
        let createdAt: Int
    }

    // MARK: - Fetch shows (kind:10154)

    /// Returns all kind:10154 shows the connected relay knows about, newest first.
    func fetchShows(relayURL: URL) async -> [ShowResult] {
        let events = await collectEvents(
            filter: NDKFilter(kinds: [Wire.kindShow], limit: Wire.showLimit),
            relayURL: relayURL,
            label: "shows"
        )

        var seen = Set<String>()
        return events
            .compactMap { Self.parseShow(from: $0) }
            .sorted { $0.createdAt > $1.createdAt }
            .filter { seen.insert($0.pubkey).inserted }
    }

    // MARK: - Fetch episodes (kind:54)

    /// Returns `Episode` objects for `show`, fetched by the show's author pubkey.
    func fetchEpisodes(for show: ShowResult, relayURL: URL, podcastID: UUID) async -> [Episode] {
        let filter = NDKFilter(
            authors: [show.pubkey],
            kinds: [Wire.kindEpisode]
        )
        let events = await collectEvents(filter: filter, relayURL: relayURL, label: "episodes")

        // Dedupe by event ID (regular events; each is unique).
        var seen = Set<String>()
        return events
            .sorted { $0.createdAt > $1.createdAt }
            .filter { seen.insert($0.id).inserted }
            .compactMap { Self.parseEpisode(from: $0, podcastID: podcastID) }
    }

    // MARK: - Deterministic UUID

    /// Derives a stable `UUID` from a NIP-F4 coordinate using SHA-256.
    /// Identical coordinates always produce the same UUID, enabling dedup
    /// by `store.podcast(id:)` without a feedURL.
    static func podcastID(for coordinate: String) -> UUID {
        let hash = SHA256.hash(data: Data(coordinate.utf8))
        var bytes = Array(hash.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50  // UUID version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // UUID variant 1
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    // MARK: - Subscribe

    /// Creates or updates the `Podcast` row, upserts episodes, and adds a
    /// `PodcastSubscription`. Returns the stored podcast.
    func subscribe(to show: ShowResult, store: AppStateStore, relayURL: URL) async -> Podcast {
        let pid = Self.podcastID(for: show.coordinate)
        let draft = Podcast(
            id: pid,
            kind: .rss,
            feedURL: nil,
            title: show.title,
            author: show.author,
            imageURL: show.imageURL,
            description: show.description,
            categories: show.categories,
            nostrCoordinate: show.coordinate
        )
        let stored = store.upsertPodcast(draft)
        let episodes = await fetchEpisodes(for: show, relayURL: relayURL, podcastID: stored.id)
        store.upsertEpisodes(episodes, forPodcast: stored.id, evaluateAutoDownload: false)
        store.addSubscription(podcastID: stored.id)
        return stored
    }

    // MARK: - Subscription collector

    private func collectEvents(filter: NDKFilter, relayURL: URL, label: String) async -> [NDKEvent] {
        let relay = URLNormalizer.tryNormalizeRelayUrl(relayURL.absoluteString) ?? relayURL.absoluteString
        guard let ndk = NostrStack.shared.ndk else {
            Self.logger.debug("collect \(label, privacy: .public): no NDK available")
            return []
        }
        if !NostrStack.shared.relaysConnected {
            Self.logger.debug("collect \(label, privacy: .public): relay pool is not marked connected; trying explicit relay")
        }
        guard await ensureRelayConnected(relay, ndk: ndk, label: label) else { return [] }

        Self.logger.notice("collect \(label, privacy: .public): subscribing on \(relay, privacy: .public)")
        let options = NDKSubscriptionOptions(
            cachePolicy: .networkOnly,
            relays: Set([relay]),
            exclusiveRelays: true,
            subscriptionId: "nip-f4-\(label)",
            closeOnEose: false,
            groupable: false
        )
        let subscription = ndk.subscribe(filter: filter, options: options, includeRelayUpdates: true)
        let accumulator = NostrDiscoveryEventAccumulator()

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await batch in subscription.events {
                    await accumulator.append(batch)
                }
            }
            group.addTask {
                guard let relayUpdates = subscription.relayUpdates else { return }
                for await update in relayUpdates {
                    switch update {
                    case let .eose(updateRelay) where updateRelay == relay:
                        try? await Task.sleep(for: .milliseconds(150))
                        return
                    case .aggregatedEose:
                        try? await Task.sleep(for: .milliseconds(150))
                        return
                    case let .closed(updateRelay) where updateRelay == relay:
                        return
                    default:
                        continue
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: Wire.timeout)
            }
            await group.next()
            group.cancelAll()
        }
        await subscription.close()
        let collected = await accumulator.snapshot()
        Self.logger.notice(
            "collect \(label, privacy: .public): received \(collected.count, privacy: .public) event(s) from \(relay, privacy: .public)"
        )
        return collected
    }

    private func ensureRelayConnected(_ relayURL: String, ndk: NDK, label: String) async -> Bool {
        let relay = await ndk.addRelay(relayURL, origin: .discovery, reason: "NIP-F4 \(label) fetch")
        do {
            try await relay.connect()
        } catch {
            Self.logger.error(
                "collect \(label, privacy: .public): failed to connect \(relayURL, privacy: .public): \(error, privacy: .public)"
            )
            return false
        }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await state in relay.stateStream {
                    switch state.connectionState {
                    case .connected, .authenticated: return true
                    case .failed: return false
                    default: continue
                    }
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                Self.logger.error("collect \(label, privacy: .public): \(relayURL, privacy: .public) timed out")
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    // MARK: - Event parsers

    private static func parseShow(from event: NDKEvent) -> ShowResult? {
        let pubkey = event.pubkey
        let createdAt = Int(event.createdAt)

        let title = event.tag(withName: "title")?[safe: 1]
            ?? (event.content.isEmpty ? nil : String(event.content.prefix(80)))
            ?? ""
        guard !title.isEmpty else { return nil }

        let description = event.tag(withName: "description")?[safe: 1] ?? event.content
        let imageURL = event.tag(withName: "image")?[safe: 1].flatMap { URL(string: $0) }
        let categories = event.tags(withName: "t").compactMap { $0[safe: 1] }

        // Author is the "host" p-tag, if any.
        let author = event.tags(withName: "p")
            .first(where: { $0[safe: 2] == "host" || $0[safe: 2] == nil })?[safe: 1] ?? ""

        let coordinate = "\(Wire.kindShow):\(pubkey)"

        return ShowResult(
            coordinate: coordinate,
            pubkey: pubkey,
            title: title,
            author: author,
            imageURL: imageURL,
            description: description,
            categories: categories,
            createdAt: createdAt
        )
    }

    private static func parseEpisode(from event: NDKEvent, podcastID: UUID) -> Episode? {
        // Audio URL from `audio` tag — required.
        guard let audioTag = event.tag(withName: "audio"),
              let audioStr = audioTag[safe: 1],
              let audioURL = URL(string: audioStr) else { return nil }

        let mimeType = audioTag[safe: 2]
        let title = event.tag(withName: "title")?[safe: 1] ?? ""
        let description = event.tag(withName: "description")?[safe: 1]
            ?? (event.content.isEmpty ? "" : event.content)
        let imageURL = event.tag(withName: "image")?[safe: 1].flatMap { URL(string: $0) }
        let pubDate = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
        let duration = event.tag(withName: "duration")?[safe: 1].flatMap { TimeInterval($0) }
        let chaptersURL = event.tag(withName: "chapters")?[safe: 1].flatMap { URL(string: $0) }

        let transcriptTag = event.tag(withName: "transcript")
        let transcriptURL = transcriptTag?[safe: 1].flatMap { URL(string: $0) }
        let transcriptKind = TranscriptKind.from(mimeType: transcriptTag?[safe: 2])

        return Episode(
            podcastID: podcastID,
            guid: event.id,
            title: title.isEmpty ? "Untitled Episode" : title,
            description: description,
            pubDate: pubDate,
            duration: duration,
            enclosureURL: audioURL,
            enclosureMimeType: mimeType,
            imageURL: imageURL,
            publisherTranscriptURL: transcriptURL,
            publisherTranscriptType: transcriptKind,
            chaptersURL: chaptersURL
        )
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
