import Foundation
import XCTest
@testable import Podcastr

@MainActor
final class PersistenceDurabilityTests: XCTestCase {

    func testPersistenceSplitsLargeEpisodeStateAcrossSQLiteAndMetadata() async throws {
        let sharedFileURL = AppStateTestSupport.uniqueTempFileURL()
        defer { AppStateTestSupport.disposeIsolatedStore(at: sharedFileURL) }

        do {
            let made = AppStateTestSupport.makeIsolatedStore(fileURL: sharedFileURL)
            let firstStore = made.store
            let sub = makeSubscription(title: "Large State Show")
            XCTAssertTrue(firstStore.addSubscription(sub))

            let padding = String(repeating: "x", count: 4_096)
            var episodes: [Episode] = []
            episodes.reserveCapacity(1_500)
            for i in 0..<1_500 {
                var ep = makeEpisode(subscriptionID: sub.id, guid: "large-\(i)")
                ep.description = padding
                episodes.append(ep)
            }
            firstStore.upsertEpisodes(episodes, forSubscription: sub.id)
            XCTAssertEqual(
                firstStore.persistence.lastEpisodeWriteSummary.kind,
                .replaceAll,
                "Large initial episode imports should keep using the full-rebuild path."
            )

            var settings = firstStore.state.settings
            settings.hasCompletedOnboarding = true
            firstStore.updateSettings(settings)

            let metadata = try Data(contentsOf: sharedFileURL)
            XCTAssertLessThan(
                metadata.count,
                512 * 1024,
                "Episode payloads should live in SQLite, not the JSON metadata file."
            )
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: Persistence.episodeStoreURL(for: sharedFileURL).path)
            )
        }

        let reopened = AppStateTestSupport.makeIsolatedStore(fileURL: sharedFileURL, reset: false)
        XCTAssertTrue(reopened.store.state.settings.hasCompletedOnboarding)
        XCTAssertEqual(reopened.store.state.subscriptions.count, 1)
        XCTAssertEqual(reopened.store.state.episodes.count, 1_500)
    }

    func testSingleEpisodeMutationUsesDeltaWriteAndRoundTrips() async throws {
        let sharedFileURL = AppStateTestSupport.uniqueTempFileURL()
        defer { AppStateTestSupport.disposeIsolatedStore(at: sharedFileURL) }

        let targetID: UUID
        do {
            let made = AppStateTestSupport.makeIsolatedStore(fileURL: sharedFileURL)
            let store = made.store
            let sub = makeSubscription(title: "Delta Mutations")
            XCTAssertTrue(store.addSubscription(sub))
            let episodes = [
                makeEpisode(subscriptionID: sub.id, guid: "delta-1"),
                makeEpisode(subscriptionID: sub.id, guid: "delta-2"),
                makeEpisode(subscriptionID: sub.id, guid: "delta-3"),
            ]
            targetID = episodes[1].id
            store.upsertEpisodes(episodes, forSubscription: sub.id)

            store.persistence.resetEpisodeWriteSummary()
            store.setEpisodeStarred(targetID, true)

            let summary = store.persistence.lastEpisodeWriteSummary
            XCTAssertEqual(summary.kind, .delta)
            XCTAssertEqual(summary.upsertCount, 1)
            XCTAssertEqual(summary.deleteCount, 0)
            XCTAssertEqual(summary.sortOrderUpdateCount, 0)
        }

        let reopened = AppStateTestSupport.makeIsolatedStore(fileURL: sharedFileURL, reset: false)
        let target = try XCTUnwrap(reopened.store.state.episodes.first { $0.id == targetID })
        XCTAssertTrue(target.isStarred)
        XCTAssertEqual(reopened.store.state.episodes.count, 3)
    }

    func testSmallEpisodeDeleteUsesRowDeleteAndRoundTrips() async throws {
        let sharedFileURL = AppStateTestSupport.uniqueTempFileURL()
        defer { AppStateTestSupport.disposeIsolatedStore(at: sharedFileURL) }

        let deletedID: UUID
        let survivingIDs: [UUID]
        do {
            let made = AppStateTestSupport.makeIsolatedStore(fileURL: sharedFileURL)
            let store = made.store
            let sub = makeSubscription(title: "Delta Deletes")
            XCTAssertTrue(store.addSubscription(sub))
            let episodes = [
                makeEpisode(subscriptionID: sub.id, guid: "delete-1"),
                makeEpisode(subscriptionID: sub.id, guid: "delete-2"),
                makeEpisode(subscriptionID: sub.id, guid: "delete-3"),
            ]
            deletedID = episodes[1].id
            survivingIDs = [episodes[0].id, episodes[2].id]
            store.upsertEpisodes(episodes, forSubscription: sub.id)

            store.persistence.resetEpisodeWriteSummary()
            store.performMutationBatch {
                store.state.episodes.removeAll { $0.id == deletedID }
            }

            let summary = store.persistence.lastEpisodeWriteSummary
            XCTAssertEqual(summary.kind, .delta)
            XCTAssertEqual(summary.upsertCount, 0)
            XCTAssertEqual(summary.deleteCount, 1)
            XCTAssertEqual(summary.sortOrderUpdateCount, 1)
        }

        let reopened = AppStateTestSupport.makeIsolatedStore(fileURL: sharedFileURL, reset: false)
        XCTAssertNil(reopened.store.state.episodes.first { $0.id == deletedID })
        XCTAssertEqual(reopened.store.state.episodes.map(\.id), survivingIDs)
    }

    func testHasCompletedOnboardingPersistsAcrossStoreInstances() async throws {
        let sharedFileURL = AppStateTestSupport.uniqueTempFileURL()
        defer { AppStateTestSupport.disposeIsolatedStore(at: sharedFileURL) }

        do {
            let made = AppStateTestSupport.makeIsolatedStore(fileURL: sharedFileURL)
            var settings = made.store.state.settings
            settings.hasCompletedOnboarding = true
            made.store.updateSettings(settings)
        }

        let reopened = AppStateTestSupport.makeIsolatedStore(fileURL: sharedFileURL, reset: false)
        XCTAssertTrue(reopened.store.state.settings.hasCompletedOnboarding)
    }

    func testCorruptEpisodeSidecarDoesNotDiscardMetadata() async throws {
        let sharedFileURL = AppStateTestSupport.uniqueTempFileURL()
        defer { AppStateTestSupport.disposeIsolatedStore(at: sharedFileURL) }

        do {
            let made = AppStateTestSupport.makeIsolatedStore(fileURL: sharedFileURL)
            let sub = makeSubscription(title: "Metadata Survives")
            XCTAssertTrue(made.store.addSubscription(sub))
            var settings = made.store.state.settings
            settings.hasCompletedOnboarding = true
            made.store.updateSettings(settings)
        }

        let episodeStoreURL = Persistence.episodeStoreURL(for: sharedFileURL)
        try Data("not sqlite".utf8).write(to: episodeStoreURL, options: [.atomic])

        let reopened = AppStateTestSupport.makeIsolatedStore(fileURL: sharedFileURL, reset: false)
        XCTAssertTrue(reopened.store.state.settings.hasCompletedOnboarding)
        XCTAssertEqual(reopened.store.state.subscriptions.map(\.title), ["Metadata Survives"])
    }

    private func makeSubscription(
        feedURL: URL = URL(string: "https://example.com/\(UUID().uuidString).xml")!,
        title: String = "Test Show"
    ) -> PodcastSubscription {
        PodcastSubscription(feedURL: feedURL, title: title)
    }

    private func makeEpisode(subscriptionID: UUID, guid: String) -> Episode {
        Episode(
            subscriptionID: subscriptionID,
            guid: guid,
            title: "Episode \(guid)",
            pubDate: Date(),
            enclosureURL: URL(string: "https://example.com/\(guid).mp3")!
        )
    }
}
