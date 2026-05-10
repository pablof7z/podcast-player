import XCTest
@testable import Podcastr

/// Coverage for `TranscriptIngestService.evaluateAutoIngest(newEpisodeIDs:)`
/// — the feed-refresh-triggered batch path that finally wires
/// `Settings.autoIngestPublisherTranscripts` to actual ingestion. Without
/// this hook, the dormant-toggle bug meant publisher transcripts only
/// landed for episodes the user manually opened in detail view.
///
/// We can't exercise the real fetch (network + Kingfisher + sqlite-vec
/// indexing) in a unit test, so the assertions focus on the gating + filter
/// logic via the empty-input fast paths the helper uses. The service's
/// `inFlight` set + `attach` requirement prevent any actual network call
/// from firing here.
@MainActor
final class TranscriptAutoIngestTests: XCTestCase {

    // MARK: - Empty-input fast paths

    func testNoOpForEmptyIDList() {
        // `evaluateAutoIngest` should bail before any state lookup when
        // there are no IDs to consider.
        let service = TranscriptIngestService()
        // No throw, no crash, no async side effects: the call is sync.
        service.evaluateAutoIngest(newEpisodeIDs: [])
    }

    func testNoOpWhenStoreUnattached() {
        // The shared RAGService starts unattached in test contexts. The
        // helper logs a warning and returns rather than crashing.
        let service = TranscriptIngestService()
        service.evaluateAutoIngest(newEpisodeIDs: [UUID(), UUID()])
    }

    // MARK: - Settings default

    func testAutoIngestDefaultsOn() {
        // The agent layer (RAG, wiki, briefings) only works once
        // transcripts exist. Defaulting off would leave most users with no
        // transcripts despite the feeds shipping them — the very bug this
        // helper exists to fix. Lock the default in.
        let s = Settings()
        XCTAssertTrue(s.autoIngestPublisherTranscripts)
    }
}
