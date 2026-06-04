import XCTest
@testable import Podcastr

/// Pins the task→model resolution used by every download delegate callback.
///
/// Regression guard for the bug where finished Gemma downloads hung at 100%
/// and vanished on relaunch: the old code matched by comparing the on-disk
/// filename basename (`gemma4-e2b`) to the remote URL basename
/// (`gemma-4-E2B-it`), which can never be equal, so the finished file was
/// never moved into place.
final class LocalModelCatalogMatchTests: XCTestCase {

    func testEveryCatalogModelResolvesFromItsOwnDownloadURL() {
        for spec in LocalModelCatalog.all {
            XCTAssertEqual(
                LocalModelCatalog.modelID(forDownloadURL: spec.downloadURL),
                spec.id,
                "Download URL for \(spec.id) must resolve back to its model id")
        }
    }

    func testUnknownURLResolvesToNil() {
        let unknown = URL(string: "https://example.com/not-a-model.litertlm")!
        XCTAssertNil(LocalModelCatalog.modelID(forDownloadURL: unknown))
    }

    /// The remote filename does NOT equal the model id — documents exactly why
    /// the old basename comparison was broken, so nobody reintroduces it.
    func testRemoteFilenameDoesNotEqualModelID() {
        for spec in LocalModelCatalog.all {
            let remoteBasename = spec.downloadURL.deletingPathExtension().lastPathComponent
            XCTAssertNotEqual(
                remoteBasename, spec.id,
                "Remote basename \(remoteBasename) unexpectedly equals model id — basename matching would have masked the bug")
        }
    }
}
