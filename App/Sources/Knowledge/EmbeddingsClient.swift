import Foundation
import os.log

// Lane 6 — RAG: OpenRouter embeddings client.
//
// Calls `POST https://openrouter.ai/api/v1/embeddings` (OpenAI-compatible
// schema) with model `openai/text-embedding-3-large` at 1024 dimensions
// (Matryoshka truncation — see `docs/spec/research/embeddings-rag-stack.md`).
// Authentication uses the existing `OpenRouterCredentialStore`.
//
// Batching: OpenAI's hard limit is 2048 inputs per request, but OpenRouter
// docs and downstream providers vary; we cap at 100 to stay well clear of
// payload-size and provider-specific limits, and to keep latency predictable.

/// Anything that can turn texts into vectors. The protocol stays minimal so
/// `VectorIndex` can be tested with a synthetic embedder if we ever wire up
/// integration tests, and so we can swap providers without touching the
/// vector store.
protocol EmbeddingsClient: Sendable {
    /// Embed `texts` in input order. The returned array has the same length
    /// as the input; each vector is `dimensions` floats long.
    func embed(_ texts: [String]) async throws -> [[Float]]
}

// MARK: - OpenRouter implementation

struct OpenRouterEmbeddingsClient: EmbeddingsClient {
    static let defaultModel = "openai/text-embedding-3-large"
    static let defaultDimensions = 1024
    static let maxBatchSize = 100

    private static let logger = Logger.app("OpenRouterEmbeddingsClient")
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/embeddings")!
    private static let xTitle = "Podcastr"

    private let apiKeyProvider: @Sendable () throws -> String?
    private let model: String
    private let dimensions: Int
    private let session: URLSession
    private let timeout: TimeInterval

    init(
        apiKeyProvider: @Sendable @escaping () throws -> String? = { try OpenRouterCredentialStore.apiKey() },
        model: String = OpenRouterEmbeddingsClient.defaultModel,
        dimensions: Int = OpenRouterEmbeddingsClient.defaultDimensions,
        session: URLSession = .shared,
        timeout: TimeInterval = 30
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.model = model
        self.dimensions = dimensions
        self.session = session
        self.timeout = timeout
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        guard let apiKey = try apiKeyProvider(), !apiKey.isEmpty else {
            throw EmbeddingsError.missingAPIKey
        }

        // Slice into batches and reassemble in input order. Sequential
        // execution keeps this simple and avoids saturating the rate-limit
        // budget; concurrent batches can be added later if ingest latency
        // proves to be a bottleneck.
        var output: [[Float]] = []
        output.reserveCapacity(texts.count)
        for batch in texts.batched(by: Self.maxBatchSize) {
            let vectors = try await embedBatch(batch, apiKey: apiKey)
            guard vectors.count == batch.count else {
                throw EmbeddingsError.shapeMismatch(
                    expected: batch.count, got: vectors.count)
            }
            output.append(contentsOf: vectors)
        }
        return output
    }

    // MARK: - Single batch

    private func embedBatch(_ batch: [String], apiKey: String) async throws -> [[Float]] {
        var req = URLRequest(url: Self.endpoint, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.xTitle, forHTTPHeaderField: "X-Title")

        let payload = RequestPayload(
            model: model,
            input: batch,
            dimensions: dimensions
        )
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw EmbeddingsError.transport(detail: "no HTTPURLResponse")
        }
        switch http.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw EmbeddingsError.unauthorized
        case 429:
            throw EmbeddingsError.rateLimited
        default:
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            Self.logger.warning("OpenRouter embeddings HTTP \(http.statusCode, privacy: .public): \(body, privacy: .public)")
            throw EmbeddingsError.serverError(statusCode: http.statusCode)
        }

        let decoded: ResponsePayload
        do {
            decoded = try JSONDecoder().decode(ResponsePayload.self, from: data)
        } catch {
            Self.logger.error("OpenRouter embeddings decode failed: \(error, privacy: .public)")
            throw EmbeddingsError.decoding
        }

        // Provider-side ordering is guaranteed by OpenAI-compatible schema
        // via the `index` field, but always defensively re-sort.
        let ordered = decoded.data.sorted { $0.index < $1.index }
        return ordered.map(\.embedding)
    }

    // MARK: - DTOs

    private struct RequestPayload: Encodable {
        let model: String
        let input: [String]
        let dimensions: Int
    }

    private struct ResponsePayload: Decodable {
        let data: [Item]
        struct Item: Decodable {
            let index: Int
            let embedding: [Float]
        }
    }
}

// MARK: - Errors

enum EmbeddingsError: LocalizedError {
    case missingAPIKey
    case unauthorized
    case rateLimited
    case serverError(statusCode: Int)
    case transport(detail: String)
    case decoding
    case shapeMismatch(expected: Int, got: Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenRouter API key not configured. Add it in Settings → AI."
        case .unauthorized:
            return "OpenRouter rejected the API key."
        case .rateLimited:
            return "OpenRouter is rate-limiting embedding requests. Try again shortly."
        case let .serverError(code):
            return "OpenRouter embeddings returned HTTP \(code)."
        case let .transport(detail):
            return "Network error contacting OpenRouter: \(detail)."
        case .decoding:
            return "Could not decode the OpenRouter embeddings response."
        case let .shapeMismatch(expected, got):
            return "Embeddings batch shape mismatch: expected \(expected), got \(got)."
        }
    }
}

// MARK: - Array batching

extension Array {
    /// Slice the array into chunks of at most `size` elements. Last chunk
    /// may be shorter. Used to honour OpenRouter's per-request input cap.
    func batched(by size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var out: [[Element]] = []
        out.reserveCapacity((count + size - 1) / size)
        var i = 0
        while i < count {
            let end = Swift.min(i + size, count)
            out.append(Array(self[i..<end]))
            i = end
        }
        return out
    }
}
