import XCTest
@testable import Podcastr

extension AppTests {

    // MARK: - Settings

    func testSettingsDoesNotPersistLegacyOpenRouterAPIKey() throws {
        let json = """
        {
          "llmModel": "openai/gpt-4o-mini",
          "openRouterAPIKey": "sk-or-v1-secret",
          "agentMaxTurns": 12
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Settings.self, from: json)
        XCTAssertEqual(decoded.openRouterCredentialSource, .manual)
        XCTAssertEqual(decoded.legacyOpenRouterAPIKey, "sk-or-v1-secret")

        let encoded = try JSONEncoder().encode(decoded)
        let encodedString = String(data: encoded, encoding: .utf8) ?? ""
        XCTAssertFalse(encodedString.contains("sk-or-v1-secret"))
        XCTAssertFalse(encodedString.contains("openRouterAPIKey"))
    }

    func testSettingsPersistsBYOKMetadataOnly() throws {
        var settings = Settings()
        settings.markOpenRouterBYOK(keyID: "key_123", keyLabel: "Default")

        let encoded = try JSONEncoder().encode(settings)
        let encodedString = String(data: encoded, encoding: .utf8) ?? ""

        XCTAssertTrue(encodedString.contains("byok"))
        XCTAssertTrue(encodedString.contains("key_123"))
        XCTAssertTrue(encodedString.contains("Default"))
        XCTAssertFalse(encodedString.contains("api_key"))
    }
}
