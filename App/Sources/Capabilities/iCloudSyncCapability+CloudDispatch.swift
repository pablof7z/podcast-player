import Foundation

// MARK: - Shared cloud→kernel dispatch

extension iCloudSyncCapability {

    /// Shared dispatch path used by both the on-launch merge and the
    /// external-change observer. Skip-interval requires both values
    /// together (the action takes `forward` + `backward`) so the two
    /// keys are coalesced into a single dispatch.
    ///
    /// Dispatched via `KernelModel.dispatchSilent` — a rejection from a
    /// not-yet-wired Rust action should not surface as a user toast.
    ///
    /// Widened from `private` to `internal` (default) so
    /// `handleExternalChange` and `start` in the core file can call it
    /// across file boundaries.
    func dispatchKeysFromCloud(_ keys: [String]) {
        let touched = Set(keys)
        var didDispatch = false
        // Set the echo-suppression flag on the app store so updateSettings
        // does not re-dispatch the same values back to the kernel.
        appStore?.isApplyingRemoteChange = true

        if touched.contains(Key.skipForwardSecs) || touched.contains(Key.skipBackwardSecs),
           let forward = (kvs.object(forKey: Key.skipForwardSecs) as? NSNumber)?.intValue,
           let backward = (kvs.object(forKey: Key.skipBackwardSecs) as? NSNumber)?.intValue,
           lastWritten[Key.skipForwardSecs] != AnyHashable(forward)
             || lastWritten[Key.skipBackwardSecs] != AnyHashable(backward) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings", body: [
                "op": "set_skip_intervals",
                "forward_secs": Double(forward),
                "backward_secs": Double(backward),
            ])
            lastWritten[Key.skipForwardSecs] = AnyHashable(forward)
            lastWritten[Key.skipBackwardSecs] = AnyHashable(backward)
            didDispatch = true
        }

        if touched.contains(Key.autoSkipAds),
           let enabled = (kvs.object(forKey: Key.autoSkipAds) as? NSNumber)?.boolValue,
           lastWritten[Key.autoSkipAds] != AnyHashable(enabled) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings",
                                   body: ["op": "set_auto_skip_ads", "enabled": enabled])
            lastWritten[Key.autoSkipAds] = AnyHashable(enabled)
            didDispatch = true
        }

        if touched.contains(Key.speed),
           let speed = (kvs.object(forKey: Key.speed) as? NSNumber)?.doubleValue,
           lastWritten[Key.speed] != AnyHashable(speed) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings",
                                   body: ["op": "set_default_playback_rate", "rate": speed])
            lastWritten[Key.speed] = AnyHashable(speed)
            didDispatch = true
        }

        if touched.contains(Key.autoDeleteDownloadsAfterPlayed),
           let enabled = (kvs.object(forKey: Key.autoDeleteDownloadsAfterPlayed) as? NSNumber)?.boolValue,
           lastWritten[Key.autoDeleteDownloadsAfterPlayed] != AnyHashable(enabled) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings",
                                   body: ["op": "set_auto_delete_downloads_after_played", "enabled": enabled])
            lastWritten[Key.autoDeleteDownloadsAfterPlayed] = AnyHashable(enabled)
            didDispatch = true
        }

        if touched.contains(Key.agentInitialModel) || touched.contains(Key.agentInitialModelName),
           let model = (kvs.object(forKey: Key.agentInitialModel) as? String),
           let modelName = (kvs.object(forKey: Key.agentInitialModelName) as? String),
           lastWritten[Key.agentInitialModel] != AnyHashable(model)
             || lastWritten[Key.agentInitialModelName] != AnyHashable(modelName) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings", body: [
                "op": "set_agent_initial_model",
                "model": model,
                "model_name": modelName,
            ])
            lastWritten[Key.agentInitialModel] = AnyHashable(model)
            lastWritten[Key.agentInitialModelName] = AnyHashable(modelName)
            didDispatch = true
        }

        if touched.contains(Key.agentThinkingModel) || touched.contains(Key.agentThinkingModelName),
           let model = (kvs.object(forKey: Key.agentThinkingModel) as? String),
           let modelName = (kvs.object(forKey: Key.agentThinkingModelName) as? String),
           lastWritten[Key.agentThinkingModel] != AnyHashable(model)
             || lastWritten[Key.agentThinkingModelName] != AnyHashable(modelName) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings", body: [
                "op": "set_agent_thinking_model",
                "model": model,
                "model_name": modelName,
            ])
            lastWritten[Key.agentThinkingModel] = AnyHashable(model)
            lastWritten[Key.agentThinkingModelName] = AnyHashable(modelName)
            didDispatch = true
        }

        if touched.contains(Key.memoryCompilationModel) || touched.contains(Key.memoryCompilationModelName),
           let model = (kvs.object(forKey: Key.memoryCompilationModel) as? String),
           let modelName = (kvs.object(forKey: Key.memoryCompilationModelName) as? String),
           lastWritten[Key.memoryCompilationModel] != AnyHashable(model)
             || lastWritten[Key.memoryCompilationModelName] != AnyHashable(modelName) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings", body: [
                "op": "set_memory_compilation_model",
                "model": model,
                "model_name": modelName,
            ])
            lastWritten[Key.memoryCompilationModel] = AnyHashable(model)
            lastWritten[Key.memoryCompilationModelName] = AnyHashable(modelName)
            didDispatch = true
        }

        if touched.contains(Key.categorizationModel) || touched.contains(Key.categorizationModelName),
           let model = (kvs.object(forKey: Key.categorizationModel) as? String),
           let modelName = (kvs.object(forKey: Key.categorizationModelName) as? String),
           lastWritten[Key.categorizationModel] != AnyHashable(model)
             || lastWritten[Key.categorizationModelName] != AnyHashable(modelName) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings", body: [
                "op": "set_categorization_model",
                "model": model,
                "model_name": modelName,
            ])
            lastWritten[Key.categorizationModel] = AnyHashable(model)
            lastWritten[Key.categorizationModelName] = AnyHashable(modelName)
            didDispatch = true
        }

        if touched.contains(Key.chapterCompilationModel) || touched.contains(Key.chapterCompilationModelName),
           let model = (kvs.object(forKey: Key.chapterCompilationModel) as? String),
           let modelName = (kvs.object(forKey: Key.chapterCompilationModelName) as? String),
           lastWritten[Key.chapterCompilationModel] != AnyHashable(model)
             || lastWritten[Key.chapterCompilationModelName] != AnyHashable(modelName) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings", body: [
                "op": "set_chapter_compilation_model",
                "model": model,
                "model_name": modelName,
            ])
            lastWritten[Key.chapterCompilationModel] = AnyHashable(model)
            lastWritten[Key.chapterCompilationModelName] = AnyHashable(modelName)
            didDispatch = true
        }

        if touched.contains(Key.embeddingsModel) || touched.contains(Key.embeddingsModelName),
           let model = (kvs.object(forKey: Key.embeddingsModel) as? String),
           let modelName = (kvs.object(forKey: Key.embeddingsModelName) as? String),
           lastWritten[Key.embeddingsModel] != AnyHashable(model)
             || lastWritten[Key.embeddingsModelName] != AnyHashable(modelName) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings", body: [
                "op": "set_embeddings_model",
                "model": model,
                "model_name": modelName,
            ])
            lastWritten[Key.embeddingsModel] = AnyHashable(model)
            lastWritten[Key.embeddingsModelName] = AnyHashable(modelName)
            didDispatch = true
        }

        if touched.contains(Key.imageGenerationModel) || touched.contains(Key.imageGenerationModelName),
           let model = (kvs.object(forKey: Key.imageGenerationModel) as? String),
           let modelName = (kvs.object(forKey: Key.imageGenerationModelName) as? String),
           lastWritten[Key.imageGenerationModel] != AnyHashable(model)
             || lastWritten[Key.imageGenerationModelName] != AnyHashable(modelName) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings", body: [
                "op": "set_image_generation_model",
                "model": model,
                "model_name": modelName,
            ])
            lastWritten[Key.imageGenerationModel] = AnyHashable(model)
            lastWritten[Key.imageGenerationModelName] = AnyHashable(modelName)
            didDispatch = true
        }

        if touched.contains(Key.rerankerEnabled),
           let enabled = (kvs.object(forKey: Key.rerankerEnabled) as? NSNumber)?.boolValue,
           lastWritten[Key.rerankerEnabled] != AnyHashable(enabled) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings",
                                   body: ["op": "set_reranker_enabled", "enabled": enabled])
            lastWritten[Key.rerankerEnabled] = AnyHashable(enabled)
            didDispatch = true
        }

        if touched.contains(Key.ollamaChatUrl),
           let url = (kvs.object(forKey: Key.ollamaChatUrl) as? String),
           lastWritten[Key.ollamaChatUrl] != AnyHashable(url) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings",
                                   body: ["op": "set_ollama_chat_url", "url": url])
            lastWritten[Key.ollamaChatUrl] = AnyHashable(url)
            didDispatch = true
        }

        if touched.contains(Key.sttProvider),
           let provider = (kvs.object(forKey: Key.sttProvider) as? String),
           lastWritten[Key.sttProvider] != AnyHashable(provider) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings",
                                   body: ["op": "set_stt_provider", "provider": provider])
            lastWritten[Key.sttProvider] = AnyHashable(provider)
            didDispatch = true
        }

        if touched.contains(Key.openRouterWhisperModel),
           let model = (kvs.object(forKey: Key.openRouterWhisperModel) as? String),
           lastWritten[Key.openRouterWhisperModel] != AnyHashable(model) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings",
                                   body: ["op": "set_open_router_whisper_model", "model": model])
            lastWritten[Key.openRouterWhisperModel] = AnyHashable(model)
            didDispatch = true
        }

        if touched.contains(Key.assemblyAiSttModel),
           let model = (kvs.object(forKey: Key.assemblyAiSttModel) as? String),
           lastWritten[Key.assemblyAiSttModel] != AnyHashable(model) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings",
                                   body: ["op": "set_assembly_ai_stt_model", "model": model])
            lastWritten[Key.assemblyAiSttModel] = AnyHashable(model)
            didDispatch = true
        }

        if touched.contains(Key.elevenLabsSttModel) || touched.contains(Key.elevenLabsTtsModel),
           let sttModel = (kvs.object(forKey: Key.elevenLabsSttModel) as? String),
           let ttsModel = (kvs.object(forKey: Key.elevenLabsTtsModel) as? String),
           lastWritten[Key.elevenLabsSttModel] != AnyHashable(sttModel)
             || lastWritten[Key.elevenLabsTtsModel] != AnyHashable(ttsModel) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings", body: [
                "op": "set_eleven_labs_models",
                "stt_model": sttModel,
                "tts_model": ttsModel,
            ])
            lastWritten[Key.elevenLabsSttModel] = AnyHashable(sttModel)
            lastWritten[Key.elevenLabsTtsModel] = AnyHashable(ttsModel)
            didDispatch = true
        }

        if touched.contains(Key.elevenLabsVoiceId) || touched.contains(Key.elevenLabsVoiceName),
           let voiceId = (kvs.object(forKey: Key.elevenLabsVoiceId) as? String),
           let voiceName = (kvs.object(forKey: Key.elevenLabsVoiceName) as? String),
           lastWritten[Key.elevenLabsVoiceId] != AnyHashable(voiceId)
             || lastWritten[Key.elevenLabsVoiceName] != AnyHashable(voiceName) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings", body: [
                "op": "set_eleven_labs_voice",
                "voice_id": voiceId,
                "voice_name": voiceName,
            ])
            lastWritten[Key.elevenLabsVoiceId] = AnyHashable(voiceId)
            lastWritten[Key.elevenLabsVoiceName] = AnyHashable(voiceName)
            didDispatch = true
        }

        if touched.contains(Key.blossomServerUrl),
           let url = (kvs.object(forKey: Key.blossomServerUrl) as? String),
           lastWritten[Key.blossomServerUrl] != AnyHashable(url) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings",
                                   body: ["op": "set_blossom_server_url", "url": url])
            lastWritten[Key.blossomServerUrl] = AnyHashable(url)
            didDispatch = true
        }

        if touched.contains(Key.youtubeExtractorUrl),
           let url = (kvs.object(forKey: Key.youtubeExtractorUrl) as? String?) ?? (nil as String?),
           lastWritten[Key.youtubeExtractorUrl] != AnyHashable(url) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings",
                                   body: ["op": "set_youtube_extractor_url", "url": url as Any])
            lastWritten[Key.youtubeExtractorUrl] = AnyHashable(url)
            didDispatch = true
        }

        if touched.contains(Key.autoMarkPlayedAtEnd),
           let enabled = (kvs.object(forKey: Key.autoMarkPlayedAtEnd) as? NSNumber)?.boolValue,
           lastWritten[Key.autoMarkPlayedAtEnd] != AnyHashable(enabled) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings",
                                   body: ["op": "set_auto_mark_played_at_end", "enabled": enabled])
            lastWritten[Key.autoMarkPlayedAtEnd] = AnyHashable(enabled)
            didDispatch = true
        }

        if touched.contains(Key.autoPlayNext),
           let enabled = (kvs.object(forKey: Key.autoPlayNext) as? NSNumber)?.boolValue,
           lastWritten[Key.autoPlayNext] != AnyHashable(enabled) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings",
                                   body: ["op": "set_auto_play_next", "enabled": enabled])
            lastWritten[Key.autoPlayNext] = AnyHashable(enabled)
            didDispatch = true
        }

        if touched.contains(Key.headphoneDoubleTapAction) || touched.contains(Key.headphoneTripleTapAction),
           let doubleTap = (kvs.object(forKey: Key.headphoneDoubleTapAction) as? String),
           let tripleTap = (kvs.object(forKey: Key.headphoneTripleTapAction) as? String),
           lastWritten[Key.headphoneDoubleTapAction] != AnyHashable(doubleTap)
             || lastWritten[Key.headphoneTripleTapAction] != AnyHashable(tripleTap) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings", body: [
                "op": "set_headphone_gesture_actions",
                "double_tap": doubleTap,
                "triple_tap": tripleTap,
            ])
            lastWritten[Key.headphoneDoubleTapAction] = AnyHashable(doubleTap)
            lastWritten[Key.headphoneTripleTapAction] = AnyHashable(tripleTap)
            didDispatch = true
        }

        if touched.contains(Key.autoIngestPublisherTranscripts),
           let enabled = (kvs.object(forKey: Key.autoIngestPublisherTranscripts) as? NSNumber)?.boolValue,
           lastWritten[Key.autoIngestPublisherTranscripts] != AnyHashable(enabled) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings",
                                   body: ["op": "set_auto_ingest_publisher_transcripts", "enabled": enabled])
            lastWritten[Key.autoIngestPublisherTranscripts] = AnyHashable(enabled)
            didDispatch = true
        }

        if touched.contains(Key.autoFallbackToScribe),
           let enabled = (kvs.object(forKey: Key.autoFallbackToScribe) as? NSNumber)?.boolValue,
           lastWritten[Key.autoFallbackToScribe] != AnyHashable(enabled) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings",
                                   body: ["op": "set_auto_fallback_to_scribe", "enabled": enabled])
            lastWritten[Key.autoFallbackToScribe] = AnyHashable(enabled)
            didDispatch = true
        }

        if touched.contains(Key.notifyOnNewEpisodes),
           let enabled = (kvs.object(forKey: Key.notifyOnNewEpisodes) as? NSNumber)?.boolValue,
           lastWritten[Key.notifyOnNewEpisodes] != AnyHashable(enabled) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings",
                                   body: ["op": "set_notify_on_new_episodes", "enabled": enabled])
            lastWritten[Key.notifyOnNewEpisodes] = AnyHashable(enabled)
            didDispatch = true
        }

        if touched.contains(Key.nostrRelayUrl),
           let url = (kvs.object(forKey: Key.nostrRelayUrl) as? String),
           lastWritten[Key.nostrRelayUrl] != AnyHashable(url) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings",
                                   body: ["op": "set_nostr_relay_url", "url": url])
            lastWritten[Key.nostrRelayUrl] = AnyHashable(url)
            didDispatch = true
        }

        if touched.contains(Key.nostrProfileName) || touched.contains(Key.nostrProfileAbout) || touched.contains(Key.nostrProfilePicture),
           let name = (kvs.object(forKey: Key.nostrProfileName) as? String),
           let about = (kvs.object(forKey: Key.nostrProfileAbout) as? String),
           let picture = (kvs.object(forKey: Key.nostrProfilePicture) as? String),
           lastWritten[Key.nostrProfileName] != AnyHashable(name)
             || lastWritten[Key.nostrProfileAbout] != AnyHashable(about)
             || lastWritten[Key.nostrProfilePicture] != AnyHashable(picture) {
            isApplyingRemoteChange = true
            kernel?.dispatchSilent(namespace: "podcast.settings", body: [
                "op": "set_nostr_profile",
                "name": name,
                "about": about,
                "picture": picture,
            ])
            lastWritten[Key.nostrProfileName] = AnyHashable(name)
            lastWritten[Key.nostrProfileAbout] = AnyHashable(about)
            lastWritten[Key.nostrProfilePicture] = AnyHashable(picture)
            didDispatch = true
        }

        // Nothing actually dispatched → no kernel echo to suppress; reset
        // the flag so the next outbound tick is not swallowed.
        if !didDispatch {
            isApplyingRemoteChange = false
            appStore?.isApplyingRemoteChange = false
        }
    }
}
