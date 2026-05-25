import XCTest
@testable import Podcast

// MARK: - PodcastActivityAttributes wire-shape tests
//
// `PodcastActivityAttributes` is shared verbatim between the main app
// target (which calls `Activity.request` / `activity.update`) and the
// `PodcastWidget` extension target (which renders
// `ActivityConfiguration<PodcastActivityAttributes>`). ActivityKit
// serializes `ContentState` to disk so the activity survives across
// app launches and device locks — these tests pin the JSON shape so
// a hand-edit to one side fails the build instead of silently
// breaking deserialization on the other.

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.2, *)
final class PodcastLiveActivityAttributesTests: XCTestCase {

    // MARK: - ContentState round-trip

    func testContentStateRoundTripsThroughJSON() throws {
        let original = PodcastActivityAttributes.ContentState(
            episodeTitle: "Ep 42 — the long one",
            podcastTitle: "Some Show",
            positionSecs: 123.4,
            durationSecs: 3600,
            isPlaying: true,
            artworkURL: URL(string: "https://example.com/art.png"))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            PodcastActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testContentStateRoundTripsWithoutArtwork() throws {
        let original = PodcastActivityAttributes.ContentState(
            episodeTitle: "No artwork episode",
            podcastTitle: "Tiny Show",
            positionSecs: 0,
            durationSecs: 0,
            isPlaying: false,
            artworkURL: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            PodcastActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - positionFraction

    func testPositionFractionReportsZeroForZeroDuration() {
        let state = PodcastActivityAttributes.ContentState(
            episodeTitle: "x", podcastTitle: "y",
            positionSecs: 30, durationSecs: 0,
            isPlaying: true, artworkURL: nil)
        XCTAssertEqual(state.positionFraction, 0)
    }

    func testPositionFractionClampsAtOne() {
        let state = PodcastActivityAttributes.ContentState(
            episodeTitle: "x", podcastTitle: "y",
            positionSecs: 9_999, durationSecs: 100,
            isPlaying: true, artworkURL: nil)
        XCTAssertEqual(state.positionFraction, 1)
    }

    func testPositionFractionClampsAtZero() {
        let state = PodcastActivityAttributes.ContentState(
            episodeTitle: "x", podcastTitle: "y",
            positionSecs: -50, durationSecs: 100,
            isPlaying: true, artworkURL: nil)
        XCTAssertEqual(state.positionFraction, 0)
    }

    func testPositionFractionComputesMidpoint() {
        let state = PodcastActivityAttributes.ContentState(
            episodeTitle: "x", podcastTitle: "y",
            positionSecs: 50, durationSecs: 100,
            isPlaying: true, artworkURL: nil)
        XCTAssertEqual(state.positionFraction, 0.5, accuracy: 0.0001)
    }

    // MARK: - Attributes

    func testAttributesRoundTripsThroughJSON() throws {
        let original = PodcastActivityAttributes(episodeID: "ep-123")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            PodcastActivityAttributes.self, from: data)
        XCTAssertEqual(decoded.episodeID, original.episodeID)
    }

    func testAttributesRoundTripsWithoutEpisodeID() throws {
        let original = PodcastActivityAttributes(episodeID: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            PodcastActivityAttributes.self, from: data)
        XCTAssertNil(decoded.episodeID)
    }
}

#endif
