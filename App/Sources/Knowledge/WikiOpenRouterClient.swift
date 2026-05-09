import Foundation

// MARK: - Wiki OpenRouter client

/// Stripped-down OpenRouter chat-completions client tuned for the wiki
/// compile pipeline.
///
/// Differs from `AgentOpenRouterClient` (which streams SSE deltas and
/// supports tool calls) on purpose:
///   • Compile turns are non-interactive — no streaming UI required.
///   • The response is forced to a single JSON object via
///     `response_format: { "type": "json_object" }`.
///   • There are no tool calls — the only side effect is the synthesis.
///
/// `Agent/` is intentionally untouched; we duplicate the small request
/// scaffolding rather than couple the wiki pipeline to the agent loop.
///
/// All real network calls are gated behind the `live` initialiser.
/// The `stubbed` initialiser returns deterministic fixture JSON so the
/// generator pipeline is exercisable in tests and previews without an
/// API key (lane 7's "real LLM calls are stubbed" constraint).
struct WikiOpenRouterClient: Sendable {

    // MARK: - Modes

    enum Mode: Sendable {
        /// Live mode — POSTs to OpenRouter. Requires an API key.
        case live(apiKey: String, model: String)

        /// Stub mode — returns the supplied JSON string verbatim. Used
        /// by tests, previews, and the lane-7 stubbed pipeline path.
        case stubbed(json: String)
    }

    let mode: Mode
    let urlSession: URLSession
    let endpoint: URL

    static let defaultEndpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    // MARK: - Init

    init(
        mode: Mode,
        endpoint: URL = WikiOpenRouterClient.defaultEndpoint,
        urlSession: URLSession = .shared
    ) {
        self.mode = mode
        self.endpoint = endpoint
        self.urlSession = urlSession
    }

    // MARK: - Convenience constructors

    static func live(apiKey: String, model: String = "openai/gpt-4o-mini") -> WikiOpenRouterClient {
        WikiOpenRouterClient(mode: .live(apiKey: apiKey, model: model))
    }

    static func stubbed(json: String) -> WikiOpenRouterClient {
        WikiOpenRouterClient(mode: .stubbed(json: json))
    }

    // MARK: - Public API

    /// Sends a system + user prompt to OpenRouter and returns the raw
    /// JSON content of the assistant message. Caller is responsible for
    /// decoding (see `WikiResponseParser`).
    ///
    /// In stubbed mode returns the stored fixture JSON unchanged.
    func compile(systemPrompt: String, userPrompt: String) async throws -> String {
        switch mode {
        case .stubbed(let json):
            return json
        case .live(let apiKey, let model):
            return try await compileLive(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                apiKey: apiKey,
                model: model
            )
        }
    }

    // MARK: - Live request

    private func compileLive(
        systemPrompt: String,
        userPrompt: String,
        apiKey: String,
        model: String
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
            "response_format": ["type": "json_object"],
            "stream": false,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw WikiClientError.malformedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            throw WikiClientError.httpError(status: http.statusCode, body: bodyString)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw WikiClientError.malformedResponse
        }
        return content
    }
}

// MARK: - Errors

enum WikiClientError: LocalizedError {
    case httpError(status: Int, body: String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .httpError(let status, let body):
            "Wiki API error (\(status)): \(body.prefix(200))"
        case .malformedResponse:
            "Malformed response from wiki API"
        }
    }
}
