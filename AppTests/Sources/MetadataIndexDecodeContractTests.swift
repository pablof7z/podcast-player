import XCTest
@testable import Podcastr

/// Cross-language wire-contract guard for the D7 metadata-index backfill fields
/// (`pendingMetadataIndexIds` + `metadataIndexInterBatchDelayMs`) embedded in
/// `PodcastUpdate`.
///
/// WHY THIS EXISTS (MEMORY ffi_decode_snakecase_contract): the Rust kernel emits
/// these as snake_case (`pending_metadata_index_ids`,
/// `metadata_index_inter_batch_delay_ms`). The bridge decoder is configured with
/// `keyDecodingStrategy = .convertFromSnakeCase`, which maps those to the
/// camelCase Swift property names. If the generated Swift struct ever grew an
/// explicit snake_case `CodingKeys` for these fields, the strategy would
/// double-convert and throw `keyNotFound` — dropping the ENTIRE PodcastUpdate
/// frame and freezing the UI (the #371-class failure).
///
/// This test decodes a Rust-shaped snake_case frame through the EXACT bridge
/// seam (`KernelDecoding.decodePodcastUpdate`) and asserts the values land. The
/// Rust counterpart (`snapshot_decode_tests::metadata_index_keys_convert_to_swift_property_names`)
/// asserts the wire shape + key conversion from the producing side.
final class MetadataIndexDecodeContractTests: XCTestCase {

    /// A Rust-emitted `PodcastUpdate` frame carrying both backfill fields in
    /// snake_case (the exact shape `build_podcast_update` serializes).
    private let frameWithBackfill = """
    {
      "running": true,
      "rev": 7,
      "schema_version": 1,
      "pending_metadata_index_ids": [
        "16368e87-66b8-5631-9f89-5059212a4e9b",
        "00000000-0000-0000-0000-000000000001"
      ],
      "metadata_index_inter_batch_delay_ms": 200
    }
    """

    /// A legacy frame predating the fields — must decode cleanly to defaults.
    private let frameWithoutBackfill = """
    {"running": true, "rev": 1, "schema_version": 1}
    """

    // MARK: - Decode through the bridge seam

    func testBackfillFieldsDecodeThroughBridgeSeam() throws {
        let data = Data(frameWithBackfill.utf8)
        let update = try KernelDecoding.decodePodcastUpdate(from: data)

        XCTAssertEqual(
            update.pendingMetadataIndexIds,
            [
                "16368e87-66b8-5631-9f89-5059212a4e9b",
                "00000000-0000-0000-0000-000000000001",
            ],
            "pending_metadata_index_ids must map to pendingMetadataIndexIds via .convertFromSnakeCase"
        )
        XCTAssertEqual(
            update.metadataIndexInterBatchDelayMs, 200,
            "metadata_index_inter_batch_delay_ms must map to metadataIndexInterBatchDelayMs"
        )
    }

    func testLegacyFrameDecodesToDefaults() throws {
        let data = Data(frameWithoutBackfill.utf8)
        let update = try KernelDecoding.decodePodcastUpdate(from: data)

        XCTAssertTrue(
            update.pendingMetadataIndexIds.isEmpty,
            "a frame predating the field must default to an empty array, not throw"
        )
        XCTAssertEqual(
            update.metadataIndexInterBatchDelayMs, 0,
            "a frame predating the field must default the delay to 0"
        )
    }

    // MARK: - Plain-decoder failure contract

    /// Pin the failure mode: a plain (non-.convertFromSnakeCase) decoder must
    /// drop the snake_case keys — proving the bridge config is load-bearing.
    /// (A plain decoder won't *throw* here because both fields default, but it
    /// will silently miss them, which is exactly why the bridge strategy matters.)
    func testPlainDecoderMissesSnakeCaseKeys() throws {
        let data = Data(frameWithBackfill.utf8)
        let update = try JSONDecoder().decode(PodcastUpdate.self, from: data)
        XCTAssertTrue(
            update.pendingMetadataIndexIds.isEmpty,
            "a plain decoder must NOT pick up snake_case keys — confirms .convertFromSnakeCase is required"
        )
        XCTAssertEqual(update.metadataIndexInterBatchDelayMs, 0)
    }
}
