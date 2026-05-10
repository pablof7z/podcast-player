import Foundation
import os.log

// MARK: - ClipStore
//
// File-backed persistence for `Clip` records. Mirrors `TranscriptStore`'s
// pattern — one file per clip under
// `$applicationSupport/podcastr/clips/<clipID>.json`. Kept out of the
// monolithic `AppState` blob so the periodic state save stays cheap and so
// the sister "clips" agent can swap the implementation without touching the
// call sites in `AppStateStore+Clips`.
//
// Thread-safety: the disk surface is conservative — synchronous on the
// caller's actor. The class is `@unchecked Sendable` because the only
// mutable state is `rootURL`, set once at init.

final class ClipStore: @unchecked Sendable {

    static let shared: ClipStore = {
        do {
            return try ClipStore()
        } catch {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("podcastr-clips", isDirectory: true)
            // swiftlint:disable:next force_try
            return try! ClipStore(rootDirectory: tmp)
        }
    }()

    private static let logger = Logger.app("ClipStore")

    let rootURL: URL

    init(rootDirectory: URL? = nil) throws {
        if let rootDirectory {
            self.rootURL = rootDirectory
        } else {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.rootURL = support
                .appendingPathComponent("podcastr", isDirectory: true)
                .appendingPathComponent("clips", isDirectory: true)
        }
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
    }

    /// Write `clip` to disk, replacing any existing record with the same id.
    func save(_ clip: Clip) throws {
        let url = fileURL(for: clip.id)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(clip)
        try data.write(to: url, options: .atomic)
        Self.logger.debug(
            "wrote clip \(clip.id, privacy: .public) (\(data.count, privacy: .public) bytes)"
        )
    }

    /// Load a single clip, or `nil` when no file exists.
    func load(clipID: UUID) -> Clip? {
        let url = fileURL(for: clipID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Clip.self, from: data)
        } catch {
            Self.logger.error(
                "failed to load clip \(clipID, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    /// Enumerate every persisted clip. Intended for the future Clips library
    /// view — the auto-snip path itself is write-only.
    func loadAll() -> [Clip] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var result: [Clip] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let clip = try? decoder.decode(Clip.self, from: data) else { continue }
            result.append(clip)
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    /// Idempotent.
    func delete(clipID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: clipID))
    }

    private func fileURL(for clipID: UUID) -> URL {
        rootURL.appendingPathComponent("\(clipID.uuidString).json")
    }
}
