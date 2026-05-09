import Foundation
import os.log

// MARK: - ElevenLabsScribeClient

/// Thin REST client for ElevenLabs Scribe v1/v2 batch transcription.
///
/// API per [ElevenLabs Speech-to-Text reference]:
///   POST https://api.elevenlabs.io/v1/speech-to-text
///   multipart/form-data with model_id=scribe_v2, file=<bytes>, diarize=true,
///   timestamps_granularity=word, language_code=<bcp47?>
///   Header: xi-api-key: <key>
///
/// The current production rollout is webhook-only for jobs longer than a few
/// minutes — there is no documented polling endpoint. To keep the surface
/// stable for downstream lanes we still expose a `submit` → `pollResult`
/// shape. `pollResult` runs `Task.sleep` exponential backoff and rechecks
/// `GET /v1/speech-to-text/{job_id}`; if the host returns 404 (no job
/// endpoint) it falls back to throwing `.webhookOnlyMode`.
actor ElevenLabsScribeClient {

    enum ScribeError: Swift.Error, Sendable {
        case missingAPIKey
        case invalidResponse
        case http(status: Int, body: String?)
        case decoding(String)
        case webhookOnlyMode
        case timedOut
    }

    private static let logger = Logger.app("ElevenLabsScribeClient")
    private let baseURL: URL
    private let session: URLSession
    private let modelID: String
    private let credential: @Sendable () throws -> String?

    init(
        baseURL: URL = URL(string: "https://api.elevenlabs.io")!,
        modelID: String = "scribe_v2",
        session: URLSession = .shared,
        credential: @escaping @Sendable () throws -> String? = { try ElevenLabsCredentialStore.apiKey() }
    ) {
        self.baseURL = baseURL
        self.modelID = modelID
        self.session = session
        self.credential = credential
    }

    // MARK: API

    /// Submits an audio file at `audioURL` for transcription. Returns a
    /// `ScribeJob` that can be passed to `pollResult` (or matched against an
    /// incoming webhook callback later when we wire that path).
    ///
    /// `episodeID` is carried on the returned `ScribeJob` so `pollResult`
    /// can synthesize the resulting `Transcript` without a second parameter.
    func submit(
        audioURL: URL,
        episodeID: UUID,
        languageHint: String? = nil
    ) async throws -> ScribeJob {
        guard let key = try credential(), !key.isEmpty else { throw ScribeError.missingAPIKey }

        let endpoint = baseURL.appendingPathComponent("v1/speech-to-text")
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = try Self.multipartBody(
            boundary: boundary,
            modelID: modelID,
            languageHint: languageHint,
            audioURL: audioURL
        )

        let (data, response) = try await session.upload(for: request, from: body)
        try Self.assertOK(response: response, data: data)

        // Two response shapes are accepted by the API:
        //   1. Sync: { "language_code": "...", "words": [...] }     (short clips)
        //   2. Async: { "request_id": "...", "status": "queued" }   (webhook path)
        if let job = try? JSONDecoder().decode(AsyncJobResponse.self, from: data) {
            return ScribeJob(
                requestID: job.request_id,
                episodeID: episodeID,
                createdAt: Date(),
                languageHint: languageHint,
                inlineResult: nil
            )
        }
        if let inline = try? JSONDecoder().decode(ScribeRawResult.self, from: data) {
            return ScribeJob(
                requestID: UUID().uuidString,
                episodeID: episodeID,
                createdAt: Date(),
                languageHint: languageHint,
                inlineResult: inline
            )
        }
        throw ScribeError.decoding("Unrecognised /speech-to-text response shape")
    }

    /// Polls until the job is `completed`, returning a `Transcript`. If the
    /// submission was synchronous (small clip), we return immediately from
    /// the cached inline result.
    ///
    /// Backoff schedule: 2s, 4s, 8s, 16s, capped at 30s; total ceiling 10 min.
    func pollResult(_ job: ScribeJob) async throws -> Transcript {
        if let inline = job.inlineResult {
            return Transcript.fromScribeRaw(inline, episodeID: job.episodeID, languageHint: job.languageHint)
        }
        guard let key = try credential(), !key.isEmpty else { throw ScribeError.missingAPIKey }

        let deadline = Date().addingTimeInterval(10 * 60)
        var delay: UInt64 = 2_000_000_000 // 2s in nanoseconds

        while Date() < deadline {
            try await Task.sleep(nanoseconds: delay)
            delay = min(delay * 2, 30_000_000_000)

            let url = baseURL
                .appendingPathComponent("v1/speech-to-text")
                .appendingPathComponent(job.requestID)
            var request = URLRequest(url: url)
            request.setValue(key, forHTTPHeaderField: "xi-api-key")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ScribeError.invalidResponse }

            if http.statusCode == 404 {
                throw ScribeError.webhookOnlyMode
            }
            if http.statusCode == 202 {
                continue // still processing
            }
            try Self.assertOK(response: response, data: data)

            if let raw = try? JSONDecoder().decode(ScribeRawResult.self, from: data) {
                return Transcript.fromScribeRaw(raw, episodeID: job.episodeID, languageHint: job.languageHint)
            }
            // Some shapes nest under "result".
            if let envelope = try? JSONDecoder().decode(ScribeEnvelope.self, from: data),
               envelope.status.lowercased() == "completed",
               let raw = envelope.result {
                return Transcript.fromScribeRaw(raw, episodeID: job.episodeID, languageHint: job.languageHint)
            }
        }
        throw ScribeError.timedOut
    }

    // MARK: Multipart

    static func multipartBody(
        boundary: String,
        modelID: String,
        languageHint: String?,
        audioURL: URL
    ) throws -> Data {
        var body = Data()
        let crlf = "\r\n"

        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)".data(using: .utf8)!)
            body.append("\(value)\(crlf)".data(using: .utf8)!)
        }

        appendField("model_id", modelID)
        appendField("diarize", "true")
        appendField("timestamps_granularity", "word")
        appendField("tag_audio_events", "true")
        if let hint = languageHint, !hint.isEmpty {
            appendField("language_code", hint)
        }

        let filename = audioURL.lastPathComponent
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(try Data(contentsOf: audioURL))
        body.append(crlf.data(using: .utf8)!)
        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)
        return body
    }

    // MARK: HTTP

    static func assertOK(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ScribeError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ScribeError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
    }
}

