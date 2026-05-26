import Foundation
import os.log

struct OllamaModelCatalogService: Sendable {
    private static let logger = Logger.app("OllamaModelCatalogService")
    private static let decoder = JSONDecoder()

    private enum Constants {
        static let defaultTagsURL = "https://ollama.com/api/tags"
        static let timeout: TimeInterval = 30
    }

    private let apiKeyProvider: @Sendable () throws -> String?
    /// Tags URL derived from the configured chat URL. Defaults to the
    /// public Ollama Cloud endpoint when no override is supplied.
    private let tagsURL: URL

    init(
        chatURL: String? = nil,
        apiKeyProvider: @Sendable @escaping () throws -> String? = { try OllamaCredentialStore.apiKey() }
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.tagsURL = OllamaModelCatalogService.tagsURL(from: chatURL)
    }

    /// Derive the /api/tags discovery URL from a /api/chat endpoint string.
    ///
    /// If the path ends in "/chat", strip it and replace with "/tags".
    /// Otherwise use `<scheme>://<host>/api/tags` as a safe fallback.
    /// Malformed or nil input falls back to the public cloud URL.
    static func tagsURL(from chatURLString: String?) -> URL {
        guard let str = chatURLString,
              let chatURL = URL(string: str),
              let host = chatURL.host else {
            return URL(string: Constants.defaultTagsURL)!
        }
        var components = URLComponents()
        components.scheme = chatURL.scheme ?? "https"
        components.host = host
        components.port = chatURL.port
        let path = chatURL.path
        if path.hasSuffix("/chat") {
            components.path = String(path.dropLast("/chat".count)) + "/tags"
        } else {
            components.path = "/api/tags"
        }
        return components.url ?? URL(string: Constants.defaultTagsURL)!
    }

    func fetchModels() async throws -> [OllamaTagModel] {
        var request = URLRequest(url: tagsURL)
        if let apiKey = try apiKeyProvider(), !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = Constants.timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CatalogError.decoding("Ollama models: missing HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CatalogError.decoding("Ollama models returned HTTP \(http.statusCode)")
        }

        do {
            return try Self.decoder.decode(OllamaTagsResponse.self, from: data).models
        } catch {
            Self.logger.warning("Ollama models decode failed: \(error, privacy: .public)")
            throw CatalogError.decoding("Ollama models: \(error.localizedDescription)")
        }
    }
}

struct OllamaTagsResponse: Decodable, Sendable {
    var models: [OllamaTagModel]
}

struct OllamaTagModel: Decodable, Sendable {
    var name: String
    var model: String?
    var modifiedAt: Date?
    var size: Int64?
    var digest: String?
    var details: Details?

    enum CodingKeys: String, CodingKey {
        case name, model, size, digest, details
        case modifiedAt = "modified_at"
    }

    struct Details: Decodable, Sendable {
        var family: String?
        var families: [String]?
        var parameterSize: String?
        var quantizationLevel: String?

        enum CodingKeys: String, CodingKey {
            case family, families
            case parameterSize = "parameter_size"
            case quantizationLevel = "quantization_level"
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        size = try c.decodeIfPresent(Int64.self, forKey: .size)
        digest = try c.decodeIfPresent(String.self, forKey: .digest)
        details = try c.decodeIfPresent(Details.self, forKey: .details)
        if let raw = try c.decodeIfPresent(String.self, forKey: .modifiedAt) {
            modifiedAt = ISO8601DateFormatter.ollamaFlexible.date(from: raw)
                ?? ISO8601DateFormatter.ollamaInternet.date(from: raw)
        } else {
            modifiedAt = nil
        }
    }
}

private extension ISO8601DateFormatter {
    nonisolated(unsafe) static let ollamaInternet: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated(unsafe) static let ollamaFlexible: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
