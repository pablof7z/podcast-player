import Foundation

// MARK: - Podcast UniFFI endpoint helpers

enum PodcastAppEndpoint {
    case threadingProjection
    case agentEmptyState
    case librarySummary
    case libraryFollowedPodcasts
    case libraryOwnedPodcasts
    case libraryDownloadRows
    case libraryStarredEpisodes
    case libraryCategorizationPrompt
    case agentTtsDefaultVoice
    case agentGeneratedPodcastDescriptor
    case nowPlayingToolResult
    case providerModelCatalog
    case speechModelCatalog
    case localModelCatalog
    case validateOpenrouterKey
    case validateElevenlabsKey
    case elevenlabsVoiceCatalog
    case audioReport
    case downloadReport
    case httpReport
    case itunesDirectorySearch
    case itunesLookupFeedUrl
    case itunesTopPodcasts
    case threadingActiveTopics
    case agentInventory
    case agentInventoryList
    case localSearch
    case homeContinueListening
    case homeTriageRollup
    case homeSubscriptionList
    case homeCategoryCards
    case carplayListenNow
    case carplayShows
    case carplayShowEpisodes
    case carplayDownloads
    case libraryShowEpisodes
    case libraryPodcastStats
    case libraryEpisodeForAudioUrl
    case libraryAllEpisodes
    case libraryAllPodcasts
    case libraryCategories
    case libraryEpisodeLookup
    case librarySubscriptionStatus
    case libraryPodcastForOwnerPubkey
    case libraryCategorizationParse
    case libraryCategoryChange
    case agentChatTitlePrompt
    case agentChatTitleParse
    case agentNostrPeerPrompt
    case agentSystemPrompt
    case agentConversationHistory
    case agentVoiceList
    case agentYoutubeSearchPlan
    case agentYoutubeSearchResults
    case agentDirectorySearchPlan
    case agentDirectorySearchResults
    case agentCategoryList
    case agentEpisodeListPlan
    case agentEpisodeListResults
    case agentEpisodeListError
    case agentOwnedPodcastTool
    case agentSearchTool
    case agentActionTool
    case storageBreakdown
    case agentTtsEpisodePlan
    case agentTtsToolPlan
    case agentTtsToolResult
    case agentVoiceConfigurePlan
    case agentVoiceConfigureResult
    case voiceReport
    case networkReport
    case transcriptReport
    case transcriptIngestPlan
    case transcriptAutoIngestCandidates
    case transcriptToolResult
    case episodeMutationToolResult
    case playbackToolResult
    case externalPlayPlan
    case agentAskEnqueue
    case agentAskSettle
    case memoryRememberText
    case episodeEvents
    case recordEpisodeEvent
    case chatComplete
    case providerComplete
    case providerEmbed
    case knowledgeQuery
    case knowledgeSimilarEpisode
    case knowledgeHomeRelated
    case knowledgeChunk
    case knowledgeResolveScope
    case perplexitySearch
    case byokExchange
    case openrouterWhisperTranscribe
    case elevenlabsScribeTranscribe
    case assemblyaiTranscribe
    case elevenlabsTtsSynthesize
    case generateImage
    case rerank

