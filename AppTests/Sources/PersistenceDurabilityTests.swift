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
