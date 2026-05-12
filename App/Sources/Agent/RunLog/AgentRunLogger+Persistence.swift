import Foundation

extension AgentRunLogger {

    /// Snapshot the current `runs` array on MainActor and hand the
    /// encode + write off to the background serial queue. UI updates
    /// stay synchronous (the `@Published` array mutation already
    /// happened in `log(run:)` / `clear()`); the disk write is a
    /// fire-and-forget side effect that never blocks an agent turn.
    func scheduleSave() {
        let snapshot = runs
        let url = fileURL
        ioQueue.async {
            guard let data = try? Self.encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: [.atomic])
        }
    }

    static func load(from url: URL) -> [AgentRun] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([AgentRun].self, from: data)) ?? []
    }
}
