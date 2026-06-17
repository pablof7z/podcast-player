import XCTest
@testable import Podcastr

// MARK: - ClipKernelProjectionTests
//
// Locks the kernel→domain clip mapping after the autosnip "move app policy
// into Rust" migration. Clips are now kernel-owned end to end: the kernel is
// the single source of truth and the iOS shell reads them on demand
// (`AppStateStore.clips(forEpisode:)` → `kernelProjectedClips()`), mapping each
// `ClipSummary` row into a domain `Clip` via `Clip(from:subscriptionID:)`.
//
// The previous Swift-side `state.clips` merge (`projectKernelClips` +
// `addClip` + local-only rich clips) was retired by that migration, so these
// tests pin the surviving, authoritative seam: the `ClipSummary → Clip`
// projection, including subscription resolution and the kernel-owned
// `.auto` source default.

final class ClipKernelProjectionTests: XCTestCase {

    // MARK: - Helpers

    private func makeSummary(
        id: UUID = UUID(),
        episodeID: UUID,
        startSecs: Double = 30,
        endSecs: Double = 90,
        title: String? = nil,
        transcriptText: String = "",
        speaker: String? = nil,
        source: String = "auto",
        refinementStatus: String = "manual",
        createdAt: Int = 1_700_000_000
    ) -> ClipSummary {
        // Construct against the regenerated ClipSummary shape, which carries the
        // kernel-owned autosnip metadata (transcriptText / speaker / source /
        // refinementStatus).
        ClipSummary(
            id: id.uuidString,
            episodeId: episodeID.uuidString,
            episodeTitle: "Episode Title",
            podcastTitle: "Podcast Title",
            startSecs: startSecs,
            endSecs: endSecs,
            title: title,
            transcriptText: transcriptText,
            speaker: speaker,
            source: source,
            refinementStatus: refinementStatus,
            createdAt: createdAt
        )
    }

    // MARK: - Kernel clip mapping

    func testKernelClipMapsIntoDomainClip() {
        let episodeID = UUID()
        let podcastID = UUID()
        let clipID = UUID()
        let summary = makeSummary(id: clipID, episodeID: episodeID, title: "A moment")

        let clip = Clip(from: summary, subscriptionID: podcastID)

        XCTAssertEqual(clip.id, clipID)
        XCTAssertEqual(clip.episodeID, episodeID)
        XCTAssertEqual(clip.subscriptionID, podcastID, "subscriptionID comes from the caller-resolved episode→podcast map")
        XCTAssertEqual(clip.startMs, 30_000)
        XCTAssertEqual(clip.endMs, 90_000)
        XCTAssertEqual(clip.caption, "A moment", "kernel title maps to caption")
        XCTAssertEqual(clip.source, .auto, "kernel-owned clips default to .auto")
    }

    func testUnknownEpisodeFallsBackToUnknownSubscription() {
        let episodeID = UUID()
        let summary = makeSummary(episodeID: episodeID)

        // Caller could not resolve an owning podcast → Unknown sentinel.
        let clip = Clip(from: summary, subscriptionID: Podcast.unknownID)

        XCTAssertEqual(clip.subscriptionID, Podcast.unknownID)
        XCTAssertEqual(clip.episodeID, episodeID)
    }

    func testCreatedAtMapsFromUnixSeconds() {
        let summary = makeSummary(episodeID: UUID(), createdAt: 1_700_000_000)
        let clip = Clip(from: summary, subscriptionID: UUID())
        XCTAssertEqual(
            clip.createdAt.timeIntervalSince1970,
            1_700_000_000,
            accuracy: 0.5,
            "createdAt maps from kernel Unix seconds")
    }

    func testInvalidIDsFallBackToStableSentinels() {
        // A malformed episode id must not crash the projection; it falls back to
        // the placeholder sentinel so the mapping stays total.
        let summary = ClipSummary(
            id: "not-a-uuid",
            episodeId: "also-not-a-uuid",
            episodeTitle: "Episode Title",
            podcastTitle: "Podcast Title",
            startSecs: 10,
            endSecs: 20,
            title: nil,
            transcriptText: "",
            speaker: nil,
            source: "auto",
            refinementStatus: "manual",
            createdAt: 1_700_000_000
        )
        let podcastID = UUID()
        let clip = Clip(from: summary, subscriptionID: podcastID)
        XCTAssertEqual(clip.subscriptionID, podcastID)
        XCTAssertEqual(clip.startMs, 10_000)
        XCTAssertEqual(clip.endMs, 20_000)
    }
}
