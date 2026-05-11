import Foundation

// MARK: - WhatsNewEntry
//
// One entry == one commit that shipped a user-facing change. The `id` is
// the short commit SHA, which is naturally unique and gives us a stable
// ordering key (alongside `shippedAt`).

struct WhatsNewEntry: Decodable, Sendable, Identifiable, Equatable {
    let id: String           // short commit SHA
    let shippedAt: Date
    let lines: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case shippedAt = "shipped_at"
        case lines
    }
}

// MARK: - Decoded payload shape

private struct WhatsNewPayload: Decodable {
    let schemaVersion: Int
    let entries: [WhatsNewEntry]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case entries
    }
}

// MARK: - WhatsNewService
//
// Loads the bundled `whats-new.json` and answers two questions:
//   1) Which entries has the user not yet seen since their last launch?
//   2) Persists the "I've seen up through entry X" marker so we don't
//      re-show old entries on every cold launch.
//
// The marker is stored under `whatsNew.lastSeenID` in `UserDefaults.standard`.
// That's the same key the SwiftUI sheet reads through `@AppStorage`, so the
// two stay in sync automatically.

@MainActor
enum WhatsNewService {

    // MARK: Constants

    /// `UserDefaults` key for the last-seen marker. Mirrored by
    /// `@AppStorage("whatsNew.lastSeenID")` inside `WhatsNewSheet`.
    static let lastSeenKey = "whatsNew.lastSeenID"

    /// Resource filename in the app bundle.
    private static let resourceName = "whats-new"
    private static let resourceExtension = "json"

    // MARK: Loading

    /// Loads `whats-new.json` from the app bundle. Empty when missing or
    /// malformed — the sheet just won't surface in that case (we'd rather
    /// fail closed than crash on launch).
    static func loadEntries(bundle: Bundle = .main) -> [WhatsNewEntry] {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try decode(data)
        } catch {
            return []
        }
    }

    /// Internal decode helper — exposed so tests can feed a JSON literal
    /// through it without depending on the bundled file (which evolves
    /// every release and would make tests flake).
    static func decode(_ data: Data) throws -> [WhatsNewEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(WhatsNewPayload.self, from: data)
        return payload.entries
    }

    // MARK: Marker

    /// The "I've seen up through this entry" marker, read directly from
    /// `UserDefaults.standard`. The sheet uses `@AppStorage` against the
    /// same key so writes stay in sync.
    static var lastSeenID: String? {
        UserDefaults.standard.string(forKey: lastSeenKey)
    }

    /// Persists the marker. Pass the newest visible entry's id when the
    /// user dismisses the sheet.
    static func markSeen(upTo id: String) {
        UserDefaults.standard.set(id, forKey: lastSeenKey)
    }

    /// Seeds the marker to the newest entry on fresh installs so the user
    /// is "caught up" silently. From the next deploy onward, any newly
    /// appended entry will surface through `unseenEntries(lastSeenID:)`.
    /// No-op once a marker exists.
    static func seedMarkerIfNeeded(entries: [WhatsNewEntry]? = nil) {
        guard lastSeenID == nil else { return }
        let all = (entries ?? loadEntries()).sorted { $0.shippedAt > $1.shippedAt }
        guard let newest = all.first else { return }
        markSeen(upTo: newest.id)
    }

    // MARK: Diff

    /// Entries the user hasn't seen yet, in newest-first order.
    ///
    /// Behaviour:
    ///   - `lastSeenID == nil` (fresh install / no marker): returns the
    ///     most recent `recentFallbackCount` entries so new users see
    ///     something useful on first launch.
    ///   - `lastSeenID` matches an entry: returns the slice of entries
    ///     newer than (above) that entry.
    ///   - `lastSeenID` is unknown (stale marker from a trimmed changelog):
    ///     same as nil — returns the most recent `recentFallbackCount`
    ///     entries rather than silently returning nothing.
    static func unseenEntries(
        lastSeenID: String?,
        now: Date = Date(),
        entries: [WhatsNewEntry]? = nil,
        recentFallbackCount: Int = 10
    ) -> [WhatsNewEntry] {
        _ = now
        let all = entries ?? loadEntries()

        // Newest first in the file already; defensively re-sort so we
        // don't depend on author discipline.
        let sorted = all.sorted { $0.shippedAt > $1.shippedAt }

        guard let marker = lastSeenID,
              let markerIndex = sorted.firstIndex(where: { $0.id == marker }) else {
            // No marker or stale marker → show recent entries.
            return Array(sorted.prefix(recentFallbackCount))
        }
        // Return everything strictly newer than the marker.
        return Array(sorted.prefix(upTo: markerIndex))
    }
}
