import XCTest
@testable import Podcastr

/// Guards the kernel → Swift decode of the kernel-owned STT fallback policy
/// projection. The STT provider fallback policy lives in the Rust kernel; the
/// resolved value rides the snapshot as `effective_stt_provider`. This is the
/// FIRST consumer of a *computed* kernel-mirror string field, so the
/// `.convertFromSnakeCase` decode path (used by `KernelBridge`) must be proven
/// — a key mismatch would silently default `effectiveSttProvider` to
/// `"apple_native"` and turn the whole feature into a no-op that still builds
/// and passes every other test.
///
/// Note: the sibling `sttProvider` kernel-mirror CodingKey carries an explicit
/// snake_case raw value that is `.convertFromSnakeCase`-incompatible, so it does
/// NOT decode from the kernel snapshot — but it is unused (callers read the
/// Swift-side `Settings` struct, not this projection), so it is out of scope
/// here and deliberately not asserted on.
final class EffectiveSTTProviderDecodeTests: XCTestCase {

    /// Decode `SettingsSnapshot` exactly the way `KernelBridge` does.
    private func decode(_ json: String) throws -> SettingsSnapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SettingsSnapshot.self, from: Data(json.utf8))
    }

    func testEffectiveSttProviderDecodesFromSnakeCaseKey() throws {
        let json = """
        {"stt_provider":"elevenlabs_scribe","effective_stt_provider":"elevenlabs_scribe","effective_stt_provider_requires_key":true}
        """
        let settings = try decode(json)
        XCTAssertEqual(
            settings.effectiveSttProvider, "elevenlabs_scribe",
            "effective_stt_provider must decode through .convertFromSnakeCase — if this is apple_native the CodingKey did not match the converted key"
        )
        XCTAssertTrue(settings.effectiveSttProviderRequiresKey)
    }

    func testEffectiveSttProviderFallbackValueDecodes() throws {
        // Kernel resolved a keyless cloud selection down to apple_native.
        let json = """
        {"stt_provider":"assemblyai","effective_stt_provider":"apple_native","effective_stt_provider_requires_key":false}
        """
        let settings = try decode(json)
        XCTAssertEqual(settings.effectiveSttProvider, "apple_native")
        XCTAssertFalse(settings.effectiveSttProviderRequiresKey)
    }

    func testMissingFieldDefaultsToAppleNative() throws {
        // Older kernel snapshots without the field must default safely.
        let settings = try decode("{\"stt_provider\":\"openrouter_whisper\"}")
        XCTAssertEqual(settings.effectiveSttProvider, "apple_native")
        XCTAssertFalse(settings.effectiveSttProviderRequiresKey)
    }

    func testCredentialMetadataDecodesFromSnakeCaseKeys() throws {
        let json = """
        {
          "open_router_byok_key_id":"openrouter_key",
          "open_router_byok_key_label":"OpenRouter",
          "assembly_ai_credential_source":"byok",
          "assembly_ai_key_present":true,
          "assembly_ai_byok_key_id":"assembly_key",
          "assembly_ai_byok_key_label":"AssemblyAI",
          "assembly_ai_connected_at":1700000000,
          "perplexity_credential_source":"manual",
          "perplexity_key_present":true,
          "perplexity_byok_key_id":"perplexity_key",
          "perplexity_byok_key_label":"Perplexity",
          "perplexity_connected_at":1700000100
        }
        """

        let settings = try decode(json)

        XCTAssertEqual(settings.openRouterBYOKKeyID, "openrouter_key")
        XCTAssertEqual(settings.openRouterBYOKKeyLabel, "OpenRouter")
        XCTAssertEqual(settings.assemblyAICredentialSource, "byok")
        XCTAssertTrue(settings.assemblyAIKeyPresent)
        XCTAssertEqual(settings.assemblyAIBYOKKeyID, "assembly_key")
        XCTAssertEqual(settings.assemblyAIBYOKKeyLabel, "AssemblyAI")
        XCTAssertEqual(settings.assemblyAIConnectedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(settings.perplexityCredentialSource, "manual")
        XCTAssertTrue(settings.perplexityKeyPresent)
        XCTAssertEqual(settings.perplexityBYOKKeyID, "perplexity_key")
        XCTAssertEqual(settings.perplexityBYOKKeyLabel, "Perplexity")
        XCTAssertEqual(settings.perplexityConnectedAt, Date(timeIntervalSince1970: 1_700_000_100))
    }
}
