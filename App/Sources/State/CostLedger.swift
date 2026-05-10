import Combine
import Foundation

enum CostFeature {
    static let agentChat = "agent.chat"
    static let agentNostr = "agent.nostr"
    static let episodeSummary = "episode.summary"
    static let briefingCompose = "briefing.compose"
    static let wikiCompile = "wiki.compile"
    static let embeddingsOpenRouter = "embeddings.openrouter"
    static let embeddingsOllama = "embeddings.ollama"
    static let categorizationRecompute = "categorization.recompute"

    static func displayName(for feature: String) -> String {
        switch feature {
        case agentChat:              return "Agent chat"
        case agentNostr:             return "Agent (Nostr)"
        case episodeSummary:         return "Episode summary"
        case briefingCompose:        return "Briefing"
        case wikiCompile:            return "Wiki compile"
        case embeddingsOpenRouter:   return "Embeddings (OpenRouter)"
        case embeddingsOllama:       return "Embeddings (Ollama)"
        case categorizationRecompute: return "Categorization"
        default:                     return feature
        }
    }
}

struct UsageRecord: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var at: Date
    var feature: String
    var model: String
    var promptTokens: Int
    var completionTokens: Int
    var cachedTokens: Int
    var reasoningTokens: Int
    var costUSD: Double
    var latencyMs: Int
    var requestPayloadJSON: String?
    var responseContentPreview: String?

    private enum CodingKeys: String, CodingKey {
        case id, at, feature, model
        case promptTokens, completionTokens, cachedTokens, reasoningTokens
        case costUSD, latencyMs
        case requestPayloadJSON, responseContentPreview
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.at = try c.decode(Date.self, forKey: .at)
        self.feature = try c.decode(String.self, forKey: .feature)
        self.model = try c.decode(String.self, forKey: .model)
        self.promptTokens = try c.decode(Int.self, forKey: .promptTokens)
        self.completionTokens = try c.decode(Int.self, forKey: .completionTokens)
        self.cachedTokens = try c.decode(Int.self, forKey: .cachedTokens)
        self.reasoningTokens = try c.decode(Int.self, forKey: .reasoningTokens)
        self.costUSD = try c.decode(Double.self, forKey: .costUSD)
        self.latencyMs = try c.decode(Int.self, forKey: .latencyMs)
        self.requestPayloadJSON = try c.decodeIfPresent(String.self, forKey: .requestPayloadJSON)
        self.responseContentPreview = try c.decodeIfPresent(String.self, forKey: .responseContentPreview)
    }

    init(
        id: UUID,
        at: Date,
        feature: String,
        model: String,
        promptTokens: Int,
        completionTokens: Int,
        cachedTokens: Int,
        reasoningTokens: Int,
        costUSD: Double,
        latencyMs: Int,
        requestPayloadJSON: String? = nil,
        responseContentPreview: String? = nil
    ) {
        self.id = id
        self.at = at
        self.feature = feature
        self.model = model
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.cachedTokens = cachedTokens
        self.reasoningTokens = reasoningTokens
        self.costUSD = costUSD
        self.latencyMs = latencyMs
        self.requestPayloadJSON = requestPayloadJSON
        self.responseContentPreview = responseContentPreview
    }
}

struct OpenRouterUsagePayload: Decodable, Sendable {
    struct PromptDetails: Decodable, Sendable {
        let cached_tokens: Int?
        let cache_write_tokens: Int?
        let audio_tokens: Int?
    }

    struct CompletionDetails: Decodable, Sendable {
        let reasoning_tokens: Int?
    }

    let prompt_tokens: Int?
    let completion_tokens: Int?
    let total_tokens: Int?
    let cost: Double?
    let prompt_tokens_details: PromptDetails?
    let completion_tokens_details: CompletionDetails?
}

@MainActor
final class CostLedger: ObservableObject {
    static let shared = CostLedger()

    @Published private(set) var records: [UsageRecord]

    private let directoryURL: URL
    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directoryURL = base.appendingPathComponent("UsageLedger", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("ledger.json")
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        records = Self.load(from: fileURL)
    }

    func log(
        feature: String,
        model: String,
        usage: OpenRouterUsagePayload?,
        latencyMs: Int,
        requestPayloadJSON: String? = nil,
        responseContentPreview: String? = nil
    ) {
        let record = UsageRecord(
            id: UUID(),
            at: Date(),
            feature: feature,
            model: model,
            promptTokens: usage?.prompt_tokens ?? 0,
            completionTokens: usage?.completion_tokens ?? 0,
            cachedTokens: usage?.prompt_tokens_details?.cached_tokens ?? 0,
            reasoningTokens: usage?.completion_tokens_details?.reasoning_tokens ?? 0,
            costUSD: usage?.cost ?? 0,
            latencyMs: latencyMs,
            requestPayloadJSON: requestPayloadJSON,
            responseContentPreview: responseContentPreview
        )
        records.insert(record, at: 0)
        save()
    }

    func logOllama(
        feature: String,
        model: String,
        promptTokens: Int,
        completionTokens: Int,
        latencyMs: Int,
        requestPayloadJSON: String? = nil,
        responseContentPreview: String? = nil
    ) {
        let record = UsageRecord(
            id: UUID(),
            at: Date(),
            feature: feature,
            model: model,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            cachedTokens: 0,
            reasoningTokens: 0,
            costUSD: 0,
            latencyMs: latencyMs,
            requestPayloadJSON: requestPayloadJSON,
            responseContentPreview: responseContentPreview
        )
        records.insert(record, at: 0)
        save()
    }

    func clear() {
        records = []
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    private static func load(from url: URL) -> [UsageRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([UsageRecord].self, from: data)) ?? []
    }
}
