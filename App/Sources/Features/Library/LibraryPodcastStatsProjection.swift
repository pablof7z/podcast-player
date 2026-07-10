import Foundation

// MARK: - LibraryPodcastStatsProjection
//
// Thin decoder for Rust-owned podcast library facts. Swift passes the visible
// podcast ids and renders labels; Rust owns the episode counts.

struct LibraryPodcastStatsProjection {
    let episodeCounts: [UUID: Int]
    let unplayedCounts: [UUID: Int]
    let downloadedPodcastIDs: Set<UUID>
    let transcribedPodcastIDs: Set<UUID>
    let latestEpisodeIDs: [UUID: UUID]

    static let empty = LibraryPodcastStatsProjection(
        episodeCounts: [:], unplayedCounts: [:], downloadedPodcastIDs: [],
        transcribedPodcastIDs: [], latestEpisodeIDs: [:]
    )

    // `@MainActor`: reads main-actor `store.kernel`; callers are SwiftUI views
    // and one-shot agent/sort operations, not a re-run-every-render UI read.
    @MainActor
    static func load(podcastIDs: [UUID], store: AppStateStore) -> LibraryPodcastStatsProjection {
        guard !podcastIDs.isEmpty,
              let envelope = store.kernel?.libraryPodcastStatsEnvelope(podcastIDs: podcastIDs),
              let data = envelope.data(using: .utf8),
              let decoded = try? JSONDecoder.libraryPodcastStats.decode(Response.self, from: data)
        else {
            return .empty
        }
        return Self.projection(from: decoded)
    }

    /// `nmp_app_podcast_library_podcast_stats` (the Rust side of
    /// `libraryPodcastStatsEnvelope`) scans `store.all_podcasts()` and does a
    /// linear `.find()` per requested id. Runs off MainActor on
    /// `kernel.snapshotDecodeQueue` — see `AppStateStore.offMainFFI`'s doc
    /// comment for why caching alone (a `.task(id:)` gate) isn't enough: the
    /// call that DOES fire can still block MainActor for hundreds of ms on a
    /// real library, caught via a main-thread `sample` (#755 follow-up). Used
    /// by Home-screen views that read this from a `.task(id:)`, not a
    /// synchronous computed property; other call sites (agent adapters, sort
    /// comparators — one-shot operations, not re-run per render) keep using
    /// the synchronous `load` above.
    @MainActor
    static func loadOffMain(podcastIDs: [UUID], store: AppStateStore) async -> LibraryPodcastStatsProjection {
        guard !podcastIDs.isEmpty else { return .empty }
        let envelope = await store.offMainFFI { handle in
            handle.libraryPodcastStatsEnvelope(podcastIDs: podcastIDs)
        }
        guard let envelope = envelope ?? nil,
              let data = envelope.data(using: .utf8),
              let decoded = try? JSONDecoder.libraryPodcastStats.decode(Response.self, from: data)
        else {
            return .empty
        }
        return Self.projection(from: decoded)
    }

    private static func projection(from decoded: Response) -> LibraryPodcastStatsProjection {
        LibraryPodcastStatsProjection(
            episodeCounts: Dictionary(
                uniqueKeysWithValues: decoded.podcasts.map { ($0.podcastId, $0.episodeCount) }
            ),
            unplayedCounts: Dictionary(
                uniqueKeysWithValues: decoded.podcasts.map { ($0.podcastId, $0.unplayedCount) }
            ),
            downloadedPodcastIDs: Set(
                decoded.podcasts.compactMap { $0.hasDownloadedEpisode ? $0.podcastId : nil }
            ),
            transcribedPodcastIDs: Set(
                decoded.podcasts.compactMap { $0.hasTranscribedEpisode ? $0.podcastId : nil }
            ),
            latestEpisodeIDs: Dictionary(
                uniqueKeysWithValues: decoded.podcasts.compactMap { row in
                    row.latestEpisodeId.map { (row.podcastId, $0) }
                }
            )
        )
    }

    func episodeCount(for podcastID: UUID) -> Int {
        episodeCounts[podcastID] ?? 0
    }

    func unplayedCount(for podcastID: UUID) -> Int {
        unplayedCounts[podcastID] ?? 0
    }

    func hasDownloadedEpisode(for podcastID: UUID) -> Bool {
        downloadedPodcastIDs.contains(podcastID)
    }

    func hasTranscribedEpisode(for podcastID: UUID) -> Bool {
        transcribedPodcastIDs.contains(podcastID)
    }

    @MainActor
    func latestEpisode(for podcastID: UUID, store: AppStateStore) -> Episode? {
        guard let episodeID = latestEpisodeIDs[podcastID] else { return nil }
        return store.episode(id: episodeID)
    }

    private struct Response: Decodable {
        let podcasts: [Row]
    }

    private struct Row: Decodable {
        let podcastId: UUID
        let episodeCount: Int
        let unplayedCount: Int
        let hasDownloadedEpisode: Bool
        let hasTranscribedEpisode: Bool
        let latestEpisodeId: UUID?
    }
}

private extension JSONDecoder {
    static let libraryPodcastStats: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
