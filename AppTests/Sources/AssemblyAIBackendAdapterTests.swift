import XCTest
@testable import Podcastr

final class AssemblyAIBackendAdapterTests: XCTestCase {

    func testDecodesRustAssemblyAIResultAndBuildsTranscript() throws {
        let data = """
        {
          "id": "tx_1",
          "status": "completed",
          "audio_duration": 1.0,
          "language_code": "en",
          "text": "Hello",
          "utterances": [
            {
              "start": 0,
              "end": 1000,
              "text": "Hello",
              "speaker": "A",
              "words": [{"text":"Hello","start":0,"end":1000,"speaker":"A"}]
            }
          ],
          "usage": {"cost": 0.01, "seconds": 1.0, "input_tokens": 2, "output_tokens": 3},
          "model": "universal-3-pro,universal-2",
          "latency_ms": 42
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(AssemblyAITranscriptPayload.self, from: data)
        XCTAssertEqual(payload.model, "universal-3-pro,universal-2")
        XCTAssertEqual(payload.latencyMs, 42)
        XCTAssertEqual(payload.usage?.input_tokens, 2)

        let episodeID = UUID()
        let transcript = Transcript.fromAssemblyAI(payload, episodeID: episodeID, languageHint: nil)

        XCTAssertEqual(transcript.episodeID, episodeID)
        XCTAssertEqual(transcript.language, "en")
        XCTAssertEqual(transcript.source, .assemblyAI)
        XCTAssertEqual(transcript.segments.count, 1)
        XCTAssertEqual(transcript.segments.first?.text, "Hello")
        XCTAssertEqual(transcript.speakers.count, 1)
    }

    func testFallbackWordsSplitOnPauseBoundary() {
        let payload = AssemblyAITranscriptPayload(
            id: "tx_1",
            status: "completed",
            audio_url: nil,
            audio_duration: nil,
            language_code: nil,
            text: "ignored",
            error: nil,
            words: [
                AssemblyAIWord(start: 0, end: 200, text: "One", confidence: nil, speaker: nil),
                AssemblyAIWord(start: 2500, end: 2700, text: "Two", confidence: nil, speaker: nil),
            ],
            utterances: nil,
            usage: nil,
            model: "universal-2",
            latencyMs: 10
        )

        let transcript = Transcript.fromAssemblyAI(payload, episodeID: UUID(), languageHint: "es")

        XCTAssertEqual(transcript.language, "es")
        XCTAssertEqual(transcript.segments.map(\.text), ["One", "Two"])
        XCTAssertEqual(transcript.segments.flatMap { $0.words ?? [] }.map(\.text), ["One", "Two"])
    }

    func testBackendErrorKindsMapToUserFacingErrorCases() {
        XCTAssertMissingAPIKey(
            AssemblyAITranscriptClient.transcribeError(from: .init(kind: "missing_api_key", message: nil, statusCode: nil))
        )
        XCTAssertInvalidAudioURL(
            AssemblyAITranscriptClient.transcribeError(from: .init(kind: "invalid_audio_url", message: nil, statusCode: nil))
        )
        XCTAssertTimedOut(
            AssemblyAITranscriptClient.transcribeError(from: .init(kind: "timed_out", message: nil, statusCode: nil))
        )
        XCTAssertRemoteError(
            AssemblyAITranscriptClient.transcribeError(from: .init(kind: "remote_error", message: "bad audio", statusCode: nil))
        )
    }

    func testBackendHTTPKindsPreserveStatusCode() {
        let invalid = AssemblyAITranscriptClient.transcribeError(
            from: .init(kind: "invalid_key", message: "bad key", statusCode: 401)
        )
        guard case .http(let invalidStatus, let invalidBody) = invalid else {
            return XCTFail("Expected HTTP error, got \(invalid)")
        }
        XCTAssertEqual(invalidStatus, 401)
        XCTAssertEqual(invalidBody, "bad key")

        let limited = AssemblyAITranscriptClient.transcribeError(
            from: .init(kind: "rate_limited", message: "slow down", statusCode: 429)
        )
        guard case .http(let limitedStatus, _) = limited else {
            return XCTFail("Expected HTTP error, got \(limited)")
        }
        XCTAssertEqual(limitedStatus, 429)
    }

    private func XCTAssertMissingAPIKey(
        _ error: AssemblyAITranscriptClient.TranscribeError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .missingAPIKey = error else {
            return XCTFail("Expected missingAPIKey, got \(error)", file: file, line: line)
        }
    }

    private func XCTAssertInvalidAudioURL(
        _ error: AssemblyAITranscriptClient.TranscribeError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .invalidAudioURL = error else {
            return XCTFail("Expected invalidAudioURL, got \(error)", file: file, line: line)
        }
    }

    private func XCTAssertTimedOut(
        _ error: AssemblyAITranscriptClient.TranscribeError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .timedOut = error else {
            return XCTFail("Expected timedOut, got \(error)", file: file, line: line)
        }
    }

    private func XCTAssertRemoteError(
        _ error: AssemblyAITranscriptClient.TranscribeError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .remoteError = error else {
            return XCTFail("Expected remoteError, got \(error)", file: file, line: line)
        }
    }
}
