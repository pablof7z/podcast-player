import Foundation

// MARK: - Settings

enum OpenRouterCredentialSource: String, Codable, Hashable, Sendable {
    case none, manual, byok
}

enum ElevenLabsCredentialSource: String, Codable, Hashable, Sendable {
    case none, manual, byok
}

enum OllamaCredentialSource: String, Codable, Hashable, Sendable {
    case none, manual, byok
}

struct Settings: Codable, Hashable, Sendable {

    // MARK: - Defaults
    private enum Defaults {
        static let llmModel = "openai/gpt-4o-mini"
        static let elevenLabsSTTModel = "scribe_v1"
        static let elevenLabsTTSModel = "eleven_turbo_v2_5"
        static let nostrRelayURL = "wss://relay.tenex.chat"
        static let defaultPlaybackRate: Double = 1.0
        static let skipForwardSeconds: Int = 30
        static let skipBackwardSeconds: Int = 15
    }

    // AI / LLM
    var llmModel: String = Defaults.llmModel
    var llmModelName: String = ""
    var memoryCompilationModel: String = Defaults.llmModel
    var memoryCompilationModelName: String = ""
    /// Model used by `WikiGenerator`. Kept distinct from `llmModel` so users can pick a
    /// cheaper / faster model for wiki compilation than for live agent chat — same pattern
    /// as `memoryCompilationModel`.
    var wikiModel: String = Defaults.llmModel
    var wikiModelName: String = ""
    var embeddingsModel: String = Self.defaultEmbeddingsModel
    var embeddingsModelName: String = ""
    /// When `true`, optionally re-rank top-k RAG candidates with a cross-encoder. Off by
    /// default to save tokens; settings UI exposes the toggle.
    var rerankerEnabled: Bool = false

    // OpenRouter credentials (secret stored in Keychain; only metadata here)
    var openRouterCredentialSource: OpenRouterCredentialSource = .none
    var openRouterBYOKKeyID: String?
    var openRouterBYOKKeyLabel: String?
    var openRouterConnectedAt: Date?
    var legacyOpenRouterAPIKey: String?

    // Ollama Cloud credentials (secret stored in Keychain; only metadata here)
    var ollamaCredentialSource: OllamaCredentialSource = .none
    var ollamaBYOKKeyID: String?
    var ollamaBYOKKeyLabel: String?
    var ollamaConnectedAt: Date?

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

    // Playback
    /// Default playback rate (0.5x – 3.0x). Per-show overrides live on `PodcastSubscription`.
    var defaultPlaybackRate: Double = Defaults.defaultPlaybackRate
    /// Seconds the forward-skip transport button advances by. Mirrored to the lock-screen.
    var skipForwardSeconds: Int = Defaults.skipForwardSeconds
    /// Seconds the back-skip transport button rewinds by. Mirrored to the lock-screen.
    var skipBackwardSeconds: Int = Defaults.skipBackwardSeconds
    /// When `true`, an episode is automatically marked played the first time playback
    /// reaches its end. Defaults on for parity with Apple Podcasts.
    var autoMarkPlayedAtEnd: Bool = true
    /// When `true`, downloaded enclosures are deleted as soon as the episode is
    /// marked played (auto-end-of-play OR explicit "Mark as played"). Off by
    /// default — without it, downloads are kept until manually removed.
    var autoDeleteDownloadsAfterPlayed: Bool = false
    /// When `true`, the next episode in `PlaybackState.queue` (Up Next)
    /// starts playing automatically when the current episode finishes.
    /// Defaults on for parity with Apple Podcasts. Suppressed when the
    /// sleep timer has armed an end-of-episode stop.
    var autoPlayNext: Bool = true
    /// When `true`, the player auto-seeks past detected ad segments
    /// (`AdSegmentDetector` output, stored on `Episode.adSegments`).
    /// Defaults off for v1 — opt-in until detection quality is proven. The
    /// chapter rail still flags ad-overlapping chapters visually regardless.
    var autoSkipAds: Bool = false

    // Wiki
    /// When `true`, `WikiGenerator` runs (or refreshes) the relevant wiki pages as soon as
    /// a new transcript finishes ingesting. Defaults off so first-run users don't burn
    /// tokens before deciding to opt in.
    var wikiAutoGenerateOnTranscriptIngest: Bool = false

