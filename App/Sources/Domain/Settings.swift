import Foundation

// MARK: - Settings

enum OpenRouterCredentialSource: String, Codable, Hashable, Sendable {
    case none, manual, byok
}

enum ElevenLabsCredentialSource: String, Codable, Hashable, Sendable {
    case none, manual, byok
}

struct Settings: Codable, Hashable, Sendable {

    // MARK: - Defaults
    private enum Defaults {
        static let llmModel = "openai/gpt-4o-mini"
        static let elevenLabsSTTModel = "scribe_v1"
        static let elevenLabsTTSModel = "eleven_turbo_v2_5"
        static let nostrRelayURL = "wss://relay.tenex.chat"
    }

    // AI / LLM
    var llmModel: String = Defaults.llmModel
    var llmModelName: String = ""
    var memoryCompilationModel: String = Defaults.llmModel
    var memoryCompilationModelName: String = ""

    // OpenRouter credentials (secret stored in Keychain; only metadata here)
    var openRouterCredentialSource: OpenRouterCredentialSource = .none
    var openRouterBYOKKeyID: String?
    var openRouterBYOKKeyLabel: String?
    var openRouterConnectedAt: Date?
    var legacyOpenRouterAPIKey: String?

    // ElevenLabs credentials (secret stored in Keychain; only metadata here)
    var elevenLabsCredentialSource: ElevenLabsCredentialSource = .none
    var elevenLabsBYOKKeyID: String?
    var elevenLabsBYOKKeyLabel: String?
    var elevenLabsConnectedAt: Date?

    // ElevenLabs configuration
    var elevenLabsSTTModel: String = Defaults.elevenLabsSTTModel
    var elevenLabsTTSModel: String = Defaults.elevenLabsTTSModel
    var elevenLabsVoiceID: String = ""
    var elevenLabsVoiceName: String = ""

    // Nostr identity (private key stored in Keychain via NostrCredentialStore)
    var nostrEnabled: Bool = false
    var nostrRelayURL: String = Defaults.nostrRelayURL
    var nostrProfileName: String = ""
    var nostrProfileAbout: String = ""
    var nostrProfilePicture: String = ""
    var nostrPublicKeyHex: String?

    // Onboarding
    var hasCompletedOnboarding: Bool = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case llmModel, llmModelName, memoryCompilationModel, memoryCompilationModelName
        case openRouterAPIKey                                             // legacy
        case openRouterCredentialSource
        case openRouterBYOKKeyID, openRouterBYOKKeyLabel, openRouterConnectedAt
        case elevenLabsCredentialSource
        case elevenLabsBYOKKeyID, elevenLabsBYOKKeyLabel, elevenLabsConnectedAt
        case elevenLabsSTTModel, elevenLabsTTSModel, elevenLabsVoiceID, elevenLabsVoiceName
        case nostrEnabled, nostrRelayURL
        case nostrProfileName, nostrProfileAbout, nostrProfilePicture
        case nostrPublicKeyHex
        case hasCompletedOnboarding
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        llmModel = try c.decodeIfPresent(String.self, forKey: .llmModel) ?? Defaults.llmModel
        llmModelName = try c.decodeIfPresent(String.self, forKey: .llmModelName) ?? ""
        memoryCompilationModel = try c.decodeIfPresent(String.self, forKey: .memoryCompilationModel) ?? Defaults.llmModel
        memoryCompilationModelName = try c.decodeIfPresent(String.self, forKey: .memoryCompilationModelName) ?? ""
        openRouterCredentialSource = try c.decodeIfPresent(OpenRouterCredentialSource.self, forKey: .openRouterCredentialSource) ?? .none
        openRouterBYOKKeyID = try c.decodeIfPresent(String.self, forKey: .openRouterBYOKKeyID)
        openRouterBYOKKeyLabel = try c.decodeIfPresent(String.self, forKey: .openRouterBYOKKeyLabel)
        openRouterConnectedAt = try c.decodeIfPresent(Date.self, forKey: .openRouterConnectedAt)
        legacyOpenRouterAPIKey = try c.decodeIfPresent(String.self, forKey: .openRouterAPIKey)
        elevenLabsCredentialSource = try c.decodeIfPresent(ElevenLabsCredentialSource.self, forKey: .elevenLabsCredentialSource) ?? .none
        elevenLabsBYOKKeyID = try c.decodeIfPresent(String.self, forKey: .elevenLabsBYOKKeyID)
        elevenLabsBYOKKeyLabel = try c.decodeIfPresent(String.self, forKey: .elevenLabsBYOKKeyLabel)
        elevenLabsConnectedAt = try c.decodeIfPresent(Date.self, forKey: .elevenLabsConnectedAt)
        elevenLabsSTTModel = try c.decodeIfPresent(String.self, forKey: .elevenLabsSTTModel) ?? Defaults.elevenLabsSTTModel
        elevenLabsTTSModel = try c.decodeIfPresent(String.self, forKey: .elevenLabsTTSModel) ?? Defaults.elevenLabsTTSModel
        elevenLabsVoiceID = try c.decodeIfPresent(String.self, forKey: .elevenLabsVoiceID) ?? ""
        elevenLabsVoiceName = try c.decodeIfPresent(String.self, forKey: .elevenLabsVoiceName) ?? ""
        nostrEnabled = try c.decodeIfPresent(Bool.self, forKey: .nostrEnabled) ?? false
        nostrRelayURL = try c.decodeIfPresent(String.self, forKey: .nostrRelayURL) ?? Defaults.nostrRelayURL
        nostrProfileName = try c.decodeIfPresent(String.self, forKey: .nostrProfileName) ?? ""
        nostrProfileAbout = try c.decodeIfPresent(String.self, forKey: .nostrProfileAbout) ?? ""
        nostrProfilePicture = try c.decodeIfPresent(String.self, forKey: .nostrProfilePicture) ?? ""
        nostrPublicKeyHex = try c.decodeIfPresent(String.self, forKey: .nostrPublicKeyHex)
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false

