import Foundation

// MARK: - Outbound — snapshot → iCloud

extension iCloudSyncCapability {

    /// Compare `settings` against the last value we wrote and push any
    /// changed keys to iCloud. Called from `KernelModel.applyPodcastUpdate`
    /// on every accepted kernel frame (rev-gated), so writes ride the
    /// reactive push path rather than a timer.
    func applySettingsSnapshot(_ settings: SettingsKVSnapshot) {
        guard started else { return }
        if isApplyingRemoteChange {
            // Single-tick suppression. Seed `lastWritten` with the
            // kernel's view so the next genuine local edit *is* written.
            isApplyingRemoteChange = false
            appStore?.isApplyingRemoteChange = false
            settings.write(to: &lastWritten)
            return
        }
        if let v = settings.speed,
           lastWritten[Key.speed] != AnyHashable(v) {
            kvs.set(v, forKey: Key.speed)
            lastWritten[Key.speed] = AnyHashable(v)
        }
        if let v = settings.skipForwardSecs,
           lastWritten[Key.skipForwardSecs] != AnyHashable(v) {
            kvs.set(Int64(v), forKey: Key.skipForwardSecs)
            lastWritten[Key.skipForwardSecs] = AnyHashable(v)
        }
        if let v = settings.skipBackwardSecs,
           lastWritten[Key.skipBackwardSecs] != AnyHashable(v) {
            kvs.set(Int64(v), forKey: Key.skipBackwardSecs)
            lastWritten[Key.skipBackwardSecs] = AnyHashable(v)
        }
        if let v = settings.autoSkipAds,
           lastWritten[Key.autoSkipAds] != AnyHashable(v) {
            kvs.set(v, forKey: Key.autoSkipAds)
            lastWritten[Key.autoSkipAds] = AnyHashable(v)
        }
        if let v = settings.autoDeleteDownloadsAfterPlayed,
           lastWritten[Key.autoDeleteDownloadsAfterPlayed] != AnyHashable(v) {
            kvs.set(v, forKey: Key.autoDeleteDownloadsAfterPlayed)
            lastWritten[Key.autoDeleteDownloadsAfterPlayed] = AnyHashable(v)
        }
        if let v = settings.agentInitialModel,
           lastWritten[Key.agentInitialModel] != AnyHashable(v) {
            kvs.set(v, forKey: Key.agentInitialModel)
            lastWritten[Key.agentInitialModel] = AnyHashable(v)
        }
        if let v = settings.agentInitialModelName,
           lastWritten[Key.agentInitialModelName] != AnyHashable(v) {
            kvs.set(v, forKey: Key.agentInitialModelName)
            lastWritten[Key.agentInitialModelName] = AnyHashable(v)
        }
        if let v = settings.agentThinkingModel,
           lastWritten[Key.agentThinkingModel] != AnyHashable(v) {
            kvs.set(v, forKey: Key.agentThinkingModel)
            lastWritten[Key.agentThinkingModel] = AnyHashable(v)
        }
        if let v = settings.agentThinkingModelName,
           lastWritten[Key.agentThinkingModelName] != AnyHashable(v) {
            kvs.set(v, forKey: Key.agentThinkingModelName)
            lastWritten[Key.agentThinkingModelName] = AnyHashable(v)
        }
        if let v = settings.memoryCompilationModel,
           lastWritten[Key.memoryCompilationModel] != AnyHashable(v) {
            kvs.set(v, forKey: Key.memoryCompilationModel)
            lastWritten[Key.memoryCompilationModel] = AnyHashable(v)
        }
        if let v = settings.memoryCompilationModelName,
           lastWritten[Key.memoryCompilationModelName] != AnyHashable(v) {
            kvs.set(v, forKey: Key.memoryCompilationModelName)
            lastWritten[Key.memoryCompilationModelName] = AnyHashable(v)
        }
        if let v = settings.categorizationModel,
           lastWritten[Key.categorizationModel] != AnyHashable(v) {
            kvs.set(v, forKey: Key.categorizationModel)
            lastWritten[Key.categorizationModel] = AnyHashable(v)
        }
        if let v = settings.categorizationModelName,
           lastWritten[Key.categorizationModelName] != AnyHashable(v) {
            kvs.set(v, forKey: Key.categorizationModelName)
            lastWritten[Key.categorizationModelName] = AnyHashable(v)
        }
        if let v = settings.chapterCompilationModel,
           lastWritten[Key.chapterCompilationModel] != AnyHashable(v) {
            kvs.set(v, forKey: Key.chapterCompilationModel)
            lastWritten[Key.chapterCompilationModel] = AnyHashable(v)
        }
        if let v = settings.chapterCompilationModelName,
           lastWritten[Key.chapterCompilationModelName] != AnyHashable(v) {
            kvs.set(v, forKey: Key.chapterCompilationModelName)
            lastWritten[Key.chapterCompilationModelName] = AnyHashable(v)
        }
        if let v = settings.embeddingsModel,
           lastWritten[Key.embeddingsModel] != AnyHashable(v) {
            kvs.set(v, forKey: Key.embeddingsModel)
            lastWritten[Key.embeddingsModel] = AnyHashable(v)
        }
        if let v = settings.embeddingsModelName,
           lastWritten[Key.embeddingsModelName] != AnyHashable(v) {
            kvs.set(v, forKey: Key.embeddingsModelName)
            lastWritten[Key.embeddingsModelName] = AnyHashable(v)
        }
        if let v = settings.imageGenerationModel,
           lastWritten[Key.imageGenerationModel] != AnyHashable(v) {
            kvs.set(v, forKey: Key.imageGenerationModel)
            lastWritten[Key.imageGenerationModel] = AnyHashable(v)
        }
        if let v = settings.imageGenerationModelName,
           lastWritten[Key.imageGenerationModelName] != AnyHashable(v) {
            kvs.set(v, forKey: Key.imageGenerationModelName)
            lastWritten[Key.imageGenerationModelName] = AnyHashable(v)
        }
        if let v = settings.rerankerEnabled,
           lastWritten[Key.rerankerEnabled] != AnyHashable(v) {
            kvs.set(v, forKey: Key.rerankerEnabled)
            lastWritten[Key.rerankerEnabled] = AnyHashable(v)
        }
        if let v = settings.ollamaChatUrl,
           lastWritten[Key.ollamaChatUrl] != AnyHashable(v) {
            kvs.set(v, forKey: Key.ollamaChatUrl)
            lastWritten[Key.ollamaChatUrl] = AnyHashable(v)
        }
        if let v = settings.sttProvider,
           lastWritten[Key.sttProvider] != AnyHashable(v) {
            kvs.set(v, forKey: Key.sttProvider)
            lastWritten[Key.sttProvider] = AnyHashable(v)
        }
        if let v = settings.openRouterWhisperModel,
           lastWritten[Key.openRouterWhisperModel] != AnyHashable(v) {
            kvs.set(v, forKey: Key.openRouterWhisperModel)
            lastWritten[Key.openRouterWhisperModel] = AnyHashable(v)
        }
        if let v = settings.assemblyAiSttModel,
           lastWritten[Key.assemblyAiSttModel] != AnyHashable(v) {
            kvs.set(v, forKey: Key.assemblyAiSttModel)
            lastWritten[Key.assemblyAiSttModel] = AnyHashable(v)
        }
        if let v = settings.elevenLabsSttModel,
           lastWritten[Key.elevenLabsSttModel] != AnyHashable(v) {
            kvs.set(v, forKey: Key.elevenLabsSttModel)
            lastWritten[Key.elevenLabsSttModel] = AnyHashable(v)
        }
        if let v = settings.elevenLabsTtsModel,
           lastWritten[Key.elevenLabsTtsModel] != AnyHashable(v) {
            kvs.set(v, forKey: Key.elevenLabsTtsModel)
            lastWritten[Key.elevenLabsTtsModel] = AnyHashable(v)
        }
        if let v = settings.elevenLabsVoiceId,
           lastWritten[Key.elevenLabsVoiceId] != AnyHashable(v) {
            kvs.set(v, forKey: Key.elevenLabsVoiceId)
            lastWritten[Key.elevenLabsVoiceId] = AnyHashable(v)
        }
        if let v = settings.elevenLabsVoiceName,
           lastWritten[Key.elevenLabsVoiceName] != AnyHashable(v) {
            kvs.set(v, forKey: Key.elevenLabsVoiceName)
            lastWritten[Key.elevenLabsVoiceName] = AnyHashable(v)
        }
        if let v = settings.blossomServerUrl,
           lastWritten[Key.blossomServerUrl] != AnyHashable(v) {
            kvs.set(v, forKey: Key.blossomServerUrl)
            lastWritten[Key.blossomServerUrl] = AnyHashable(v)
        }
        if let v = settings.youtubeExtractorUrl,
           lastWritten[Key.youtubeExtractorUrl] != AnyHashable(v) {
            kvs.set(v, forKey: Key.youtubeExtractorUrl)
            lastWritten[Key.youtubeExtractorUrl] = AnyHashable(v)
        }
        if let v = settings.autoMarkPlayedAtEnd,
           lastWritten[Key.autoMarkPlayedAtEnd] != AnyHashable(v) {
            kvs.set(v, forKey: Key.autoMarkPlayedAtEnd)
            lastWritten[Key.autoMarkPlayedAtEnd] = AnyHashable(v)
        }
        if let v = settings.autoPlayNext,
           lastWritten[Key.autoPlayNext] != AnyHashable(v) {
            kvs.set(v, forKey: Key.autoPlayNext)
            lastWritten[Key.autoPlayNext] = AnyHashable(v)
        }
        if let v = settings.headphoneDoubleTapAction,
           lastWritten[Key.headphoneDoubleTapAction] != AnyHashable(v) {
            kvs.set(v, forKey: Key.headphoneDoubleTapAction)
            lastWritten[Key.headphoneDoubleTapAction] = AnyHashable(v)
        }
        if let v = settings.headphoneTripleTapAction,
           lastWritten[Key.headphoneTripleTapAction] != AnyHashable(v) {
            kvs.set(v, forKey: Key.headphoneTripleTapAction)
            lastWritten[Key.headphoneTripleTapAction] = AnyHashable(v)
        }
        if let v = settings.autoIngestPublisherTranscripts,
           lastWritten[Key.autoIngestPublisherTranscripts] != AnyHashable(v) {
            kvs.set(v, forKey: Key.autoIngestPublisherTranscripts)
            lastWritten[Key.autoIngestPublisherTranscripts] = AnyHashable(v)
        }
        if let v = settings.autoFallbackToScribe,
           lastWritten[Key.autoFallbackToScribe] != AnyHashable(v) {
            kvs.set(v, forKey: Key.autoFallbackToScribe)
            lastWritten[Key.autoFallbackToScribe] = AnyHashable(v)
        }
        if let v = settings.notifyOnNewEpisodes,
           lastWritten[Key.notifyOnNewEpisodes] != AnyHashable(v) {
            kvs.set(v, forKey: Key.notifyOnNewEpisodes)
            lastWritten[Key.notifyOnNewEpisodes] = AnyHashable(v)
        }
        if let v = settings.nostrRelayUrl,
           lastWritten[Key.nostrRelayUrl] != AnyHashable(v) {
            kvs.set(v, forKey: Key.nostrRelayUrl)
            lastWritten[Key.nostrRelayUrl] = AnyHashable(v)
        }
        if let v = settings.nostrProfileName,
           lastWritten[Key.nostrProfileName] != AnyHashable(v) {
            kvs.set(v, forKey: Key.nostrProfileName)
            lastWritten[Key.nostrProfileName] = AnyHashable(v)
        }
        if let v = settings.nostrProfileAbout,
           lastWritten[Key.nostrProfileAbout] != AnyHashable(v) {
            kvs.set(v, forKey: Key.nostrProfileAbout)
            lastWritten[Key.nostrProfileAbout] = AnyHashable(v)
        }
        if let v = settings.nostrProfilePicture,
           lastWritten[Key.nostrProfilePicture] != AnyHashable(v) {
            kvs.set(v, forKey: Key.nostrProfilePicture)
            lastWritten[Key.nostrProfilePicture] = AnyHashable(v)
        }
    }
}
