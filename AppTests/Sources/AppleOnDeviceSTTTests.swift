import Speech
import XCTest
@testable import Podcastr

/// Device-only integration probe for Apple on-device STT.
///
/// Exercises the exact production path in `AppleNativeSTTClient.transcribe` against
/// the bundled `test-episode.mp3` (~34 s, mono MP3) so any failure surfaces here
/// rather than requiring a full app launch + `os_log` capture.
///
/// Skips automatically on the simulator: `SpeechTranscriber.isAvailable` returns
/// `false` there and on-device speech models are not present.
final class AppleOnDeviceSTTTests: XCTestCase {

    func testTranscribesBundledTestEpisode() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("SpeechTranscriber needs a real device — run on iPhone")
        #endif

        guard SpeechTranscriber.isAvailable else {
            throw XCTSkip("SpeechTranscriber.isAvailable == false on this device (iOS 26+ required)")
        }

        guard let audioURL = Bundle.main.url(forResource: "test-episode", withExtension: "mp3") else {
            return XCTFail("STTTEST: test-episode.mp3 not found in app bundle — check Project.swift resources")
        }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int) ?? -1
        print("STTTEST: audio path=\(audioURL.path) sizeBytes=\(fileSize)")

        let episodeID = UUID()
        let client = AppleNativeSTTClient()

        // Model download may happen on the first run — budget extra time.
        print("STTTEST: calling transcribe (first run may download on-device speech model)…")
        let transcript: Transcript
        do {
            transcript = try await client.transcribe(audioFileURL: audioURL, episodeID: episodeID)
        } catch {
            return XCTFail(
                "STTTEST: transcription FAILED — \(error.localizedDescription) [\(type(of: error)): \(error)]"
            )
        }

        print(
            "STTTEST: ✓ segments=\(transcript.segments.count) " +
            "source=\(transcript.source) language=\(transcript.language)"
        )
        for (i, seg) in transcript.segments.prefix(5).enumerated() {
            print(
                "STTTEST: seg[\(i)] " +
                "[\(String(format: "%.2f", seg.start))–\(String(format: "%.2f", seg.end))s] " +
                "\"\(seg.text.prefix(100))\""
            )
        }

        XCTAssertFalse(transcript.segments.isEmpty,
                       "STTTEST: got 0 segments — SpeechAnalyzer returned results but none survived isFinal filter")
        XCTAssertEqual(transcript.source, .onDevice)
        XCTAssertEqual(transcript.episodeID, episodeID)
    }
}
