import XCTest
@testable import Podcastr

@MainActor
final class NostrPodcastDiscoverySmokeTests: XCTestCase {

    func testPrimalReturnsNIPF4ShowsThroughAppDiscoveryStack() async throws {
        guard ProcessInfo.processInfo.environment["PODCASTR_LIVE_NOSTR_SMOKE"] == "1" else {
            throw XCTSkip("Set PODCASTR_LIVE_NOSTR_SMOKE=1 to run the live relay smoke test.")
        }

        await NostrStack.shared.bind(store: AppStateStore())
        await NostrStack.shared.start()

        let service = NostrPodcastDiscoveryService()
        let shows = await service.fetchShows(relayURL: URL(string: "wss://relay.primal.net")!)

        XCTAssertFalse(shows.isEmpty, "relay.primal.net should return live kind:10154 NIP-F4 shows")
        XCTAssertTrue(shows.contains { !$0.title.isEmpty })
    }
}
