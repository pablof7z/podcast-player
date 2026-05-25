import Foundation
import XCTest
@testable import Pod0

final class NostrPodcastDiscoveryServiceTests: XCTestCase {
    func testParseShowUsesPubkeyCoordinateWithoutDTag() throws {
        let event: [String: Any] = [
            "id": "show-event",
            "pubkey": String(repeating: "a", count: 64),
            "created_at": 1_800_000_000,
            "content": "fallback",
            "tags": [
                ["title", "Pod0 Daily"],
                ["description", "A NIP-F4 show"],
                ["author", "Pod0"],
                ["image", "https://example.com/art.png"],
                ["t", "technology"],
            ],
        ]

        let show = try XCTUnwrap(NostrPodcastDiscoveryService.parseShow(from: event))

        XCTAssertEqual(show.id, String(repeating: "a", count: 64))
        XCTAssertEqual(show.coordinate, "10154:\(String(repeating: "a", count: 64))")
        XCTAssertEqual(show.title, "Pod0 Daily")
        XCTAssertEqual(show.description, "A NIP-F4 show")
        XCTAssertEqual(show.author, "Pod0")
        XCTAssertEqual(show.categories, ["technology"])
        XCTAssertEqual(show.imageURL?.absoluteString, "https://example.com/art.png")
    }

    func testParseEpisodeUsesEventIDAndAudioTag() throws {
        let podcastID = UUID()
        let event: [String: Any] = [
            "id": String(repeating: "c", count: 64),
            "pubkey": String(repeating: "a", count: 64),
            "created_at": 1_800_000_001,
            "content": "episode body",
            "tags": [
                ["title", "Launch Notes"],
                ["description", "Episode description"],
                ["audio", "https://cdn.example.com/audio.mp3", "audio/mpeg"],
                ["duration", "180"],
                ["transcript", "https://cdn.example.com/transcript.vtt", "text/vtt"],
            ],
        ]

        let episode = try XCTUnwrap(NostrPodcastDiscoveryService.parseEpisode(from: event, podcastID: podcastID))

        XCTAssertEqual(episode.podcastID, podcastID)
        XCTAssertEqual(episode.guid, String(repeating: "c", count: 64))
        XCTAssertEqual(episode.title, "Launch Notes")
        XCTAssertEqual(episode.description, "Episode description")
        XCTAssertEqual(episode.enclosureURL.absoluteString, "https://cdn.example.com/audio.mp3")
        XCTAssertEqual(episode.enclosureMimeType, "audio/mpeg")
        XCTAssertEqual(episode.duration, 180)
        XCTAssertEqual(episode.pubDate, Date(timeIntervalSince1970: 1_800_000_001))
        XCTAssertEqual(episode.publisherTranscriptURL?.absoluteString, "https://cdn.example.com/transcript.vtt")
    }
}
