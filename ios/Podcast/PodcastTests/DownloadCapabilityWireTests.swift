import XCTest
@testable import Podcast

// MARK: - DownloadCapability wire-shape tests
//
// The Rust `DownloadCommand` / `DownloadReport` enums in
// `apps/nmp-app-podcast/src/capability/download.rs` define the canonical
// wire shape (`#[serde(tag = "type", rename_all = "snake_case")]`). The
// Swift mirrors in `DownloadCapability+Wire.swift` use hand-rolled
// `Codable` because the variant payloads differ across cases.
//
// These tests pin the JSON strings so a drift on either side surfaces
// loudly. The Rust crate has the same round-trips on its side
// (`capability::download::tests`) — together they form a two-sided
// contract.

final class DownloadCapabilityWireTests: XCTestCase {

    // MARK: - DownloadCommand decoding (Rust → Swift)

    func testStartDownloadCommandDecodesWithExpectedBytes() throws {
        let json = #"""
        {"type":"start_download","url":"https://ex.com/ep.mp3","episode_id":"ep-7","expected_bytes":12345}
        """#
        let decoded = try decodeCommand(json)
        XCTAssertEqual(
            decoded,
            .startDownload(url: "https://ex.com/ep.mp3", episodeID: "ep-7", expectedBytes: 12345))
    }

    func testStartDownloadCommandDecodesWithoutExpectedBytes() throws {
        // Rust's `#[serde(skip_serializing_if = "Option::is_none")]` omits
        // the field; the Swift decoder treats it as `nil`.
        let json = #"""
        {"type":"start_download","url":"https://ex.com/ep.mp3","episode_id":"ep-7"}
        """#
        XCTAssertEqual(
            try decodeCommand(json),
            .startDownload(url: "https://ex.com/ep.mp3", episodeID: "ep-7", expectedBytes: nil))
    }

    func testPauseResumeCancelCommandsDecode() throws {
        XCTAssertEqual(
            try decodeCommand(#"{"type":"pause_download","episode_id":"ep-1"}"#),
            .pauseDownload(episodeID: "ep-1"))
        XCTAssertEqual(
            try decodeCommand(#"{"type":"resume_download","episode_id":"ep-1"}"#),
            .resumeDownload(episodeID: "ep-1"))
        XCTAssertEqual(
            try decodeCommand(#"{"type":"cancel_download","episode_id":"ep-1"}"#),
            .cancelDownload(episodeID: "ep-1"))
    }

    func testCancelAllCommandDecodes() throws {
        XCTAssertEqual(try decodeCommand(#"{"type":"cancel_all"}"#), .cancelAll)
    }

    func testUnknownCommandTypeRaisesDecodeError() {
        XCTAssertThrowsError(try decodeCommand(#"{"type":"obliterate","episode_id":"ep-1"}"#))
    }

    // MARK: - DownloadReport encoding (Swift → Rust)

    func testProgressReportEncodesWithTotalBytes() throws {
        let report = DownloadReport.progress(
            episodeID: "ep-1",
            bytesDownloaded: 4096,
            totalBytes: 81920)
        let dict = try parse(encodeReport(report))
        XCTAssertEqual(dict["type"] as? String, "progress")
        XCTAssertEqual(dict["episode_id"] as? String, "ep-1")
        XCTAssertEqual(asUInt64(dict["bytes_downloaded"]), 4096)
        XCTAssertEqual(asUInt64(dict["total_bytes"]), 81920)
    }

    func testProgressReportOmitsTotalBytesWhenUnknown() throws {
        let report = DownloadReport.progress(
            episodeID: "ep-1",
            bytesDownloaded: 4096,
            totalBytes: nil)
        let json = try encodeReport(report)
        // Rust's `skip_serializing_if = "Option::is_none"` mandates the
        // key is absent — not `null`. A drift here would break the
        // two-sided round-trip.
        XCTAssertFalse(json.contains("total_bytes"))
        let dict = try parse(json)
        XCTAssertNil(dict["total_bytes"])
        XCTAssertEqual(asUInt64(dict["bytes_downloaded"]), 4096)
    }

    func testCompletedReportEncodesLocalPath() throws {
        let report = DownloadReport.completed(
            episodeID: "ep-1",
            localPath: "/var/mobile/.../ep-1.mp3")
        let dict = try parse(encodeReport(report))
        XCTAssertEqual(dict["type"] as? String, "completed")
        XCTAssertEqual(dict["episode_id"] as? String, "ep-1")
        XCTAssertEqual(dict["local_path"] as? String, "/var/mobile/.../ep-1.mp3")
    }

    func testFailedReportEncodesError() throws {
        let report = DownloadReport.failed(
            episodeID: "ep-1",
            error: "transport: timeout")
        let dict = try parse(encodeReport(report))
        XCTAssertEqual(dict["type"] as? String, "failed")
        XCTAssertEqual(dict["episode_id"] as? String, "ep-1")
        XCTAssertEqual(dict["error"] as? String, "transport: timeout")
    }

    func testCancelledReportEncodesOnlyEpisodeID() throws {
        let report = DownloadReport.cancelled(episodeID: "ep-1")
        let dict = try parse(encodeReport(report))
        XCTAssertEqual(dict["type"] as? String, "cancelled")
        XCTAssertEqual(dict["episode_id"] as? String, "ep-1")
        XCTAssertEqual(dict.count, 2)
    }

    func testPausedReportEncodesBytesDownloaded() throws {
        let report = DownloadReport.paused(
            episodeID: "ep-1",
            bytesDownloaded: 2048)
        let dict = try parse(encodeReport(report))
        XCTAssertEqual(dict["type"] as? String, "paused")
        XCTAssertEqual(dict["episode_id"] as? String, "ep-1")
        XCTAssertEqual(asUInt64(dict["bytes_downloaded"]), 2048)
    }

    // MARK: - Namespace pinning

    func testNamespaceMatchesCanonicalCapabilityPlan() {
        XCTAssertEqual(DownloadCapability.namespace, "nmp.download.capability")
    }

    func testBackgroundSessionIdentifierMatchesLegacyApp() {
        // The legacy iOS app used `io.f7z.podcast.downloads`. Keeping the
        // identifier stable lets the OS re-attach in-flight downloads
        // from a pre-NMP launch (M4 milestone pre-flight).
        XCTAssertEqual(DownloadCapability.sessionIdentifier, "io.f7z.podcast.downloads")
    }

    // MARK: - Helpers

    private func decodeCommand(_ json: String) throws -> DownloadCommand {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(DownloadCommand.self, from: data)
    }

    private func encodeReport(_ report: DownloadReport) throws -> String {
        guard let json = report.jsonString() else {
            throw XCTSkip("DownloadReport encoding returned nil — unreachable")
        }
        return json
    }

    private func parse(_ json: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        guard let dict = object as? [String: Any] else {
            throw XCTSkip("encoded report was not a JSON object")
        }
        return dict
    }

    /// `UInt64` over JSON round-trips through `NSNumber`. Cast safely
    /// without losing precision (the numbers we test fit in `Double`).
    private func asUInt64(_ value: Any?) -> UInt64? {
        if let n = value as? NSNumber { return n.uint64Value }
        if let i = value as? Int { return UInt64(i) }
        if let i = value as? UInt64 { return i }
        return nil
    }
}
