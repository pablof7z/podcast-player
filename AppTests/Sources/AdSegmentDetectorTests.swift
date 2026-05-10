import XCTest
@testable import Podcastr

/// Pins the pure pieces of `AdSegmentDetector`:
///   1. `parseAdSegments` — JSON contract, monotonic + non-overlapping
///      validation, duration clamp, default `.midroll` kind fallback.
///   2. `Episode.Chapter.overlapsAd(in:adSegments:)` — half-open interval
///      overlap with implicit end-time resolution.
///   3. `AppStateStore.setEpisodeAdSegments` round-trips through the
///      Episode model's Codable layer.
///
/// The LLM round-trip itself isn't tested here — `WikiOpenRouterClient.live`
/// would need a real key. Detector behaviour past the parse boundary is
/// integration territory.
@MainActor
final class AdSegmentDetectorTests: XCTestCase {

    private var detector: AdSegmentDetector!

    override func setUp() {
        super.setUp()
        detector = AdSegmentDetector.shared
    }

    override func tearDown() {
        detector = nil
        super.tearDown()
    }

    // MARK: - parseAdSegments

    func testParseAdSegmentsHappyPath() {
        let raw = """
        {"ads":[{"start_seconds":0,"end_seconds":30,"kind":"preroll"},{"start_seconds":600,"end_seconds":660,"kind":"midroll"}]}
        """
        let result = detector.parseAdSegments(raw, durationCap: 3600)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 2)
        XCTAssertEqual(result?[0].kind, .preroll)
        XCTAssertEqual(result?[0].start, 0)
        XCTAssertEqual(result?[0].end, 30)
        XCTAssertEqual(result?[1].kind, .midroll)
    }

    func testParseAdSegmentsReturnsEmptyForEmptyAdsArray() {
        let raw = """
        {"ads":[]}
        """
        let result = detector.parseAdSegments(raw, durationCap: 3600)
        XCTAssertNotNil(result, "empty array is a valid 'no ads found' result, not nil")
        XCTAssertEqual(result?.count, 0)
    }

    func testParseAdSegmentsRejectsMalformedJSON() {
        XCTAssertNil(detector.parseAdSegments("not json", durationCap: 3600))
        XCTAssertNil(detector.parseAdSegments(#"{"chapters":[]}"#, durationCap: 3600))
    }

    func testParseAdSegmentsDropsZeroLengthRanges() {
        let raw = """
        {"ads":[{"start_seconds":100,"end_seconds":100,"kind":"midroll"},{"start_seconds":200,"end_seconds":260,"kind":"midroll"}]}
        """
        let result = detector.parseAdSegments(raw, durationCap: 3600)
        XCTAssertEqual(result?.count, 1, "zero-length range should be rejected")
        XCTAssertEqual(result?.first?.start, 200)
    }

    func testParseAdSegmentsRejectsOverlappingRanges() {
        // Second range starts inside the first → drop the second.
        let raw = """
        {"ads":[{"start_seconds":0,"end_seconds":120,"kind":"preroll"},{"start_seconds":60,"end_seconds":180,"kind":"midroll"}]}
        """
        let result = detector.parseAdSegments(raw, durationCap: 3600)
        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.end, 120)
    }

    func testParseAdSegmentsRejectsNonMonotonicRanges() {
        // Second range is BEFORE the first → drop the second.
        let raw = """
        {"ads":[{"start_seconds":300,"end_seconds":360,"kind":"midroll"},{"start_seconds":100,"end_seconds":160,"kind":"midroll"}]}
        """
        let result = detector.parseAdSegments(raw, durationCap: 3600)
        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.start, 300)
    }

    func testParseAdSegmentsClampsToDurationCap() {
        let raw = """
        {"ads":[{"start_seconds":3500,"end_seconds":9999,"kind":"postroll"}]}
        """
        let result = detector.parseAdSegments(raw, durationCap: 3600)
        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.end, 3600, "end past duration cap is clamped")
    }

    func testParseAdSegmentsDefaultsKindToMidroll() {
        // Missing `kind` → midroll.
        let raw = """
        {"ads":[{"start_seconds":0,"end_seconds":30}]}
        """
        let result = detector.parseAdSegments(raw, durationCap: 3600)
        XCTAssertEqual(result?.first?.kind, .midroll)
    }

    func testParseAdSegmentsRejectsUnknownKindAsMidroll() {
        let raw = """
        {"ads":[{"start_seconds":0,"end_seconds":30,"kind":"bumper"}]}
        """
        let result = detector.parseAdSegments(raw, durationCap: 3600)
        XCTAssertEqual(result?.first?.kind, .midroll, "unknown kind defaults to .midroll")
    }

    // MARK: - Chapter overlap helper

    func testChapterOverlapsAdReturnsFalseForEmptyAds() {
        let chapter = Episode.Chapter(startTime: 0, title: "Cold open")
        XCTAssertFalse(chapter.overlapsAd(in: [chapter], adSegments: []))
    }

    func testChapterOverlapsAdDetectsContainedAd() {
        let chapters = [
            Episode.Chapter(startTime: 0, title: "Cold open"),
            Episode.Chapter(startTime: 600, title: "Topic A"),
            Episode.Chapter(startTime: 1200, title: "Topic B")
        ]
        let ads = [Episode.AdSegment(start: 660, end: 720, kind: .midroll)]
        XCTAssertTrue(chapters[1].overlapsAd(in: chapters, adSegments: ads))
        XCTAssertFalse(chapters[0].overlapsAd(in: chapters, adSegments: ads))
        XCTAssertFalse(chapters[2].overlapsAd(in: chapters, adSegments: ads))
    }

    func testChapterOverlapsAdUsesExplicitEndTime() {
        // Explicit endTime — ignore neighbouring chapters when computing
        // the chapter window. Ad at 700 sits OUTSIDE [0, 500] → no overlap.
        let chapter = Episode.Chapter(startTime: 0, endTime: 500, title: "Cold open")
        let nextChapter = Episode.Chapter(startTime: 800, title: "Topic A")
        let ads = [Episode.AdSegment(start: 700, end: 750, kind: .midroll)]
        XCTAssertFalse(chapter.overlapsAd(in: [chapter, nextChapter], adSegments: ads))
    }

    func testChapterOverlapsAdLastChapterExtendsToInfinity() {
        let chapters = [
            Episode.Chapter(startTime: 0, title: "Cold open"),
            Episode.Chapter(startTime: 600, title: "Topic A")
        ]
        // Ad sits after the last chapter's start with no upper bound — the
        // last chapter must claim it.
        let ads = [Episode.AdSegment(start: 3500, end: 3580, kind: .postroll)]
        XCTAssertTrue(chapters[1].overlapsAd(in: chapters, adSegments: ads))
    }

    func testChapterOverlapsAdRespectsHalfOpenInterval() {
        // Ad starts exactly at the next chapter's startTime → does NOT
        // overlap the previous chapter. Half-open semantics keep adjacent
        // chapter+ad pairs disjoint.
        let chapters = [
            Episode.Chapter(startTime: 0, title: "Cold open"),
            Episode.Chapter(startTime: 500, title: "Topic A")
        ]
        let ads = [Episode.AdSegment(start: 500, end: 560, kind: .midroll)]
        XCTAssertFalse(chapters[0].overlapsAd(in: chapters, adSegments: ads))
        XCTAssertTrue(chapters[1].overlapsAd(in: chapters, adSegments: ads))
    }

    // MARK: - Codable round-trip

    func testEpisodeAdSegmentsCodableRoundTrip() throws {
        let original = Episode(
            subscriptionID: UUID(),
            guid: "rt-1",
            title: "Round-trip",
            pubDate: Date(timeIntervalSince1970: 1_700_000_000),
            enclosureURL: URL(string: "https://example.com/a.mp3")!,
            adSegments: [
                Episode.AdSegment(start: 0, end: 30, kind: .preroll),
                Episode.AdSegment(start: 1200, end: 1260, kind: .midroll)
            ]
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Episode.self, from: encoded)
        XCTAssertEqual(decoded.adSegments?.count, 2)
        XCTAssertEqual(decoded.adSegments?.first?.kind, .preroll)
        XCTAssertEqual(decoded.adSegments?.last?.end, 1260)
    }

    func testEpisodeAdSegmentsAbsentFieldDecodesAsNil() throws {
        // Older saved state has no `adSegments` key — must decode silently.
        // Build the fixture by encoding an Episode with `adSegments == nil`
        // and stripping the field, which is more robust than hand-writing
        // the tagged-enum JSON that `DownloadState` / `TranscriptState` use.
        let template = Episode(
            subscriptionID: UUID(),
            guid: "legacy",
            title: "Legacy",
            pubDate: Date(timeIntervalSince1970: 1_700_000_000),
            enclosureURL: URL(string: "https://example.com/a.mp3")!,
            adSegments: nil
        )
        let encoded = try JSONEncoder().encode(template)
        // Confirm the encoder emits the field even when nil OR drops it — we
        // just need the decoder to tolerate its absence. Strip the key
        // explicitly to simulate an older saved-state blob.
        guard var dict = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            return XCTFail("expected dict-shaped Episode encoding")
        }
        dict.removeValue(forKey: "adSegments")
        let strippedData = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(Episode.self, from: strippedData)
        XCTAssertNil(decoded.adSegments)
    }

    // MARK: - setEpisodeAdSegments round-trip

    func testSetEpisodeAdSegmentsRoundTripsThroughStore() {
        let result = AppStateTestSupport.makeIsolatedStore()
        defer { AppStateTestSupport.disposeIsolatedStore(at: result.fileURL) }
        let store = result.store

        let episode = Episode(
            subscriptionID: UUID(),
            guid: "store-rt-1",
            title: "Store Round-trip",
            pubDate: Date(timeIntervalSince1970: 1_700_000_000),
            enclosureURL: URL(string: "https://example.com/a.mp3")!
        )
        store.state.episodes = [episode]

        let segments: [Episode.AdSegment] = [
            Episode.AdSegment(start: 0, end: 30, kind: .preroll),
            Episode.AdSegment(start: 1500, end: 1560, kind: .midroll)
        ]
        store.setEpisodeAdSegments(episode.id, segments: segments)

        let resolved = store.episode(id: episode.id)?.adSegments
        XCTAssertEqual(resolved?.count, 2)
        XCTAssertEqual(resolved?.first?.kind, .preroll)
        XCTAssertEqual(resolved?.last?.start, 1500)

        // Empty array means "detection ran, found no ads" — distinct from
        // nil. The store must persist that distinction.
        store.setEpisodeAdSegments(episode.id, segments: [])
        XCTAssertEqual(store.episode(id: episode.id)?.adSegments?.count, 0)
        XCTAssertNotNil(store.episode(id: episode.id)?.adSegments, "empty != nil")
    }
}
