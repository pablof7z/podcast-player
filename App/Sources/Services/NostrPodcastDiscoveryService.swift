import CryptoKit
import Foundation
@preconcurrency import NDKSwiftCore
import os.log

// MARK: - NostrPodcastDiscoveryService
//
// Queries the shared `NDK` instance for NIP-74 podcast events:
//   kind:30074 — podcast show (parameterised replaceable, d-tag = show identifier)
//   kind:30075 — podcast episode (parameterised replaceable, d-tag = episode identifier)
//
// Each query opens a single subscription that closes on EOSE; results stream
// in via `subscription.events` (AsyncStream). An outer timeout races to bail
// out if the relay never sends EOSE. No polling.

@MainActor
final class NostrPodcastDiscoveryService {

    nonisolated private static let logger = Logger.app("NostrPodcastDiscoveryService")

    private enum Wire {
        static let kindShow = 30074
        static let kindEpisode = 30075
        static let timeout: Duration = .seconds(8)
    }

    // MARK: - Public result types

    struct ShowResult: Identifiable, Sendable {
        /// Unique key: "<pubkey>:<dTag>"
        var id: String { "\(pubkey):\(dTag)" }
        let coordinate: String   // "30074:<pubkey>:<dTag>"
        let pubkey: String
        let dTag: String
        let title: String
        let author: String
        let imageURL: URL?
        let description: String
        let categories: [String]
        let createdAt: Int
    }

    // MARK: - Fetch shows (kind:30074)

    /// Returns all kind:30074 shows the connected relay knows about, newest first.
    /// `relayURL` is preserved for API compatibility but is no longer consulted
    /// — NDK uses its connected relay pool.
    func fetchShows(relayURL: URL) async -> [ShowResult] {
        let events = await collectEvents(
            filter: NDKFilter(kinds: [Wire.kindShow]),
            label: "shows"
        )

        var seen = Set<String>()
        return events
            .compactMap { Self.parseShow(from: $0) }
            .sorted { $0.createdAt > $1.createdAt }
            .filter { seen.insert($0.coordinate).inserted }
    }

    // MARK: - Fetch episodes (kind:30075)

    /// Returns `Episode` objects for `show`, already mapped with `podcastID`.
    func fetchEpisodes(for show: ShowResult, relayURL: URL, podcastID: UUID) async -> [Episode] {
        let showRef = "\(Wire.kindShow):\(show.pubkey):\(show.dTag)"
        let filter = NDKFilter(
            authors: [show.pubkey],
            kinds: [Wire.kindEpisode],
            tags: ["a": Set([showRef])]
        )
        let events = await collectEvents(filter: filter, label: "episodes")

        // Dedupe by d-tag (replaceable events): keep the newest per d-tag.
        var seen = [String: Int64]()
        var deduped: [NDKEvent] = []
        for event in events.sorted(by: { $0.createdAt > $1.createdAt }) {
            guard let dTag = event.tag(withName: "d")?[safe: 1], !dTag.isEmpty,
                  seen[dTag] == nil else { continue }
            seen[dTag] = event.createdAt
            deduped.append(event)
        }
        return deduped.compactMap { Self.parseEpisode(from: $0, podcastID: podcastID) }
    }

    // MARK: - Deterministic UUID

    /// Derives a stable `UUID` from a NIP-74 coordinate using SHA-256.
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

    /// Opens an `ndk.subscribe(closeOnEose: true)` for `filter`, drains the
    /// resulting `AsyncStream` until it terminates (EOSE) or the hard timeout
    /// fires. Returns the collected events. `label` is used only for logging.
    private func collectEvents(filter: NDKFilter, label: String) async -> [NDKEvent] {
        guard let ndk = NostrStack.shared.ndk else {
            Self.logger.debug("collect \(label, privacy: .public): no NDK available")
            return []
        }
        guard NostrStack.shared.relaysConnected else {
            Self.logger.debug("collect \(label, privacy: .public): relays not connected")
            return []
        }

        let subscription = ndk.subscribe(filter: filter, closeOnEose: true)
        var collected: [NDKEvent] = []

        await withTaskGroup(of: [NDKEvent].self) { group in
            group.addTask {
                var local: [NDKEvent] = []
                for await batch in subscription.events {
                    local.append(contentsOf: batch)
                }
                return local
            }
            group.addTask {
                try? await Task.sleep(for: Wire.timeout)
                return []
            }
            if let first = await group.next() {
                collected = first
            }
            group.cancelAll()
        }
        return collected
    }

    // MARK: - Event parsers

    private static func parseShow(from event: NDKEvent) -> ShowResult? {
        let pubkey = event.pubkey
        let createdAt = Int(event.createdAt)

        guard let dTag = event.tag(withName: "d")?[safe: 1], !dTag.isEmpty else { return nil }

        let title = event.tag(withName: "title")?[safe: 1]
            ?? (event.content.isEmpty ? nil : String(event.content.prefix(80)))
            ?? ""
        guard !title.isEmpty else { return nil }

        let author = event.tag(withName: "author")?[safe: 1] ?? ""
        let description = event.tag(withName: "summary")?[safe: 1] ?? event.content
        let imageURL = event.tag(withName: "image")?[safe: 1].flatMap { URL(string: $0) }
        let categories = event.tags(withName: "t").compactMap { $0[safe: 1] }
        let coordinate = "\(Wire.kindShow):\(pubkey):\(dTag)"

        return ShowResult(
            coordinate: coordinate,
            pubkey: pubkey,
            dTag: dTag,
            title: title,
            author: author,
            imageURL: imageURL,
            description: description,
            categories: categories,
            createdAt: createdAt
        )
    }

    private static func parseEpisode(from event: NDKEvent, podcastID: UUID) -> Episode? {
        guard let dTag = event.tag(withName: "d")?[safe: 1], !dTag.isEmpty else { return nil }

        // Audio URL from `imeta url` or fallback `url` tag — required.
        let imetaTag = event.tag(withName: "imeta")
        let audioURLStr = imetaTag?
            .dropFirst()
            .compactMap { $0.hasPrefix("url ") ? String($0.dropFirst(4)) : nil }
            .first
            ?? event.tag(withName: "url")?[safe: 1]
        guard let audioStr = audioURLStr, let audioURL = URL(string: audioStr) else { return nil }

        let title = event.tag(withName: "title")?[safe: 1] ?? ""
        let description = event.tag(withName: "summary")?[safe: 1] ?? event.content
        let imageURL = event.tag(withName: "image")?[safe: 1].flatMap { URL(string: $0) }

        let pubDateSeconds = event.tag(withName: "published_at")?[safe: 1]
            .flatMap { Int($0) } ?? Int(event.createdAt)
        let pubDate = Date(timeIntervalSince1970: TimeInterval(pubDateSeconds))

        let duration = event.tag(withName: "duration")?[safe: 1].flatMap { TimeInterval($0) }
        let chaptersURL = event.tag(withName: "chapters")?[safe: 1].flatMap { URL(string: $0) }

        let transcriptTag = event.tag(withName: "transcript")
        let transcriptURL = transcriptTag?[safe: 1].flatMap { URL(string: $0) }
        let transcriptKind = TranscriptKind.from(mimeType: transcriptTag?[safe: 2])

        let mimeType = imetaTag?
            .dropFirst()
            .compactMap { $0.hasPrefix("m ") ? String($0.dropFirst(2)) : nil }
            .first

        return Episode(
            podcastID: podcastID,
            guid: dTag,
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
