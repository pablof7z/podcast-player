import Foundation
import os.log

// MARK: - NostrPodcastDiscoveryService
//
// Queries the Rust core for NIP-74 podcast events:
//   kind:30074 — podcast show (parameterised replaceable, d-tag = show id)
//   kind:30075 — podcast episode (parameterised replaceable, d-tag = ep id)
//
// Each fetch opens a Rust-side subscription via the shared
// `PodcastrCoreBridge`, drains incoming deltas on the MainActor through an
// `AsyncStream`, then unsubscribes — closely matching the previous direct-
// WebSocket lifecycle but with the relay pool managed by Rust.
//
// rust-cutover: the `relayURL` parameter on every public method is now
// ignored — the Rust pool owns relay selection.

@MainActor
final class NostrPodcastDiscoveryService {

    nonisolated private static let logger = Logger.app("NostrPodcastDiscoveryService")

    private enum Wire {
        static let kindShow: UInt32 = 30074
        static let kindEpisode: UInt32 = 30075
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

    /// Returns all kind:30074 shows the Rust pool knows about, newest first.
    /// `relayURL` is ignored. // rust-cutover: relayURL ignored; Rust pool broadcasts to all writers
    func fetchShows(relayURL _: URL) async -> [ShowResult] {
        let bridge = PodcastrCoreBridge.shared
        let (stream, continuation) = AsyncStream<Delta>.makeStream()
        let handle = bridge.register { delta in continuation.yield(delta) }

        let subId: String
        do {
            subId = try await bridge.core.subscribePodcastShows(
                callbackSubscriptionId: handle.callbackID
            )
        } catch {
            Self.logger.warning("fetchShows: subscribe failed — \(error.localizedDescription, privacy: .public)")
            continuation.finish()
            bridge.unregister(handle)
            return []
        }

        let timeoutTask = Task {
            try? await Task.sleep(for: Wire.timeout)
            continuation.finish()
        }

        var collected: [ShowResult] = []
        for await delta in stream {
            switch delta.change {
            case .podcastShowDiscovered(let show):
                collected.append(Self.map(show: show))
            case .subscriptionEose:
                continuation.finish()
            default:
                break
            }
        }
        timeoutTask.cancel()

        await bridge.core.unsubscribePodcast(subId: subId)
        bridge.unregister(handle)

        // Rust may emit the same coordinate twice across the initial REQ
        // results from multiple relays. Dedup on coordinate, newest first,
        // mirroring the original Swift behaviour callers rely on.
        var seen = Set<String>()
        return collected
            .sorted { $0.createdAt > $1.createdAt }
            .filter { seen.insert($0.coordinate).inserted }
    }

    // MARK: - Fetch episodes (kind:30075)

    /// Returns `Episode` objects for `show`, already mapped with `podcastID`.
    /// `relayURL` is ignored. // rust-cutover: relayURL ignored; Rust pool broadcasts to all writers
    func fetchEpisodes(for show: ShowResult, relayURL _: URL, podcastID: UUID) async -> [Episode] {
        let bridge = PodcastrCoreBridge.shared
        let (stream, continuation) = AsyncStream<Delta>.makeStream()
        let handle = bridge.register { delta in continuation.yield(delta) }

        let subId: String
        do {
            subId = try await bridge.core.subscribePodcastEpisodes(
                showCoordinate: show.coordinate,
                callbackSubscriptionId: handle.callbackID
            )
        } catch {
            Self.logger.warning("fetchEpisodes: subscribe failed — \(error.localizedDescription, privacy: .public)")
            continuation.finish()
            bridge.unregister(handle)
            return []
        }

        let timeoutTask = Task {
            try? await Task.sleep(for: Wire.timeout)
            continuation.finish()
        }

        var collected: [PodcastEpisodeRecord] = []
        for await delta in stream {
            switch delta.change {
            case .podcastEpisodeDiscovered(let episode):
                collected.append(episode)
            case .subscriptionEose:
                continuation.finish()
            default:
                break
            }
        }
        timeoutTask.cancel()

        await bridge.core.unsubscribePodcast(subId: subId)
        bridge.unregister(handle)

        // Replaceable-event dedupe: keep newest `createdAt` per d-tag.
        var newestByDTag: [String: PodcastEpisodeRecord] = [:]
        for rec in collected {
            if let existing = newestByDTag[rec.dTag], existing.createdAt >= rec.createdAt {
                continue
            }
            newestByDTag[rec.dTag] = rec
        }
        return newestByDTag.values
            .sorted { $0.createdAt > $1.createdAt }
            .map { Self.map(episode: $0, podcastID: podcastID) }
    }

    // MARK: - Deterministic UUID

    /// Derives a stable `UUID` from a NIP-74 coordinate.
    /// Routes through Rust so the algorithm has a single source of truth.
    static func podcastID(for coordinate: String) -> UUID {
        let uuidString = podcastIdForCoordinate(coordinate: coordinate)
        return UUID(uuidString: uuidString) ?? UUID()
    }

    // MARK: - Subscribe ("Add to library")

    /// Creates or updates the `Podcast` row, upserts episodes, and adds a
    /// `PodcastSubscription`. Returns the stored podcast.
    /// `relayURL` is ignored. // rust-cutover: relayURL ignored; Rust pool broadcasts to all writers
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

    // MARK: - Record → Swift type mapping

    private static func map(show rec: PodcastShowRecord) -> ShowResult {
        ShowResult(
            coordinate: rec.coordinate,
            pubkey: rec.pubkey,
            dTag: rec.dTag,
            title: rec.title,
            author: rec.author,
            imageURL: rec.imageUrl.flatMap { URL(string: $0) },
            description: rec.description,
            categories: rec.categories,
            createdAt: Int(rec.createdAt)
        )
    }

    private static func map(episode rec: PodcastEpisodeRecord, podcastID: UUID) -> Episode {
        // FIXME(rust-cutover): PodcastEpisodeRecord has no `publishedAt` field
        // — falling back to createdAt. For episodes whose publisher re-published
        // an older release, the pubDate will reflect the re-publish time rather
        // than the original air date.
        let pubDate = Date(timeIntervalSince1970: TimeInterval(rec.createdAt))
        let duration: TimeInterval? = rec.duration.map { TimeInterval($0) }
        let audioURL = URL(string: rec.audioUrl) ?? URL(string: "about:blank")!
        let transcriptURL = rec.transcriptUrl.flatMap { URL(string: $0) }
        let chaptersURL = rec.chaptersUrl.flatMap { URL(string: $0) }
        // FIXME(rust-cutover): PodcastEpisodeRecord exposes no per-episode
        // imageUrl; UI falls back to podcast artwork per `Episode.imageURL` docs.
        // FIXME(rust-cutover): PodcastEpisodeRecord exposes no transcript
        // mime type; transcript kind cannot be classified at the FFI boundary.
        return Episode(
            podcastID: podcastID,
            guid: rec.dTag,
            title: rec.title.isEmpty ? "Untitled Episode" : rec.title,
            description: rec.description,
            pubDate: pubDate,
            duration: duration,
            enclosureURL: audioURL,
            enclosureMimeType: rec.mimeType,
            imageURL: nil,
            publisherTranscriptURL: transcriptURL,
            publisherTranscriptType: nil,
            chaptersURL: chaptersURL
        )
    }
}
