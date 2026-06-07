import Foundation

struct AssemblyAITranscriptIntent: Encodable {
    let audioURL: String
    let languageHint: String?

    enum CodingKeys: String, CodingKey {
        case audioURL = "audio_url"
        case languageHint = "language_hint"
    }
}

struct AssemblyAITranscriptEnvelope: Decodable {
    var result: AssemblyAITranscriptPayload?
    var error: AssemblyAITranscriptBackendError?
}

struct AssemblyAITranscriptBackendError: Decodable {
    var kind: String
    var message: String?
    var statusCode: Int?

    enum CodingKeys: String, CodingKey {
        case kind, message
        case statusCode = "status_code"
    }
}

struct AssemblyAIJob: Sendable, Hashable {
    let transcriptID: String
    let episodeID: UUID
    let createdAt: Date
    let languageHint: String?
    let speechModels: [String]
    let inlineResult: AssemblyAITranscriptPayload?
}

struct AssemblyAITranscriptPayload: Codable, Sendable, Hashable {
    let id: String?
    let status: String?
    let audio_url: String?
    let audio_duration: Double?
    let language_code: String?
    let text: String?
    let error: String?
    let words: [AssemblyAIWord]?
    let utterances: [AssemblyAIUtterance]?
    let usage: AssemblyAIUsage?
    let model: String?
    let latencyMs: Int?

    enum CodingKeys: String, CodingKey {
        case id, status, audio_url, audio_duration, language_code, text, error
        case words, utterances, usage, model
        case latencyMs = "latency_ms"
    }
}

struct AssemblyAIUsage: Codable, Sendable, Hashable {
    let cost: Double?
    let seconds: Double?
    let input_tokens: Int?
    let output_tokens: Int?
    let total_tokens: Int?
}

struct AssemblyAIUtterance: Codable, Sendable, Hashable {
    let start: Int
    let end: Int
    let text: String
    let confidence: Double?
    let speaker: String?
    let words: [AssemblyAIWord]?
}

struct AssemblyAIWord: Codable, Sendable, Hashable {
    let start: Int
    let end: Int
    let text: String
    let confidence: Double?
    let speaker: String?
}
