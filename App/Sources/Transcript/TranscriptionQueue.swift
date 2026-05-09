import Foundation
import os.log

// MARK: - TranscriptionQueue

/// Coordinates transcription work across episodes. Owns priority, dedup, and
/// dispatch (publisher-ingestor vs Scribe) so the rest of the app submits a
/// single high-level intent: "transcribe this episode."
///
/// Why an actor: callers from `@MainActor` (UI) and from background tasks
/// (downloads finishing) both push work in. We need serialised access to the
/// pending set without risking re-entrant races.
actor TranscriptionQueue {

    // MARK: Types

    /// Public work request. Lane 2 owns the real `Episode`; the queue only
    /// needs the four fields below, so we accept a small struct to stay
    /// decoupled from that lane's evolving shape.
    struct Job: Sendable, Hashable {
        let episodeID: UUID
        let priority: Priority
        let publisherTranscriptURL: URL?
        let publisherTranscriptMime: String?
        let audioURL: URL?
        let languageHint: String?
    }

    enum Priority: Int, Sendable, Comparable {
        case nowPlaying = 3
        case recentlySubscribed = 2
        case bulk = 1
        static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum State: Sendable, Equatable {
        case pending
        case running
        case completed
        case failed(message: String)
    }

    // MARK: Dependencies

    private let ingestor: PublisherTranscriptIngestor
    private let scribe: ElevenLabsScribeClient
    private let onResult: @Sendable (Transcript) async -> Void
    private static let logger = Logger.app("TranscriptionQueue")

    // MARK: State

    /// Pending jobs ordered by priority then enqueue time.
    private var pending: [Job] = []
    /// Lookup: episodeID → current state. Used for dedup + UI status.
    private var states: [UUID: State] = [:]
    private var workerRunning = false

    init(
        ingestor: PublisherTranscriptIngestor = PublisherTranscriptIngestor(),
        scribe: ElevenLabsScribeClient = ElevenLabsScribeClient(),
        onResult: @escaping @Sendable (Transcript) async -> Void = { _ in }
    ) {
        self.ingestor = ingestor
        self.scribe = scribe
        self.onResult = onResult
    }

    // MARK: API

    /// Adds a job to the queue. If the same episode is already pending the
    /// new request only wins if its priority is higher. If the episode is
    /// already running or completed, the new request is dropped.
    func enqueue(_ job: Job) {
        if let existing = states[job.episodeID] {
            switch existing {
            case .running, .completed:
                Self.logger.debug("Skipping enqueue: episode \(job.episodeID) already \(String(describing: existing), privacy: .public)")
                return
            case .pending, .failed:
                break
            }
        }
        pending.removeAll { $0.episodeID == job.episodeID }
        pending.append(job)
        pending.sort { $0.priority > $1.priority }
        states[job.episodeID] = .pending
        startWorkerIfNeeded()
    }

    /// Returns the current state of an episode's transcription, or `nil` if
    /// it has not been seen by the queue.
    func state(for episodeID: UUID) -> State? { states[episodeID] }

    /// Returns the count of jobs currently pending.
    func pendingCount() -> Int { pending.count }

    // MARK: Worker

    private func startWorkerIfNeeded() {
        guard !workerRunning else { return }
        workerRunning = true
        Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while let job = popNext() {
            states[job.episodeID] = .running
            do {
                let transcript = try await execute(job)
                states[job.episodeID] = .completed
                await onResult(transcript)
            } catch {
                let message = String(describing: error)
                Self.logger.error("Job failed for episode \(job.episodeID, privacy: .public): \(message, privacy: .public)")
                states[job.episodeID] = .failed(message: message)
            }
        }
        workerRunning = false
    }

    private func popNext() -> Job? {
        guard !pending.isEmpty else { return nil }
        return pending.removeFirst()
    }

    /// Dispatches one job: prefer publisher transcript, fall back to Scribe.
    private func execute(_ job: Job) async throws -> Transcript {
        if let url = job.publisherTranscriptURL {
            do {
                return try await ingestor.ingest(
                    url: url,
                    mimeHint: job.publisherTranscriptMime,
                    episodeID: job.episodeID,
                    language: job.languageHint ?? "en-US"
                )
            } catch {
                Self.logger.notice(
                    "Publisher transcript failed (\(String(describing: error), privacy: .public)) — falling back to Scribe"
                )
            }
        }
        guard let audio = job.audioURL else {
            throw QueueError.missingAudioForScribe(job.episodeID)
        }
        let scribeJob = try await scribe.submit(
            audioURL: audio,
            episodeID: job.episodeID,
            languageHint: job.languageHint
        )
        return try await scribe.pollResult(scribeJob)
    }

    enum QueueError: Swift.Error, Sendable {
        case missingAudioForScribe(UUID)
    }
}
