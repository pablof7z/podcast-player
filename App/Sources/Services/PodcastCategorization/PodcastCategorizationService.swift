import Foundation
import Observation
import os.log

// MARK: - Errors

enum CategorizationError: LocalizedError {
    case noAPIKey
    case noSubscriptions
    case invalidResponse
    case httpError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenRouter is not connected. Add a key in Settings → Intelligence → Providers."
        case .noSubscriptions:
            return "Add at least one podcast subscription before generating categories."
        case .invalidResponse:
            return "The model returned an invalid response. Try again."
        case .httpError(let status, let body):
            return "Categorization API error (\(status)): \(body.prefix(200))"
        }
    }
}

// MARK: - Service

/// Drives one-shot LLM categorization of the user's subscription library.
///
/// Why a singleton + `@Observable`: the recompute is rare (user-triggered
/// from Settings), but the UI wants to reflect `isRunning` from anywhere
/// the action can be kicked off. Single-flight is enforced by checking
/// `isRunning` before starting; `recompute(store:)` returns immediately
/// if a run is already in progress.
///
/// Networking is direct to OpenRouter's chat-completions endpoint, mirroring
/// the pattern in `WikiOpenRouterClient`. The OAuth-flavoured
/// `BYOKConnectService` only handles key acquisition, not chat — referenced
/// here because the credential lookup goes through `OpenRouterCredentialStore`
/// which the BYOK flow populates.
@MainActor
@Observable
final class PodcastCategorizationService {

    static let shared = PodcastCategorizationService()

    nonisolated private static let logger = Logger.app("PodcastCategorizationService")

    /// Wall-clock of the last successful recompute. Drives the "last run"
    /// row that the Settings sheet renders.
    private(set) var lastRun: Date?

    /// True while a recompute is in flight. UI binds to this for spinner +
    /// disabled-button state.
    private(set) var isRunning: Bool = false

    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private static let temperature: Double = 0.3
    private static let requestTimeout: TimeInterval = 90

    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: - Public entry point

    /// Sends one prompt to the configured OpenRouter model, validates the
    /// response, and persists the resulting categories on the store.
    ///
    /// Throws `.noAPIKey` if OpenRouter isn't connected, `.noSubscriptions`
    /// if the library is empty, `.invalidResponse` for any parser/validation
    /// failure, and `.httpError` for non-2xx responses.
    func recompute(store: AppStateStore) async throws {
        // Single-flight: a second concurrent caller silently no-ops rather
        // than queueing or throwing. The only entry-point today is the
        // Settings sheet, which gates its own UI on `isRunning`; future
        // callers must check `isRunning` themselves before calling.
        guard !isRunning else { return }
        let subscriptions = store.state.subscriptions
        guard !subscriptions.isEmpty else {
            throw CategorizationError.noSubscriptions
        }
        let apiKey: String
        do {
            guard let key = try OpenRouterCredentialStore.apiKey() else {
                throw CategorizationError.noAPIKey
            }
            apiKey = key
        } catch let error as CategorizationError {
            throw error
        } catch {
            Self.logger.error("OpenRouterCredentialStore.apiKey failed: \(error, privacy: .public)")
            throw CategorizationError.noAPIKey
        }

        let requestedModel = store.state.settings.llmModel
        Self.logger.info("recompute starting subs=\(subscriptions.count, privacy: .public) model=\(requestedModel, privacy: .public)")

        isRunning = true
        defer { isRunning = false }

        let (rawContent, resolvedModel) = try await callOpenRouter(
            apiKey: apiKey,
            model: requestedModel,
            subscriptions: subscriptions
        )

        let generatedAt = Date()
        let categories = try PodcastCategorizationParser.categories(
            from: rawContent,
            subscriptions: subscriptions,
            generatedAt: generatedAt,
            model: resolvedModel ?? requestedModel
        )

        store.setCategories(categories)
        lastRun = generatedAt
        Self.logger.info("recompute complete categories=\(categories.count, privacy: .public)")
    }

    // MARK: - Network

    private func callOpenRouter(
        apiKey: String,
        model: String,
        subscriptions: [PodcastSubscription]
    ) async throws -> (content: String, modelEcho: String?) {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.requestTimeout

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": PodcastCategorizationPrompt.systemPrompt()],
                ["role": "user", "content": PodcastCategorizationPrompt.userPrompt(subscriptions: subscriptions)],
            ],
            "response_format": ["type": "json_object"],
            "temperature": Self.temperature,
            "stream": false,
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData
        let requestPayloadJSON = String(data: bodyData, encoding: .utf8)

        let start = Date()
        let (data, response) = try await urlSession.data(for: request)
        let latencyMs = Int(Date().timeIntervalSince(start) * 1000)

        guard let http = response as? HTTPURLResponse else {
            throw CategorizationError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            throw CategorizationError.httpError(status: http.statusCode, body: bodyString)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw CategorizationError.invalidResponse
        }

        let modelEcho = json["model"] as? String

        if let usageRaw = json["usage"] {
            let usageData = try? JSONSerialization.data(withJSONObject: usageRaw)
            let usage = usageData.flatMap { try? JSONDecoder().decode(OpenRouterUsagePayload.self, from: $0) }
            let modelUsed = modelEcho ?? model
            CostLedger.shared.log(
                feature: CostFeature.categorizationRecompute,
                model: modelUsed,
                usage: usage,
                latencyMs: latencyMs,
                requestPayloadJSON: requestPayloadJSON,
                responseContentPreview: content
            )
        }

        return (content, modelEcho)
    }
}
