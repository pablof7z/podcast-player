import Foundation
import os.log

/// Concrete `PerplexityClientProtocol` — wraps the Perplexity online-search API.
///
/// Reads its bearer token from the existing `KeychainStore` under
/// `(service: "PerplexityCredentialStore", account: "perplexity_api_key")`.
/// If no key is stored the client throws `PerplexityClientError.missingAPIKey`
/// rather than calling out — callers are expected to surface a "needs setup"
/// affordance to the user.
///
/// Lane 10 deliberately does **not** add a typed `PerplexityCredentialStore`
/// alongside the existing `OpenRouterCredentialStore` / `ElevenLabsCredentialStore`.
/// That belongs to a settings/keychain lane. The constants here are the
/// contract a future credential store must honour. See the TODO below.
public actor PerplexityClient: PerplexityClientProtocol {

    // MARK: - Keychain contract

    /// Service name used for the Perplexity bearer token in the iOS Keychain.
    /// TODO(lane-x): create a `PerplexityCredentialStore` that owns this string;
    /// for now we read raw via `KeychainStore`.
    public static let keychainService = "PerplexityCredentialStore"
    /// Account name used for the Perplexity bearer token in the iOS Keychain.
    public static let keychainAccount = "perplexity_api_key"

    // MARK: - Endpoint

    /// Default Perplexity chat-completions endpoint. Exposed for tests.
    public static let defaultEndpoint = URL(string: "https://api.perplexity.ai/chat/completions")!
    /// Default model the client requests. Conservative — small + online.
    public static let defaultModel = "sonar-small-online"

    private let endpoint: URL
    private let model: String
    private let session: URLSession
    private let logger = Logger.app("PerplexityClient")

    public init(
        endpoint: URL = PerplexityClient.defaultEndpoint,
        model: String = PerplexityClient.defaultModel,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.model = model
        self.session = session
    }

    // MARK: - PerplexityClientProtocol

    public func search(query: String) async throws -> PerplexityResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PerplexityClientError.invalidQuery
        }

        let apiKey = try Self.readAPIKey()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": trimmed],
            ],
            "return_citations": true,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PerplexityClientError.transport("non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            logger.error("Perplexity HTTP \(http.statusCode, privacy: .public): \(bodyText, privacy: .public)")
            throw PerplexityClientError.httpStatus(http.statusCode)
        }

        return try Self.parseResponse(data)
    }

    // MARK: - Helpers

    /// Reads the API key from the Keychain. Throws if no key is present so the
    /// agent's `perplexity_search` tool can surface a clean error to the model.
    static func readAPIKey() throws -> String {
        let stored: String?
        do {
            stored = try KeychainStore.readString(service: keychainService, account: keychainAccount)
        } catch {
            throw PerplexityClientError.keychain(error.localizedDescription)
        }
        guard let key = stored, !key.isEmpty else {
            throw PerplexityClientError.missingAPIKey
        }
        return key
    }

    /// Parses Perplexity's chat-completions JSON into a `PerplexityResult`.
    /// Tolerant: missing citations array becomes `[]`, missing answer becomes
    /// the empty string. Exposed `internal` for tests.
    static func parseResponse(_ data: Data) throws -> PerplexityResult {
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let root = raw as? [String: Any] else {
            throw PerplexityClientError.malformedResponse("root not an object")
        }

        // Answer text — choices[0].message.content
        var answer = ""
        if let choices = root["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            answer = content
        }

        // Citations — Perplexity returns them either as a top-level "citations"
        // array of URL strings, or inside an "search_results" array of objects.
        var sources: [PerplexityResult.Source] = []
        if let urls = root["citations"] as? [String] {
            sources = urls.map { PerplexityResult.Source(title: $0, url: $0) }
        } else if let results = root["search_results"] as? [[String: Any]] {
            sources = results.compactMap { obj in
                guard let url = obj["url"] as? String else { return nil }
                let title = (obj["title"] as? String) ?? url
                return PerplexityResult.Source(title: title, url: url)
            }
        }

        return PerplexityResult(answer: answer, sources: sources)
    }
}

// MARK: - Errors

public enum PerplexityClientError: LocalizedError {
    case invalidQuery
    case missingAPIKey
    case keychain(String)
    case transport(String)
    case httpStatus(Int)
    case malformedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "Empty Perplexity query."
        case .missingAPIKey:
            return "No Perplexity API key configured. Add one in Settings."
        case .keychain(let detail):
            return "Keychain error reading Perplexity key: \(detail)"
        case .transport(let detail):
            return "Network error talking to Perplexity: \(detail)"
        case .httpStatus(let code):
            return "Perplexity returned HTTP \(code)."
        case .malformedResponse(let detail):
            return "Couldn't parse Perplexity response: \(detail)"
        }
    }
}