// MARK: - DTOs

struct ScribeJob: Sendable, Hashable {
    let requestID: String
    let episodeID: UUID
    let createdAt: Date
    let languageHint: String?
    let inlineResult: ScribeRawResult?
}

struct ScribeRawResult: Codable, Sendable, Hashable {
    let language_code: String?
    let text: String?
    let words: [ScribeWord]?
}

struct ScribeWord: Codable, Sendable, Hashable {
    let text: String
    let start: Double
    let end: Double
    let type: String?           // "word" | "spacing" | "audio_event"
    let speaker_id: String?
}

struct AsyncJobResponse: Codable, Sendable {
    let request_id: String
    let status: String?
}

struct ScribeEnvelope: Codable, Sendable {
    let status: String
    let result: ScribeRawResult?
}

// MARK: - Transcript adapter

extension Transcript {
    /// Converts a Scribe raw result into our internal `Transcript`. Words of
    /// type `spacing` are dropped. Words of type `audio_event` (`[laughter]`,
    /// `[music]`) are folded into the body text in-place — the wiki / agent
    /// surfaces will use them for context, the reader will hide them.
    static func fromScribeRaw(
        _ raw: ScribeRawResult,
        episodeID: UUID,
        languageHint: String?
    ) -> Transcript {
        let language = raw.language_code ?? languageHint ?? "en-US"
        let words = raw.words ?? []

        // Group words into segments by speaker switch and ≥1.2s pause boundary.
        var speakers: [String: Speaker] = [:]
        var segments: [Segment] = []
        var bufferText = ""
        var bufferWords: [Word] = []
        var bufferStart: Double = 0
        var bufferEnd: Double = 0
        var bufferSpeaker: String?

        @inline(__always) func flush() {
            guard !bufferWords.isEmpty else { return }
            let speakerID: UUID?
            if let label = bufferSpeaker {
                if let existing = speakers[label] {
                    speakerID = existing.id
                } else {
                    let new = Speaker(label: label, displayName: nil)
                    speakers[label] = new
                    speakerID = new.id
                }
            } else { speakerID = nil }
            segments.append(
                Segment(
                    start: bufferStart,
                    end: bufferEnd,
                    speakerID: speakerID,
                    text: bufferText.trimmingCharacters(in: .whitespacesAndNewlines),
                    words: bufferWords
                )
            )
            bufferText = ""
            bufferWords = []
        }

        for w in words where w.type != "spacing" {
            let speakerSwitch = bufferSpeaker != nil && w.speaker_id != bufferSpeaker
            let pauseBoundary = !bufferWords.isEmpty && (w.start - bufferEnd) > 1.2
            if speakerSwitch || pauseBoundary {
                flush()
            }
            if bufferWords.isEmpty {
                bufferStart = w.start
                bufferSpeaker = w.speaker_id
            }
            bufferEnd = w.end
            if !bufferText.isEmpty { bufferText.append(" ") }
            bufferText.append(w.text)
            bufferWords.append(Word(start: w.start, end: w.end, text: w.text))
        }
        flush()

        return Transcript(
            episodeID: episodeID,
            language: language,
            source: .scribeV1,
            segments: segments,
            speakers: Array(speakers.values),
            generatedAt: Date()
        )
    }
}
