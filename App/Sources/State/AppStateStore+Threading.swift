import Foundation

// MARK: - Rust-owned threading projection

struct ThreadingProjection: Equatable, Sendable {
    var topics: [ThreadingTopic]
    var mentions: [ThreadingMention]

    static let empty = ThreadingProjection(topics: [], mentions: [])
}

struct ActiveThreadingTopic: Equatable, Identifiable, Sendable {
    let topic: ThreadingTopic
    let unplayedEpisodeCount: Int
    let mentionIDs: [UUID]
    var id: UUID { topic.id }
}

extension AppStateStore {

    var threadingTopics: [ThreadingTopic] {
        threadingProjection.topics
    }

    /// Off-MainActor refresh. The underlying Rust projection is O(episodes):
    /// on a freshly-synced real library (thousands of episodes) the FIRST
    /// post-launch call recomputes every episode's heuristic category from
    /// scratch (the categorization cache starts empty each launch — see
    /// #755/#756) and measured over 1s on a real ~2k-episode library. Calling
    /// this synchronously from HomeView's `.task` used to block MainActor for
    /// that entire second right after the list had already rendered, freezing
    /// scrolling/interaction. The envelope fetch + JSON decode now run on
    /// `kernel.snapshotDecodeQueue` — the same off-MainActor decode queue
    /// `KernelModel` already uses for the full-library snapshot pull (see
    /// `KernelModel+SnapshotPull.swift`) — captured while still on MainActor
    /// (`PodcastHandle` is the thread-safe FFI handle; `KernelModel` itself is
    /// not). Only the final assignment hops back to MainActor.
    func refreshThreadingProjection() async {
        guard let kernelModel = kernel else { return }
        let handle = kernelModel.kernel
        let decodeQueue = kernelModel.snapshotDecodeQueue
        let start = DispatchTime.now().uptimeNanoseconds
        let decoded: ThreadingProjection? = await withCheckedContinuation { continuation in
            decodeQueue.async {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                guard let envelope = handle.threadingProjectionEnvelope(),
                      let data = envelope.data(using: .utf8),
                      let decodedEnvelope = try? decoder.decode(ThreadingProjectionEnvelope.self, from: data)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: decodedEnvelope.projection)
            }
        }
        PerfMetrics.shared.record(
            .threadingProjectionPull,
            micros: Int((DispatchTime.now().uptimeNanoseconds &- start) / 1_000))
        guard let decoded else { return }
        threadingProjection = decoded
    }

    func threadingTopic(id: UUID) -> ThreadingTopic? {
        threadingProjection.topics.first { $0.id == id }
    }

    func threadingMentions(forTopic id: UUID) -> [ThreadingMention] {
        threadingProjection.mentions.filter { $0.topicID == id }
    }

    func threadingMentions(containingEpisode episodeID: UUID) -> [ThreadingMention] {
        threadingProjection.mentions.filter { $0.episodeID == episodeID }
    }

    /// Off-MainActor, same rationale as `refreshThreadingProjection`: this
    /// shares the Rust-side rev-gated cache with the projection pull, but a
    /// rev bump between the two calls (any concurrent library/download/
    /// playback update touches the same global rev counter) makes this ALSO
    /// hit the ~1s-on-a-real-library cold-rebuild path — observed on-device
    /// as a second main-thread stall right after the first one. Runs on the
    /// same `kernel.snapshotDecodeQueue` for the same off-MainActor reason.
    func activeThreadingTopics(
        limit: Int,
        subscriptionFilter: Set<UUID>? = nil
    ) async -> [ActiveThreadingTopic] {
        guard let kernelModel = kernel else { return [] }
        let handle = kernelModel.kernel
        let decodeQueue = kernelModel.snapshotDecodeQueue
        let podcastIDs = subscriptionFilter.map { Array($0) } ?? []
        let start = DispatchTime.now().uptimeNanoseconds
        let decoded: ActiveThreadingTopicsEnvelope? = await withCheckedContinuation { continuation in
            decodeQueue.async {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                guard let envelope = handle.threadingActiveTopicsEnvelope(limit: limit, podcastIDs: podcastIDs),
                      let data = envelope.data(using: .utf8),
                      let decodedEnvelope = try? decoder.decode(ActiveThreadingTopicsEnvelope.self, from: data)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: decodedEnvelope)
            }
        }
        PerfMetrics.shared.record(
            .threadingActiveTopicsPull,
            micros: Int((DispatchTime.now().uptimeNanoseconds &- start) / 1_000))
        guard let decoded else { return [] }
        return decoded.activeTopics.compactMap { row in
            guard let topicID = UUID(uuidString: row.topicId),
                  let topic = threadingTopic(id: topicID) else { return nil }
            let mentionIDs = row.mentionIds.compactMap(UUID.init(uuidString:))
            return ActiveThreadingTopic(
                topic: topic,
                unplayedEpisodeCount: row.unplayedEpisodeCount,
                mentionIDs: mentionIDs
            )
        }
    }
}

private struct ThreadingProjectionEnvelope: Decodable {
    var topics: [ThreadingTopicDTO] = []
    var mentions: [ThreadingMentionDTO] = []

    var projection: ThreadingProjection {
        ThreadingProjection(
            topics: topics.compactMap(\.topic),
            mentions: mentions.compactMap(\.mention)
        )
    }
}

private struct ActiveThreadingTopicsEnvelope: Decodable {
    var activeTopics: [ActiveThreadingTopicDTO] = []
}

private struct ActiveThreadingTopicDTO: Decodable {
    var topicId: String
    var unplayedEpisodeCount: Int
    var mentionIds: [String]
}

private struct ThreadingTopicDTO: Decodable {
    var id: String
    var slug: String
    var displayName: String
    var definition: String?
    var episodeMentionCount: Int
    var contradictionCount: Int
    var lastMentionedAt: Int?

    var topic: ThreadingTopic? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return ThreadingTopic(
            id: uuid,
            slug: slug,
            displayName: displayName,
            definition: definition,
            episodeMentionCount: episodeMentionCount,
            contradictionCount: contradictionCount,
            lastMentionedAt: lastMentionedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
}

private struct ThreadingMentionDTO: Decodable {
    var id: String
    var topicId: String
    var episodeId: String
    var startMs: Int
    var endMs: Int
    var snippet: String
    var confidence: Double
    var isContradictory: Bool

    var mention: ThreadingMention? {
        guard let id = UUID(uuidString: id),
              let topicID = UUID(uuidString: topicId),
              let episodeID = UUID(uuidString: episodeId) else { return nil }
        return ThreadingMention(
            id: id,
            topicID: topicID,
            episodeID: episodeID,
            startMS: startMs,
            endMS: endMs,
            snippet: snippet,
            confidence: confidence,
            isContradictory: isContradictory
        )
    }
}