    // Transcripts
    /// When `true`, the app pre-fetches publisher-supplied transcripts in the
    /// background as soon as new episodes appear (called from
    /// `AppStateStore.upsertEpisodes` after a feed refresh). Default-on
    /// because the agent layer (RAG, wiki, briefings, summarisation) only
    /// works once the transcript exists; publisher transcripts are typically
    /// tens of KB so the bandwidth cost is small. Toggle off in
    /// Settings → Transcripts to defer everything to manual fetch.
    var autoIngestPublisherTranscripts: Bool = true
    /// When `true`, episodes lacking a publisher transcript fall back to ElevenLabs Scribe
    /// transcription. Requires an ElevenLabs key; defaults on so existing behaviour is
    /// preserved.
    var autoFallbackToScribe: Bool = true

    // Notifications (per-kind toggles; the system permission is separate)
    /// When `true`, fire a local notification when a feed refresh discovers a brand-new
    /// episode for a subscription that has notifications enabled.
    var notifyOnNewEpisodes: Bool = true
    /// When `true`, fire a local notification when a daily/weekly briefing finishes
    /// generating and is ready to play.
    var notifyOnBriefingReady: Bool = true

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
        case wikiModel, wikiModelName, embeddingsModel, embeddingsModelName, rerankerEnabled
        case openRouterAPIKey                                             // legacy
        case openRouterCredentialSource
        case openRouterBYOKKeyID, openRouterBYOKKeyLabel, openRouterConnectedAt
        case ollamaCredentialSource, ollamaBYOKKeyID, ollamaBYOKKeyLabel, ollamaConnectedAt
        case elevenLabsCredentialSource
        case elevenLabsBYOKKeyID, elevenLabsBYOKKeyLabel, elevenLabsConnectedAt
        case elevenLabsSTTModel, elevenLabsTTSModel, elevenLabsVoiceID, elevenLabsVoiceName
        case defaultPlaybackRate, skipForwardSeconds, skipBackwardSeconds, autoMarkPlayedAtEnd
        case autoDeleteDownloadsAfterPlayed, autoPlayNext, autoSkipAds
        case wikiAutoGenerateOnTranscriptIngest
        case autoIngestPublisherTranscripts, autoFallbackToScribe
        case notifyOnNewEpisodes, notifyOnBriefingReady
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
        wikiModel = try c.decodeIfPresent(String.self, forKey: .wikiModel) ?? Defaults.llmModel
        wikiModelName = try c.decodeIfPresent(String.self, forKey: .wikiModelName) ?? ""
        embeddingsModel = try c.decodeIfPresent(String.self, forKey: .embeddingsModel) ?? Self.defaultEmbeddingsModel
        embeddingsModelName = try c.decodeIfPresent(String.self, forKey: .embeddingsModelName) ?? ""
        rerankerEnabled = try c.decodeIfPresent(Bool.self, forKey: .rerankerEnabled) ?? false
        openRouterCredentialSource = try c.decodeIfPresent(OpenRouterCredentialSource.self, forKey: .openRouterCredentialSource) ?? .none
        openRouterBYOKKeyID = try c.decodeIfPresent(String.self, forKey: .openRouterBYOKKeyID)
        openRouterBYOKKeyLabel = try c.decodeIfPresent(String.self, forKey: .openRouterBYOKKeyLabel)
        openRouterConnectedAt = try c.decodeIfPresent(Date.self, forKey: .openRouterConnectedAt)
        legacyOpenRouterAPIKey = try c.decodeIfPresent(String.self, forKey: .openRouterAPIKey)
        ollamaCredentialSource = try c.decodeIfPresent(OllamaCredentialSource.self, forKey: .ollamaCredentialSource) ?? .none
        ollamaBYOKKeyID = try c.decodeIfPresent(String.self, forKey: .ollamaBYOKKeyID)
        ollamaBYOKKeyLabel = try c.decodeIfPresent(String.self, forKey: .ollamaBYOKKeyLabel)
        ollamaConnectedAt = try c.decodeIfPresent(Date.self, forKey: .ollamaConnectedAt)
        elevenLabsCredentialSource = try c.decodeIfPresent(ElevenLabsCredentialSource.self, forKey: .elevenLabsCredentialSource) ?? .none
        elevenLabsBYOKKeyID = try c.decodeIfPresent(String.self, forKey: .elevenLabsBYOKKeyID)
        elevenLabsBYOKKeyLabel = try c.decodeIfPresent(String.self, forKey: .elevenLabsBYOKKeyLabel)
        elevenLabsConnectedAt = try c.decodeIfPresent(Date.self, forKey: .elevenLabsConnectedAt)
        elevenLabsSTTModel = try c.decodeIfPresent(String.self, forKey: .elevenLabsSTTModel) ?? Defaults.elevenLabsSTTModel
        elevenLabsTTSModel = try c.decodeIfPresent(String.self, forKey: .elevenLabsTTSModel) ?? Defaults.elevenLabsTTSModel
        elevenLabsVoiceID = try c.decodeIfPresent(String.self, forKey: .elevenLabsVoiceID) ?? ""
        elevenLabsVoiceName = try c.decodeIfPresent(String.self, forKey: .elevenLabsVoiceName) ?? ""
        defaultPlaybackRate = try c.decodeIfPresent(Double.self, forKey: .defaultPlaybackRate) ?? Defaults.defaultPlaybackRate
        skipForwardSeconds = try c.decodeIfPresent(Int.self, forKey: .skipForwardSeconds) ?? Defaults.skipForwardSeconds
        skipBackwardSeconds = try c.decodeIfPresent(Int.self, forKey: .skipBackwardSeconds) ?? Defaults.skipBackwardSeconds
        autoMarkPlayedAtEnd = try c.decodeIfPresent(Bool.self, forKey: .autoMarkPlayedAtEnd) ?? true
        autoDeleteDownloadsAfterPlayed = try c.decodeIfPresent(Bool.self, forKey: .autoDeleteDownloadsAfterPlayed) ?? false
        autoPlayNext = try c.decodeIfPresent(Bool.self, forKey: .autoPlayNext) ?? true
        autoSkipAds = try c.decodeIfPresent(Bool.self, forKey: .autoSkipAds) ?? false
        wikiAutoGenerateOnTranscriptIngest = try c.decodeIfPresent(Bool.self, forKey: .wikiAutoGenerateOnTranscriptIngest) ?? false
        autoIngestPublisherTranscripts = try c.decodeIfPresent(Bool.self, forKey: .autoIngestPublisherTranscripts) ?? true
        autoFallbackToScribe = try c.decodeIfPresent(Bool.self, forKey: .autoFallbackToScribe) ?? true
        notifyOnNewEpisodes = try c.decodeIfPresent(Bool.self, forKey: .notifyOnNewEpisodes) ?? true
        notifyOnBriefingReady = try c.decodeIfPresent(Bool.self, forKey: .notifyOnBriefingReady) ?? true
        nostrEnabled = try c.decodeIfPresent(Bool.self, forKey: .nostrEnabled) ?? false
        nostrRelayURL = try c.decodeIfPresent(String.self, forKey: .nostrRelayURL) ?? Defaults.nostrRelayURL
        nostrProfileName = try c.decodeIfPresent(String.self, forKey: .nostrProfileName) ?? ""
        nostrProfileAbout = try c.decodeIfPresent(String.self, forKey: .nostrProfileAbout) ?? ""
        nostrProfilePicture = try c.decodeIfPresent(String.self, forKey: .nostrProfilePicture) ?? ""
        nostrPublicKeyHex = try c.decodeIfPresent(String.self, forKey: .nostrPublicKeyHex)
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false