    func call(on app: PodcastApp, requestJson: String?) -> String? {
        switch self {
        case .threadingProjection: return app.threadingProjection()
        case .agentEmptyState: return app.agentEmptyState()
        case .librarySummary: return app.librarySummary()
        case .libraryFollowedPodcasts: return app.libraryFollowedPodcasts()
        case .libraryOwnedPodcasts: return app.libraryOwnedPodcasts()
        case .libraryDownloadRows: return app.libraryDownloadRows()
        case .libraryStarredEpisodes: return app.libraryStarredEpisodes()
        case .libraryCategorizationPrompt: return app.libraryCategorizationPrompt()
        case .agentTtsDefaultVoice: return app.agentTtsDefaultVoice()
        case .agentGeneratedPodcastDescriptor: return app.agentGeneratedPodcastDescriptor()
        case .nowPlayingToolResult: return app.nowPlayingToolResult()
        case .providerModelCatalog: return app.providerModelCatalog()
        case .speechModelCatalog: return app.speechModelCatalog()
        case .localModelCatalog: return app.localModelCatalog()
        case .validateOpenrouterKey: return app.validateOpenrouterKey()
        case .validateElevenlabsKey: return app.validateElevenlabsKey()
        case .elevenlabsVoiceCatalog: return app.elevenlabsVoiceCatalog()
        case .audioReport:
            guard let requestJson else { return nil }
            return app.audioReport(requestJson: requestJson)
        case .downloadReport:
            guard let requestJson else { return nil }
            return app.downloadReport(requestJson: requestJson)
        case .httpReport:
            guard let requestJson else { return nil }
            return app.httpReport(requestJson: requestJson)
        case .itunesDirectorySearch:
            guard let requestJson else { return nil }
            return app.itunesDirectorySearch(requestJson: requestJson)
        case .itunesLookupFeedUrl:
            guard let requestJson else { return nil }
            return app.itunesLookupFeedUrl(requestJson: requestJson)
        case .itunesTopPodcasts:
            guard let requestJson else { return nil }
            return app.itunesTopPodcasts(requestJson: requestJson)
        case .threadingActiveTopics:
            guard let requestJson else { return nil }
            return app.threadingActiveTopics(requestJson: requestJson)
        case .agentInventory:
            guard let requestJson else { return nil }
            return app.agentInventory(requestJson: requestJson)
        case .agentInventoryList:
            guard let requestJson else { return nil }
            return app.agentInventoryList(requestJson: requestJson)
        case .localSearch:
            guard let requestJson else { return nil }
            return app.localSearch(requestJson: requestJson)
        case .homeContinueListening:
            guard let requestJson else { return nil }
            return app.homeContinueListening(requestJson: requestJson)
        case .homeTriageRollup:
            guard let requestJson else { return nil }
            return app.homeTriageRollup(requestJson: requestJson)
        case .homeSubscriptionList:
            guard let requestJson else { return nil }
            return app.homeSubscriptionList(requestJson: requestJson)
        case .homeCategoryCards:
            guard let requestJson else { return nil }
            return app.homeCategoryCards(requestJson: requestJson)
        case .carplayListenNow:
            guard let requestJson else { return nil }
            return app.carplayListenNow(requestJson: requestJson)
        case .carplayShows:
            guard let requestJson else { return nil }
            return app.carplayShows(requestJson: requestJson)
        case .carplayShowEpisodes:
            guard let requestJson else { return nil }
            return app.carplayShowEpisodes(requestJson: requestJson)
        case .carplayDownloads:
            guard let requestJson else { return nil }
            return app.carplayDownloads(requestJson: requestJson)
        case .libraryShowEpisodes:
            guard let requestJson else { return nil }
            return app.libraryShowEpisodes(requestJson: requestJson)
        case .libraryPodcastStats:
            guard let requestJson else { return nil }
            return app.libraryPodcastStats(requestJson: requestJson)
        case .libraryEpisodeForAudioUrl:
            guard let requestJson else { return nil }
            return app.libraryEpisodeForAudioUrl(requestJson: requestJson)
        case .libraryAllEpisodes:
            guard let requestJson else { return nil }
            return app.libraryAllEpisodes(requestJson: requestJson)
        case .libraryAllPodcasts:
            guard let requestJson else { return nil }
            return app.libraryAllPodcasts(requestJson: requestJson)
        case .libraryCategories:
            guard let requestJson else { return nil }
            return app.libraryCategories(requestJson: requestJson)
        case .libraryEpisodeLookup:
            guard let requestJson else { return nil }
            return app.libraryEpisodeLookup(requestJson: requestJson)
        case .librarySubscriptionStatus:
            guard let requestJson else { return nil }
            return app.librarySubscriptionStatus(requestJson: requestJson)
        case .libraryPodcastForOwnerPubkey:
            guard let requestJson else { return nil }
            return app.libraryPodcastForOwnerPubkey(requestJson: requestJson)
        case .libraryCategorizationParse:
            guard let requestJson else { return nil }
            return app.libraryCategorizationParse(requestJson: requestJson)
        case .libraryCategoryChange:
            guard let requestJson else { return nil }
            return app.libraryCategoryChange(requestJson: requestJson)
        case .agentChatTitlePrompt:
            guard let requestJson else { return nil }
            return app.agentChatTitlePrompt(requestJson: requestJson)
        case .agentChatTitleParse:
            guard let requestJson else { return nil }
            return app.agentChatTitleParse(requestJson: requestJson)
        case .agentNostrPeerPrompt:
            guard let requestJson else { return nil }
            return app.agentNostrPeerPrompt(requestJson: requestJson)
        case .agentSystemPrompt:
            guard let requestJson else { return nil }
            return app.agentSystemPrompt(requestJson: requestJson)
        case .agentConversationHistory:
            guard let requestJson else { return nil }
            return app.agentConversationHistory(requestJson: requestJson)
        case .agentVoiceList:
            guard let requestJson else { return nil }
            return app.agentVoiceList(requestJson: requestJson)
        case .agentYoutubeSearchPlan:
            guard let requestJson else { return nil }
            return app.agentYoutubeSearchPlan(requestJson: requestJson)
        case .agentYoutubeSearchResults:
            guard let requestJson else { return nil }
            return app.agentYoutubeSearchResults(requestJson: requestJson)
        case .agentDirectorySearchPlan:
            guard let requestJson else { return nil }
            return app.agentDirectorySearchPlan(requestJson: requestJson)
        case .agentDirectorySearchResults:
            guard let requestJson else { return nil }
            return app.agentDirectorySearchResults(requestJson: requestJson)
        case .agentCategoryList:
            guard let requestJson else { return nil }
            return app.agentCategoryList(requestJson: requestJson)
        case .agentEpisodeListPlan:
            guard let requestJson else { return nil }
            return app.agentEpisodeListPlan(requestJson: requestJson)
        case .agentEpisodeListResults:
            guard let requestJson else { return nil }
            return app.agentEpisodeListResults(requestJson: requestJson)
        case .agentEpisodeListError:
            guard let requestJson else { return nil }
            return app.agentEpisodeListError(requestJson: requestJson)
        case .agentOwnedPodcastTool:
            guard let requestJson else { return nil }
            return app.agentOwnedPodcastTool(requestJson: requestJson)
        case .agentSearchTool:
            guard let requestJson else { return nil }
            return app.agentSearchTool(requestJson: requestJson)
        case .agentActionTool:
            guard let requestJson else { return nil }
            return app.agentActionTool(requestJson: requestJson)
        case .storageBreakdown:
            guard let requestJson else { return nil }
            return app.storageBreakdown(requestJson: requestJson)
        case .agentTtsEpisodePlan:
            guard let requestJson else { return nil }
            return app.agentTtsEpisodePlan(requestJson: requestJson)
        case .agentTtsToolPlan:
            guard let requestJson else { return nil }
            return app.agentTtsToolPlan(requestJson: requestJson)
        case .agentTtsToolResult:
            guard let requestJson else { return nil }
            return app.agentTtsToolResult(requestJson: requestJson)
        case .agentVoiceConfigurePlan:
            guard let requestJson else { return nil }
            return app.agentVoiceConfigurePlan(requestJson: requestJson)
        case .agentVoiceConfigureResult:
            guard let requestJson else { return nil }
            return app.agentVoiceConfigureResult(requestJson: requestJson)
        case .voiceReport:
            guard let requestJson else { return nil }
            return app.voiceReport(requestJson: requestJson)
        case .networkReport:
            guard let requestJson else { return nil }
            return app.networkReport(requestJson: requestJson)
        case .transcriptReport:
            guard let requestJson else { return nil }
            return app.transcriptReport(requestJson: requestJson)
        case .transcriptIngestPlan:
            guard let requestJson else { return nil }
            return app.transcriptIngestPlan(requestJson: requestJson)
        case .transcriptAutoIngestCandidates:
            guard let requestJson else { return nil }
            return app.transcriptAutoIngestCandidates(requestJson: requestJson)
        case .transcriptToolResult:
            guard let requestJson else { return nil }
            return app.transcriptToolResult(requestJson: requestJson)
        case .episodeMutationToolResult:
            guard let requestJson else { return nil }
            return app.episodeMutationToolResult(requestJson: requestJson)
        case .playbackToolResult:
            guard let requestJson else { return nil }
            return app.playbackToolResult(requestJson: requestJson)
        case .externalPlayPlan:
            guard let requestJson else { return nil }
            return app.externalPlayPlan(requestJson: requestJson)
        case .agentAskEnqueue:
            guard let requestJson else { return nil }
            return app.agentAskEnqueue(requestJson: requestJson)
        case .agentAskSettle:
            guard let requestJson else { return nil }
            return app.agentAskSettle(requestJson: requestJson)
        case .memoryRememberText:
            guard let requestJson else { return nil }
            return app.memoryRememberText(requestJson: requestJson)
        case .episodeEvents:
            guard let requestJson else { return nil }
            return app.episodeEvents(requestJson: requestJson)
        case .recordEpisodeEvent:
            guard let requestJson else { return nil }
            return app.recordEpisodeEvent(requestJson: requestJson)
        case .chatComplete:
            guard let requestJson else { return nil }
            return app.chatComplete(requestJson: requestJson)
        case .providerComplete:
            guard let requestJson else { return nil }
            return app.providerComplete(requestJson: requestJson)
        case .providerEmbed:
            guard let requestJson else { return nil }
            return app.providerEmbed(requestJson: requestJson)
        case .knowledgeQuery:
            guard let requestJson else { return nil }
            return app.knowledgeQuery(requestJson: requestJson)
        case .knowledgeSimilarEpisode:
            guard let requestJson else { return nil }
            return app.knowledgeSimilarEpisode(requestJson: requestJson)
        case .knowledgeHomeRelated:
            guard let requestJson else { return nil }
            return app.knowledgeHomeRelated(requestJson: requestJson)
        case .knowledgeChunk:
            guard let requestJson else { return nil }
            return app.knowledgeChunk(requestJson: requestJson)
        case .knowledgeResolveScope:
            guard let requestJson else { return nil }
            return app.knowledgeResolveScope(requestJson: requestJson)
        case .perplexitySearch:
            guard let requestJson else { return nil }
            return app.perplexitySearch(requestJson: requestJson)
        case .byokExchange:
            guard let requestJson else { return nil }
            return app.byokExchange(requestJson: requestJson)
        case .openrouterWhisperTranscribe:
            guard let requestJson else { return nil }
            return app.openrouterWhisperTranscribe(requestJson: requestJson)
        case .elevenlabsScribeTranscribe:
            guard let requestJson else { return nil }
            return app.elevenlabsScribeTranscribe(requestJson: requestJson)
        case .assemblyaiTranscribe:
            guard let requestJson else { return nil }
            return app.assemblyaiTranscribe(requestJson: requestJson)
        case .elevenlabsTtsSynthesize:
            guard let requestJson else { return nil }
            return app.elevenlabsTtsSynthesize(requestJson: requestJson)
        case .generateImage:
            guard let requestJson else { return nil }
            return app.generateImage(requestJson: requestJson)
        case .rerank:
            guard let requestJson else { return nil }
            return app.rerank(requestJson: requestJson)
        }
    }
}

