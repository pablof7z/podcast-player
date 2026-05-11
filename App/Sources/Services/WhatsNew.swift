import Foundation

// MARK: - WhatsNewEntry
//
// One entry == one commit that shipped a user-facing change. The `id` is
// the short commit SHA (or a slug for changes that span multiple commits),
// kept around for human reference and changelog rendering. The
// authoritative "did the user see this" comparison uses `shippedAt` — a
// timestamp is robust to entries getting renamed, deleted, or trimmed in
// future builds in a way SHA matching never was.

struct WhatsNewEntry: Decodable, Sendable, Identifiable, Equatable {
    let id: String           // short commit SHA / slug
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
//   1) Which entries have been shipped since the user's last-seen marker?
//   2) Persists the "I've seen up to timestamp X" marker so the same
//      content doesn't re-surface on every cold launch.
//
// The marker is a timestamp (ISO-8601, stored in `UserDefaults.standard`
// under `whatsNew.lastSeenAt`). Earlier builds used an entry-ID marker
// under `whatsNew.lastSeenID`; that key is migrated automatically if it
// shows up.
//
// First-launch semantics: when no marker exists at all, the marker is
// silently seeded to the newest entry's `shippedAt`. The user sees an
// empty sheet on first install — i.e. NO sheet is shown, because there's
// nothing newer than "everything that already shipped." From the next
// build forward, any newly appended entry surfaces.

@MainActor
enum WhatsNewService {

    // MARK: Constants

    /// Timestamp marker — the current source of truth.
    static let lastSeenAtKey = "whatsNew.lastSeenAt"
    /// Legacy ID-based marker. Migrated on first launch then removed.
    static let legacyLastSeenIDKey = "whatsNew.lastSeenID"

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

    /// The "I've seen everything up through this timestamp" marker, read
    /// from `UserDefaults.standard`. `nil` on a brand-new install (before
    /// `migrateAndSeedIfNeeded` has run).
    static var lastSeenAt: Date? {
        guard let s = UserDefaults.standard.string(forKey: lastSeenAtKey),
              !s.isEmpty else {
            return nil
        }
        return Self.iso8601.date(from: s)
    }

    /// Persist the marker. Call when the user dismisses the sheet, with the
    /// newest visible entry's `shippedAt`.
    static func markSeen(at date: Date) {
        UserDefaults.standard.set(Self.iso8601.string(from: date), forKey: lastSeenAtKey)
    }

    /// Bring the marker up to date on cold launch.
    ///
    /// Two cases handled:
    ///   1. Legacy `whatsNew.lastSeenID` exists from an older build — look
    ///      up that entry's `shippedAt` and write it as the new timestamp
    ///      marker, then delete the legacy key.
    ///   2. No marker at all (fresh install) — silently seed the marker to
    ///      the newest entry's `shippedAt` so the user doesn't see "the
    ///      entire changelog ever" as their first impression of the app.
    ///      Future entries appended after this build will still surface.
    ///
    /// Idempotent: a no-op once a current-format marker is present.
    static func migrateAndSeedIfNeeded(entries: [WhatsNewEntry]? = nil) {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: lastSeenAtKey) != nil { return }

        let sorted = (entries ?? loadEntries()).sorted { $0.shippedAt > $1.shippedAt }

        if let legacyID = defaults.string(forKey: legacyLastSeenIDKey),
           !legacyID.isEmpty,
           let entry = sorted.first(where: { $0.id == legacyID }) {
            markSeen(at: entry.shippedAt)
            defaults.removeObject(forKey: legacyLastSeenIDKey)
            return
        }
        // No usable legacy marker — seed silently.
        if let newest = sorted.first {
            markSeen(at: newest.shippedAt)
        }
        defaults.removeObject(forKey: legacyLastSeenIDKey)
    }

    // MARK: Diff

    /// Entries strictly newer than `lastSeenAt`, in newest-first order.
    ///
    /// `lastSeenAt == nil` returns `[]` rather than the full changelog —
    /// `migrateAndSeedIfNeeded` is responsible for seeding the marker on
    /// fresh installs; if it hasn't run yet, the caller should not surface
    /// anything.
    static func unseenEntries(
        lastSeenAt: Date?,
        entries: [WhatsNewEntry]? = nil
    ) -> [WhatsNewEntry] {
        guard let marker = lastSeenAt else { return [] }
        let all = entries ?? loadEntries()
        return all
            .filter { $0.shippedAt > marker }
            .sorted { $0.shippedAt > $1.shippedAt }
    }

    // MARK: Helpers

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
