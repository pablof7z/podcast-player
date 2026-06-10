import XCTest
@testable import Podcastr

/// Cross-language parity guard for the settings-default single-source refactor.
///
/// The Rust kernel owns the canonical fresh-install defaults in
/// `PodcastStore::new()`; the Swift `SettingsSnapshot()` property initializers
/// are the one permitted Swift mirror. The Rust test
/// `settings_fresh_install_matches_fixture` serializes
/// `SettingsSnapshot::default()` to `tests/fixtures/settings_fresh_install.json`;
/// this test decodes the **same** fixture into the Swift `SettingsSnapshot` and
/// asserts it equals `SettingsSnapshot()`. If the two default sets drift, one of
/// these two tests fails — keeping the mirrors honest without a code generator.
final class SettingsSnapshotParityTests: XCTestCase {
    private func loadFixture() throws -> Data {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: "settings_fresh_install", withExtension: "json") else {
            XCTFail("settings_fresh_install.json missing from test bundle — check Project.swift resources")
            return Data()
        }
        return try Data(contentsOf: url)
    }

    /// The kernel-generated fixture must decode into the Swift default mirror.
    func testFixtureDecodesToSwiftDefault() throws {
        let data = try loadFixture()
        let decoded = try JSONDecoder().decode(SettingsSnapshot.self, from: data)
        XCTAssertEqual(
            decoded,
            SettingsSnapshot(),
            """
            Swift SettingsSnapshot() drifted from the kernel fresh-install fixture.
            The canonical defaults live in Rust PodcastStore::new(); update the Swift
            SettingsSnapshot property initializers (PodcastSettingsSnapshot.generated.swift)
            to match, then regenerate the fixture with:
              cargo test -p nmp-app-podcast regenerate_settings_fresh_install_fixture -- --ignored --nocapture
            """
        )
    }

    /// An empty JSON object must hydrate to the full default — proves the
    /// container-level decode + property-initializer fallback works with no keys.
    func testEmptyObjectDecodesToSwiftDefault() throws {
        let data = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(SettingsSnapshot.self, from: data)
        XCTAssertEqual(decoded, SettingsSnapshot())
    }
}