        if openRouterCredentialSource == .none,
           let legacy = legacyOpenRouterAPIKey,
           !legacy.trimmed.isEmpty {
            openRouterCredentialSource = .manual
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(llmModel, forKey: .llmModel)
        try c.encode(llmModelName, forKey: .llmModelName)
        try c.encode(memoryCompilationModel, forKey: .memoryCompilationModel)
        try c.encode(memoryCompilationModelName, forKey: .memoryCompilationModelName)
        try c.encode(openRouterCredentialSource, forKey: .openRouterCredentialSource)
        try c.encodeIfPresent(openRouterBYOKKeyID, forKey: .openRouterBYOKKeyID)
        try c.encodeIfPresent(openRouterBYOKKeyLabel, forKey: .openRouterBYOKKeyLabel)
        try c.encodeIfPresent(openRouterConnectedAt, forKey: .openRouterConnectedAt)
        try c.encode(elevenLabsCredentialSource, forKey: .elevenLabsCredentialSource)
        try c.encodeIfPresent(elevenLabsBYOKKeyID, forKey: .elevenLabsBYOKKeyID)
        try c.encodeIfPresent(elevenLabsBYOKKeyLabel, forKey: .elevenLabsBYOKKeyLabel)
        try c.encodeIfPresent(elevenLabsConnectedAt, forKey: .elevenLabsConnectedAt)
        try c.encode(elevenLabsSTTModel, forKey: .elevenLabsSTTModel)
        try c.encode(elevenLabsTTSModel, forKey: .elevenLabsTTSModel)
        try c.encode(elevenLabsVoiceID, forKey: .elevenLabsVoiceID)
        try c.encode(elevenLabsVoiceName, forKey: .elevenLabsVoiceName)
        try c.encode(nostrEnabled, forKey: .nostrEnabled)
        try c.encode(nostrRelayURL, forKey: .nostrRelayURL)
        try c.encode(nostrProfileName, forKey: .nostrProfileName)
        try c.encode(nostrProfileAbout, forKey: .nostrProfileAbout)
        try c.encode(nostrProfilePicture, forKey: .nostrProfilePicture)
        try c.encodeIfPresent(nostrPublicKeyHex, forKey: .nostrPublicKeyHex)
        try c.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
    }

    // MARK: - Display helpers

    /// Returns a human-readable display name for an OpenRouter model.
    ///
    /// Preference order:
    /// 1. `modelName` when non-empty (persisted human-readable name from catalog).
    /// 2. Slug after the last `/` in `modelID` (e.g. "gpt-4o" from "openai/gpt-4o").
    /// 3. `modelID` verbatim when it contains no `/`.
    /// 4. "Not set" when `modelID` is empty.
    static func modelDisplayName(modelID: String, modelName: String = "") -> String {
        let name = modelName.trimmed
        if !name.isEmpty { return name }
        let id = modelID.trimmed
        guard !id.isEmpty else { return "Not set" }
        if let idx = id.lastIndex(of: "/") { return String(id[id.index(after: idx)...]) }
        return id
    }

    mutating func markOpenRouterManual(connectedAt: Date = Date()) {
        openRouterCredentialSource = .manual
        openRouterBYOKKeyID = nil
        openRouterBYOKKeyLabel = nil
        openRouterConnectedAt = connectedAt
        legacyOpenRouterAPIKey = nil
    }

    mutating func markOpenRouterBYOK(keyID: String?, keyLabel: String?, connectedAt: Date = Date()) {
        openRouterCredentialSource = .byok
        openRouterBYOKKeyID = keyID
        openRouterBYOKKeyLabel = keyLabel
        openRouterConnectedAt = connectedAt
        legacyOpenRouterAPIKey = nil
    }

    mutating func clearOpenRouterCredential() {
        openRouterCredentialSource = .none
        openRouterBYOKKeyID = nil
        openRouterBYOKKeyLabel = nil
        openRouterConnectedAt = nil
        legacyOpenRouterAPIKey = nil
    }

    mutating func markElevenLabsManual(connectedAt: Date = Date()) {
        elevenLabsCredentialSource = .manual
        elevenLabsBYOKKeyID = nil
        elevenLabsBYOKKeyLabel = nil
        elevenLabsConnectedAt = connectedAt
    }

    mutating func markElevenLabsBYOK(keyID: String?, keyLabel: String?, connectedAt: Date = Date()) {
        elevenLabsCredentialSource = .byok
        elevenLabsBYOKKeyID = keyID
        elevenLabsBYOKKeyLabel = keyLabel
        elevenLabsConnectedAt = connectedAt
    }

    mutating func clearElevenLabsCredential() {
        elevenLabsCredentialSource = .none
        elevenLabsBYOKKeyID = nil
        elevenLabsBYOKKeyLabel = nil
        elevenLabsConnectedAt = nil
    }
}
