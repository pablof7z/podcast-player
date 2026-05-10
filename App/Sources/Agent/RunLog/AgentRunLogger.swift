import Foundation
import Observation

@MainActor
final class AgentRunLogger: ObservableObject {
    static let shared = AgentRunLogger()

    @Published private(set) var runs: [AgentRun] = []

    private let directoryURL: URL
    private let fileURL: URL

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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(runs) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    private static func load(from url: URL) -> [AgentRun] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([AgentRun].self, from: data)) ?? []
    }
}