        if openRouterCredentialSource == .none,
           let legacy = legacyOpenRouterAPIKey,
           !legacy.isBlank {
            openRouterCredentialSource = .manual
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(llmModel, forKey: .llmModel)
        try c.encode(llmModelName, forKey: .llmModelName)
        try c.encode(memoryCompilationModel, forKey: .memoryCompilationModel)
        try c.encode(memoryCompilationModelName, forKey: .memoryCompilationModelName)
        try c.encode(wikiModel, forKey: .wikiModel)
        try c.encode(wikiModelName, forKey: .wikiModelName)
        try c.encode(embeddingsModel, forKey: .embeddingsModel)
        try c.encode(embeddingsModelName, forKey: .embeddingsModelName)
        try c.encode(rerankerEnabled, forKey: .rerankerEnabled)
        try c.encode(openRouterCredentialSource, forKey: .openRouterCredentialSource)
        try c.encodeIfPresent(openRouterBYOKKeyID, forKey: .openRouterBYOKKeyID)
        try c.encodeIfPresent(openRouterBYOKKeyLabel, forKey: .openRouterBYOKKeyLabel)
        try c.encodeIfPresent(openRouterConnectedAt, forKey: .openRouterConnectedAt)
        try c.encode(ollamaCredentialSource, forKey: .ollamaCredentialSource)
        try c.encodeIfPresent(ollamaBYOKKeyID, forKey: .ollamaBYOKKeyID)
        try c.encodeIfPresent(ollamaBYOKKeyLabel, forKey: .ollamaBYOKKeyLabel)
        try c.encodeIfPresent(ollamaConnectedAt, forKey: .ollamaConnectedAt)
        try c.encode(elevenLabsCredentialSource, forKey: .elevenLabsCredentialSource)
        try c.encodeIfPresent(elevenLabsBYOKKeyID, forKey: .elevenLabsBYOKKeyID)
        try c.encodeIfPresent(elevenLabsBYOKKeyLabel, forKey: .elevenLabsBYOKKeyLabel)
        try c.encodeIfPresent(elevenLabsConnectedAt, forKey: .elevenLabsConnectedAt)
        try c.encode(elevenLabsSTTModel, forKey: .elevenLabsSTTModel)
        try c.encode(elevenLabsTTSModel, forKey: .elevenLabsTTSModel)
        try c.encode(elevenLabsVoiceID, forKey: .elevenLabsVoiceID)
        try c.encode(elevenLabsVoiceName, forKey: .elevenLabsVoiceName)
        try c.encode(defaultPlaybackRate, forKey: .defaultPlaybackRate)
        try c.encode(skipForwardSeconds, forKey: .skipForwardSeconds)
        try c.encode(skipBackwardSeconds, forKey: .skipBackwardSeconds)
        try c.encode(autoMarkPlayedAtEnd, forKey: .autoMarkPlayedAtEnd)
        try c.encode(autoDeleteDownloadsAfterPlayed, forKey: .autoDeleteDownloadsAfterPlayed)
        try c.encode(autoPlayNext, forKey: .autoPlayNext)
        try c.encode(autoSkipAds, forKey: .autoSkipAds)
        try c.encode(wikiAutoGenerateOnTranscriptIngest, forKey: .wikiAutoGenerateOnTranscriptIngest)
        try c.encode(autoIngestPublisherTranscripts, forKey: .autoIngestPublisherTranscripts)
        try c.encode(autoFallbackToScribe, forKey: .autoFallbackToScribe)
        try c.encode(notifyOnNewEpisodes, forKey: .notifyOnNewEpisodes)
        try c.encode(notifyOnBriefingReady, forKey: .notifyOnBriefingReady)
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
        let reference = LLMModelReference(storedID: id)
        if reference.provider != .openRouter { return reference.modelID }
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

    mutating func markOllamaManual(connectedAt: Date = Date()) {
        ollamaCredentialSource = .manual
        ollamaBYOKKeyID = nil
        ollamaBYOKKeyLabel = nil
        ollamaConnectedAt = connectedAt
    }

    mutating func markOllamaBYOK(keyID: String?, keyLabel: String?, connectedAt: Date = Date()) {
        ollamaCredentialSource = .byok
        ollamaBYOKKeyID = keyID
        ollamaBYOKKeyLabel = keyLabel
        ollamaConnectedAt = connectedAt
    }

    mutating func clearOllamaCredential() {
        ollamaCredentialSource = .none
        ollamaBYOKKeyID = nil
        ollamaBYOKKeyLabel = nil
        ollamaConnectedAt = nil
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

// MARK: - Embedding constants
//
// Display-only metadata for the on-device embedding pipeline. Surfaced in the AI
// settings UI so the user can confirm what the RAG layer is using.

extension Settings {
    /// Provider/model identifier used by `EmbeddingsClient`. The actual call site
    /// defaults to this value until the user chooses a provider-specific model.
    static let defaultEmbeddingsModel: String = "openai/text-embedding-3-large"
    static let embeddingsModelID: String = defaultEmbeddingsModel
    /// Truncation dimension applied to embeddings (Matryoshka). See
    /// `docs/spec/research/embeddings-rag-stack.md`.
    static let embeddingsDimensions: Int = 1024
    /// Display string mirroring `model@dim`, used directly in settings rows.
    static func embeddingsModelDisplay(modelID: String, modelName: String = "") -> String {
        "\(modelDisplayName(modelID: modelID, modelName: modelName))@\(embeddingsDimensions)"
    }

    static var embeddingsModelDisplay: String {
        embeddingsModelDisplay(modelID: defaultEmbeddingsModel)
    }
}
