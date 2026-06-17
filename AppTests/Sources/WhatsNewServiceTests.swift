import XCTest
@testable import Podcastr

/// Coverage for `WhatsNewService` — the changelog-diff helper that
/// decides which entries to surface on the next cold launch.
///
/// Tests use fixture JSON literals rather than the real bundled
/// `changelog/` directory so they don't drift as the changelog grows.
/// Each literal is a SINGLE entry file, matching the on-disk
/// one-file-per-entry layout `WhatsNewService.decode` now expects.
@MainActor
final class WhatsNewServiceTests: XCTestCase {

    // MARK: - Fixture

    /// Three single-entry files, newest first. Dates are spaced one day
    /// apart so sort-by-shippedAt is unambiguous. Mirrors the per-file
    /// changelog layout: each string is the full contents of one
    /// `changelog/<timestamp>.json`.
    private let entryFilesJSON: [String] = [
        #"""
        {
          "shipped_at": "2026-05-10T22:00:00Z",
          "lines": ["Newest line"]
        }
        """#,
        #"""
        {
          "shipped_at": "2026-05-09T12:00:00Z",
          "lines": ["Middle line A", "Middle line B"]
        }
        """#,
        #"""
        {
          "shipped_at": "2026-05-08T08:00:00Z",
          "lines": ["Oldest line"]
        }
        """#,
    ]

    /// Decodes each per-file fixture and sorts newest-first to mirror what
    /// `loadEntries` + the diff helpers would produce from the bundled dir
    /// (directory enumeration order is not guaranteed, so the production
    /// loader never relies on it either).
    private func fixtureEntries() throws -> [WhatsNewEntry] {
        try entryFilesJSON
            .map { try WhatsNewService.decode(Data($0.utf8)) }
            .sorted { $0.shippedAt > $1.shippedAt }
    }

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    // MARK: - Decoding

    func testSingleEntryFileDecodes() throws {
        let entry = try WhatsNewService.decode(Data(entryFilesJSON[0].utf8))
        XCTAssertEqual(entry.lines, ["Newest line"])
        XCTAssertEqual(entry.shippedAt, date("2026-05-10T22:00:00Z"))
    }

    func testFixtureEntriesDecodeAndSortNewestFirst() throws {
        let entries = try fixtureEntries()
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].lines, ["Newest line"])
        XCTAssertEqual(entries[1].lines.count, 2)
        XCTAssertEqual(entries[2].lines, ["Oldest line"])
    }

    /// The bundled `changelog/` directory shipped with the app must
    /// enumerate and decode into at least one well-formed entry — a parse
    /// failure or an empty/missing directory would silently disable the
    /// sheet for every user. The set of entries is allowed to evolve.
    func testBundledChangelogParses() {
        let entries = WhatsNewService.loadEntries()
        XCTAssertFalse(entries.isEmpty, "Bundled changelog/ should ship with at least one entry.")
        XCTAssertFalse(entries.contains { $0.lines.isEmpty }, "Every bundled entry needs at least one line.")
        let timestamps = entries.map(\.shippedAt)
        XCTAssertEqual(Set(timestamps).count, timestamps.count, "Every entry needs a unique shipped_at timestamp.")
    }

    // MARK: - unseenEntries

    func testUnseenEntriesEmptyOnFreshInstall() throws {
        let entries = try fixtureEntries()
        // Fresh install: no marker stored. The seeding step is the caller's
        // responsibility — `unseenEntries` itself should return empty so the
        // sheet doesn't dump the entire changelog at first launch.
        let unseen = WhatsNewService.unseenEntries(lastSeenAt: nil, entries: entries)
        XCTAssertTrue(unseen.isEmpty, "Fresh install must not dump the entire changelog at first launch.")
    }

    func testUnseenEntriesEmptyWhenMarkerIsNewest() throws {
        let entries = try fixtureEntries()
        let marker = date("2026-05-10T22:00:00Z")
        let unseen = WhatsNewService.unseenEntries(lastSeenAt: marker, entries: entries)
        XCTAssertTrue(unseen.isEmpty, "User has already seen the newest entry — nothing to show.")
    }

    func testUnseenEntriesReturnsNewerSliceWhenMarkerIsMiddle() throws {
        let entries = try fixtureEntries()
        let marker = date("2026-05-09T12:00:00Z")
        let unseen = WhatsNewService.unseenEntries(lastSeenAt: marker, entries: entries)
        XCTAssertEqual(unseen.map(\.lines), [["Newest line"]])
    }

    func testUnseenEntriesReturnsAllNewerWhenMarkerIsOldest() throws {
        let entries = try fixtureEntries()
        let marker = date("2026-05-08T08:00:00Z")
        let unseen = WhatsNewService.unseenEntries(lastSeenAt: marker, entries: entries)
        XCTAssertEqual(unseen.map(\.lines), [["Newest line"], ["Middle line A", "Middle line B"]])
    }

    func testUnseenEntriesEmptyWhenMarkerIsAfterEverything() throws {
        let entries = try fixtureEntries()
        // Marker is in the future relative to all entries — could happen if
        // the user's clock drifted, or after entries are trimmed below the
        // marker. Nothing newer = nothing to show.
        let marker = date("2030-01-01T00:00:00Z")
        let unseen = WhatsNewService.unseenEntries(lastSeenAt: marker, entries: entries)
        XCTAssertTrue(unseen.isEmpty)
    }

    func testUnseenEntriesAreNewestFirst() throws {
        let entries = try fixtureEntries()
        let marker = date("2026-05-08T08:00:00Z")
        let unseen = WhatsNewService.unseenEntries(lastSeenAt: marker, entries: entries)
        let dates = unseen.map(\.shippedAt)
        XCTAssertEqual(dates, dates.sorted(by: >), "Unseen entries must be newest-first.")
    }
}
