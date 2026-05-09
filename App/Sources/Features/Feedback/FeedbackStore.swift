import os
import SwiftUI

// MARK: - FeedbackStore

@MainActor
@Observable
final class FeedbackStore {

    private let logger = Logger.app("FeedbackStore")
    var threads: [FeedbackThread] = []
    var isLoading: Bool = false

    private static var persistenceURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("feedback_threads.json")
    }

    func load() async {
        isLoading = true
        do {
            threads = try loadFromDisk()
        } catch CocoaError.fileNoSuchFile {
            threads = []
        } catch {
            logger.error("Failed to load threads from disk: \(error, privacy: .public)")
            threads = []
        }
        isLoading = false
    }

    @discardableResult
    func publishThread(category: FeedbackCategory, content: String, image: UIImage?) async throws -> FeedbackThread {
        try await Task.sleep(for: AppTheme.Timing.feedbackPublishDelay)
        let thread = FeedbackThread(category: category, content: content, attachedImage: image)
        threads.insert(thread, at: 0)
        do { try saveToDisk() } catch { logger.error("Failed to save after publishThread: \(error, privacy: .public)") }
        return thread
    }

    func publishReply(content: String, threadID: UUID) async throws {
        try await Task.sleep(for: AppTheme.Timing.feedbackReplyDelay)
        guard let idx = threads.firstIndex(where: { $0.id == threadID }) else { return }
        threads[idx].replies.append(FeedbackReply(content: content, isFromMe: true))
        do { try saveToDisk() } catch { logger.error("Failed to save after publishReply: \(error, privacy: .public)") }
    }

    func deleteThread(id: UUID) {
        threads.removeAll { $0.id == id }
        do { try saveToDisk() } catch { logger.error("Failed to save after deleteThread: \(error, privacy: .public)") }
    }

    // MARK: - Private persistence helpers

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func saveToDisk() throws {
        let data = try Self.encoder.encode(threads)
        try data.write(to: Self.persistenceURL, options: .atomic)
    }

    private func loadFromDisk() throws -> [FeedbackThread] {
        let data = try Data(contentsOf: Self.persistenceURL)
        return try Self.decoder.decode([FeedbackThread].self, from: data)
    }
}
