import XCTest
@testable import Podcastr

/// Coverage for `WhatsNewService` — the changelog-diff helper that
/// decides which entries to surface on the next cold launch.
///
/// Tests use a fixture JSON literal rather than the real bundled
/// `whats-new.json` so they don't drift as the changelog grows.
@MainActor
final class WhatsNewServiceTests: XCTestCase {

    // MARK: - Fixture

    /// Three entries, newest first. Hashes are short SHAs to mirror the
    /// real format. Dates are spaced one day apart so sort-by-shippedAt
    /// is unambiguous.
    private let fixtureJSON = #"""
    {
      "schema_version": 1,
      "entries": [
        {
          "id": "ccc3333",
          "shipped_at": "2026-05-10T22:00:00Z",
          "lines": ["Newest line"]
        },
        {
          "id": "bbb2222",
          "shipped_at": "2026-05-09T12:00:00Z",
          "lines": ["Middle line A", "Middle line B"]
        },
        {
          "id": "aaa1111",
          "shipped_at": "2026-05-08T08:00:00Z",
          "lines": ["Oldest line"]
        }
      ]
    }
    """#

    private func fixtureEntries() throws -> [WhatsNewEntry] {
        let data = Data(fixtureJSON.utf8)
        return try WhatsNewService.decode(data)
    }

    // MARK: - Decoding

    func testFixtureJSONDecodes() throws {
        let entries = try fixtureEntries()
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].id, "ccc3333")
        XCTAssertEqual(entries[0].lines, ["Newest line"])
        XCTAssertEqual(entries[1].lines.count, 2)
    }

    /// The bundled `whats-new.json` shipped with the app must remain
    /// well-formed — a parse failure would silently disable the sheet
    /// for every user. The list itself is allowed to evolve.
    func testBundledChangelogParses() {
        let entries = WhatsNewService.loadEntries()
        XCTAssertFalse(entries.isEmpty, "Bundled whats-new.json should ship with at least one entry.")
        XCTAssertFalse(entries.contains { $0.id.isEmpty }, "Every bundled entry needs a non-empty short SHA.")
        XCTAssertFalse(entries.contains { $0.lines.isEmpty }, "Every bundled entry needs at least one line.")
    }

    // MARK: - unseenEntries

    func testUnseenEntriesEmptyOnFreshInstall() throws {
        let entries = try fixtureEntries()
        // Fresh install: no marker stored.
        let unseen = WhatsNewService.unseenEntries(lastSeenID: nil, entries: entries)
        XCTAssertTrue(unseen.isEmpty, "Fresh install must not dump the entire changelog at first launch.")
    }

    func testUnseenEntriesEmptyWhenMarkerIsNewest() throws {
        let entries = try fixtureEntries()
        let unseen = WhatsNewService.unseenEntries(lastSeenID: "ccc3333", entries: entries)
        XCTAssertTrue(unseen.isEmpty, "User has already seen the newest entry — nothing to show.")
    }

    func testUnseenEntriesReturnsNewerSliceWhenMarkerIsMiddle() throws {
        let entries = try fixtureEntries()
        let unseen = WhatsNewService.unseenEntries(lastSeenID: "bbb2222", entries: entries)
        XCTAssertEqual(unseen.map(\.id), ["ccc3333"])
    }

    func testUnseenEntriesReturnsAllNewerWhenMarkerIsOldest() throws {
        let entries = try fixtureEntries()
        let unseen = WhatsNewService.unseenEntries(lastSeenID: "aaa1111", entries: entries)
        XCTAssertEqual(unseen.map(\.id), ["ccc3333", "bbb2222"])
    }

    func testUnseenEntriesEmptyForUnknownMarker() throws {
        let entries = try fixtureEntries()
        // Marker references a commit that's no longer in the changelog
        // (could happen if entries get trimmed). Conservative: don't
        // re-show everything.
        let unseen = WhatsNewService.unseenEntries(lastSeenID: "deadbee", entries: entries)
        XCTAssertTrue(unseen.isEmpty)
    }

    func testUnseenEntriesAreNewestFirst() throws {
        let entries = try fixtureEntries()
        let unseen = WhatsNewService.unseenEntries(lastSeenID: "aaa1111", entries: entries)
        let dates = unseen.map(\.shippedAt)
        XCTAssertEqual(dates, dates.sorted(by: >), "Unseen entries must be newest-first.")
    }
}
