import Foundation
import Observation

@MainActor
final class AgentRunLogger: ObservableObject {
    static let shared = AgentRunLogger()

    @Published private(set) var runs: [AgentRun] = []

    private let directoryURL: URL
    private let fileURL: URL

    /// Configured once and reused — every `log(run:)` triggered a save
    /// that allocated a fresh encoder, configured it (`.iso8601` +
    /// `.sortedKeys`), then discarded it. Per-run agent transcripts can
    /// grow to several KB once turns + tool calls + system prompts add
    /// up, so the per-call configuration was a real (if small) tax.
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directoryURL = base.appendingPathComponent("AgentRunLog", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("runs.json")
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        runs = Self.load(from: fileURL)
    }

    func log(run: AgentRun) {
        runs.insert(run, at: 0)
        save()
    }

    func clear() {
        runs = []
        save()
    }

    private func save() {
        guard let data = try? Self.encoder.encode(runs) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    private static func load(from url: URL) -> [AgentRun] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([AgentRun].self, from: data)) ?? []
    }
}
