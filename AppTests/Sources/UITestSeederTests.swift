import XCTest
@testable import Podcastr

final class UITestSeederTests: XCTestCase {
    func testSeededDownloadURLUsesCanonicalDownloadStorePath() throws {
        let episodeID = try XCTUnwrap(UUID(uuidString: "A1A1FFFF-0001-0002-0001-000000000001"))
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/audio/default.mp3"))
        let episode = Episode(
            id: episodeID,
            podcastID: UUID(),
            guid: "seeded-episode",
            title: "Seeded Episode",
            pubDate: Date(timeIntervalSince1970: 0),
            enclosureURL: sourceURL,
            enclosureMimeType: "audio/mpeg"
        )

        let seededURL = UITestSeeder.seededDownloadURL(
            episodeID: episodeID.uuidString,
            sourceURL: sourceURL
        )
        let canonicalURL = EpisodeDownloadStore.shared.localFileURL(for: episode)

        XCTAssertEqual(seededURL.standardizedFileURL.path, canonicalURL.standardizedFileURL.path)
        XCTAssertTrue(seededURL.path.contains("/Downloads/"))
        XCTAssertFalse(seededURL.path.localizedCaseInsensitiveContains("/podcastr/downloads/"))
    }
}
