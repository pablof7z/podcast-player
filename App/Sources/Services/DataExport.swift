import Foundation

// MARK: - DataExport
//
// Pure, side-effect-free helpers for exporting the user's `AppState` as a
// portable JSON document. The view layer composes these into a `ShareLink`.
//
// Inspired by win-the-day-app's `FullBackupManager` (payload + version envelope)
// and cut-tracker's `CSVExporter` (filename + suggested file shape).
//
// SECURITY: This export must never include secrets. We deliberately route
// through `AppState` only (which holds non-secret connection metadata) and
// strip the legacy OpenRouter API key field before serialization. Keychain
// values (OpenRouter, ElevenLabs, Nostr private key) are NOT exported.

enum DataExport {

    /// Versioned envelope around `AppState`. Bumping `schemaVersion` lets
    /// future imports detect and migrate older exports.
    struct Payload: Codable, Sendable {
        var schemaVersion: Int
        var generatedAt: Date
        var appVersion: String?
        var buildNumber: String?
        var sourceBundleIdentifier: String?
        var state: AppState
    }

    static let currentSchemaVersion = 1

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    // ISO8601DateFormatter is thread-safe for reads after setup — nonisolated(unsafe) suppresses
    // the Swift 6 Sendable warning without changing runtime behaviour.
    private nonisolated(unsafe) static let iso8601 = ISO8601DateFormatter()

    private static let filenameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Build

    /// Returns a redacted copy of `state` safe for export.
    /// - Removes the legacy OpenRouter API key (the only secret-shaped field
    ///   that ever touched persistence; current credentials live in Keychain).
    static func redactedState(from state: AppState) -> AppState {
        var copy = state
        copy.settings.legacyOpenRouterAPIKey = nil
        return copy
    }

    /// Builds the export payload from the live in-memory state.
    static func makePayload(from state: AppState, now: Date = Date()) -> Payload {
        let info = Bundle.main.infoDictionary
        return Payload(
            schemaVersion: currentSchemaVersion,
            generatedAt: now,
            appVersion: info?["CFBundleShortVersionString"] as? String,
            buildNumber: info?["CFBundleVersion"] as? String,
            sourceBundleIdentifier: Bundle.main.bundleIdentifier,
            state: redactedState(from: state)
        )
    }

    /// Encodes the payload to pretty-printed UTF-8 JSON.
    static func encode(_ payload: Payload) throws -> Data {
        try encoder.encode(payload)
    }

    /// Suggested filename, e.g. `Podcastr-Export-2026-05-05-1430.json`.
    static func suggestedFilename(at date: Date = Date()) -> String {
        "Podcastr-Export-\(filenameDateFormatter.string(from: date)).json"
    }

    // MARK: - Write

    /// Writes the encoded payload to a fresh file in the temporary directory
    /// and returns its URL, suitable for `ShareLink(item:)`.
    static func writeTemporaryFile(_ data: Data, filename: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic])
        return url
    }

    /// Convenience: build payload, encode, and write a temp file in one shot.
    static func writeExport(of state: AppState, now: Date = Date()) throws -> URL {
        let payload = makePayload(from: state, now: now)
        let data = try encode(payload)
        let filename = suggestedFilename(at: now)
        return try writeTemporaryFile(data, filename: filename)
    }

    // MARK: - Format

    /// Supported export file formats.
    enum Format: String, CaseIterable, Sendable {
        case json = "JSON"
        case csv  = "CSV"

        var fileExtension: String {
            switch self {
            case .json: return "json"
            case .csv:  return "csv"
            }
        }
    }

    // MARK: - CSV encoding (items only)

    /// Produces a UTF-8 CSV string with one row per non-deleted item.
    /// Columns: id, title, status, source, isPriority, isPinned, recurrence, createdAt, updatedAt, reminderAt, dueAt, tags, colorTag, estimatedMinutes
    static func encodeItemsCSV(from state: AppState) -> Data {
        let header = "id,title,status,source,isPriority,isPinned,recurrence,createdAt,updatedAt,reminderAt,dueAt,tags,colorTag,estimatedMinutes"
        var rows: [String] = [header]
        for item in state.items where !item.deleted {
            let cols: [String] = [
                item.id.uuidString,
                csvEscaped(item.title),
                item.status.rawValue,
                item.source.rawValue,
                item.isPriority ? "true" : "false",
                item.isPinned ? "true" : "false",
                item.recurrence.rawValue,
                Self.iso8601.string(from: item.createdAt),
                Self.iso8601.string(from: item.updatedAt),
                item.reminderAt.map { Self.iso8601.string(from: $0) } ?? "",
                item.dueAt.map { Self.iso8601.string(from: $0) } ?? "",
                csvEscaped(item.tags.joined(separator: "|")),
                item.colorTag.rawValue,
                item.estimatedMinutes.map { String($0) } ?? "",
            ]
            rows.append(cols.joined(separator: ","))
        }
        // Force-unwrap is safe: UTF-8 encoding never fails on a Swift String.
        return rows.joined(separator: "\n").data(using: .utf8)!
    }

    private static func csvEscaped(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    /// Suggested CSV filename, e.g. `Podcastr-Items-2026-05-05-1430.csv`.
    static func suggestedCSVFilename(at date: Date = Date()) -> String {
        "Podcastr-Items-\(filenameDateFormatter.string(from: date)).csv"
    }

    /// Writes a CSV of items to a temp file and returns its URL.
    static func writeCSVExport(of state: AppState, now: Date = Date()) throws -> URL {
        let data = encodeItemsCSV(from: state)
        let filename = suggestedCSVFilename(at: now)
        return try writeTemporaryFile(data, filename: filename)
    }

    // MARK: - Stats (UI helpers)

    /// Counts of non-deleted records in `state`, used for the export preview.
    struct Stats: Sendable, Hashable {
        var items: Int
        var notes: Int
        var friends: Int
        var memories: Int
        var agentActivity: Int

        var totalRecords: Int { items + notes + friends + memories + agentActivity }
    }

    static func stats(for state: AppState) -> Stats {
        Stats(
            items: state.items.filter { !$0.deleted }.count,
            notes: state.notes.filter { !$0.deleted }.count,
            friends: state.friends.count,
            memories: state.agentMemories.filter { !$0.deleted }.count,
            agentActivity: state.agentActivity.count
        )
    }
}