enum PodcastAppGlobalEndpoint {
    case normalizeFeedUrl
    case npubFromHex
    case parsePubkey
    case agentActionPolicy
    case byokAuthorization

    func call(requestJson: String) -> String? {
        switch self {
        case .normalizeFeedUrl: return normalizeFeedUrl(requestJson: requestJson)
        case .npubFromHex: return npubFromHex(requestJson: requestJson)
        case .parsePubkey: return parsePubkey(requestJson: requestJson)
        case .agentActionPolicy: return agentActionPolicy(requestJson: requestJson)
        case .byokAuthorization: return byokAuthorization(requestJson: requestJson)
        }
    }
}

func podcastAppString(
    _ handle: UnsafeMutableRawPointer?,
    endpoint: PodcastAppEndpoint,
    request: String? = nil
) -> String? {
    guard let app = PodcastHandle.app(for: handle) else { return nil }
    return endpoint.call(on: app, requestJson: request)
}

func podcastAppGlobalString(
    endpoint: PodcastAppGlobalEndpoint,
    request: String
) -> String? {
    endpoint.call(requestJson: request)
}

// ─── Swift-side timing wrapper ────────────────────────────────────────────

struct KernelUpdateResult {
    /// Per-domain push-frame sidecars decoded from this tick. Only domains
    /// that actually changed since the last emit are present (delta
    /// suppression). Absent domains MUST NOT overwrite prior composite state.
    let domainFrames: PodcastDomainFrames
    /// Identity slice of the kernel snapshot — `active_account` /
    /// `accounts` / `bunker_handshake` per
    /// `KernelIdentityProjection`.
    let identity: KernelIdentityProjection
    /// Top-level `store_open_failure` diagnostic (V-67). `nil` in healthy
    /// sessions; `Some(reason)` when the kernel could not open its on-disk
    /// LMDB store and fell back to in-memory (this session's data will not
    /// persist). The host MUST surface this to the user.
    let storeOpenFailure: String?
    /// Generic NMP NIP-50 search sidecars keyed by host session id.
    let nostrSearchSessions: [String: NostrSearchResultsSnapshot]
    let payloadBytes: Int
    let callbackReceivedAt: ContinuousClock.Instant
    let decodeMicros: Int
}

extension KernelUpdateResult {
    /// Extract the top-level `store_open_failure` string from a kernel snapshot
    /// wire envelope (`{"t":"snapshot","v":{...}}`). Mirrors the raw second-pass
    /// read in `KernelIdentityProjection.decode` — the typed `PodcastUpdate`
    /// decode intentionally drops this generic-snapshot key. Returns `nil` when
    /// the key is absent (healthy session) or the payload is unparseable.
    static func extractStoreOpenFailure(envelopePayload data: Data) -> String? {
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              let outer = raw as? [String: Any],
              let value = outer["v"] as? [String: Any]
        else { return nil }
        return value["store_open_failure"] as? String
    }
}

// ─── Duration microseconds helper ────────────────────────────────────────

extension Duration {
    var microseconds: Int {
        let parts = components
        return Int(parts.seconds) * 1_000_000 + Int(parts.attoseconds / 1_000_000_000_000)
    }
}
