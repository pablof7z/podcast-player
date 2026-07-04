//! App-owned UniFFI endpoint methods for provider, knowledge, and media tools.

use super::uniffi_facade::PodcastApp;
use super::uniffi_facade_legacy_support::call_legacy_handle_json;

#[uniffi::export]
impl PodcastApp {
    pub fn chat_complete(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(handle, &request_json, super::nmp_app_podcast_chat_complete)
        })
    }

    pub fn provider_complete(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_provider_complete,
            )
        })
    }

    pub fn provider_embed(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(handle, &request_json, super::nmp_app_podcast_provider_embed)
        })
    }

    pub fn knowledge_query(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().map(|handle| {
            super::knowledge_query::knowledge_query_json(Some(handle), Some(&request_json))
        })
    }

    pub fn knowledge_similar_episode(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_knowledge_similar_episode,
            )
        })
    }

    pub fn knowledge_home_related(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_knowledge_home_related,
            )
        })
    }

    pub fn knowledge_chunk(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().map(|handle| {
            super::knowledge_query::knowledge_chunk_json(Some(handle), Some(&request_json))
        })
    }

    pub fn knowledge_resolve_scope(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_knowledge_resolve_scope,
            )
        })
    }

    pub fn perplexity_search(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_perplexity_search,
            )
        })
    }

    pub fn byok_exchange(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(handle, &request_json, super::nmp_app_podcast_byok_exchange)
        })
    }

    pub fn openrouter_whisper_transcribe(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_openrouter_whisper_transcribe,
            )
        })
    }

    pub fn elevenlabs_scribe_transcribe(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_elevenlabs_scribe_transcribe,
            )
        })
    }

    pub fn assemblyai_transcribe(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_assemblyai_transcribe,
            )
        })
    }

    pub fn elevenlabs_tts_synthesize(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_elevenlabs_tts_synthesize,
            )
        })
    }

    pub fn generate_image(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(handle, &request_json, super::nmp_app_podcast_generate_image)
        })
    }

    pub fn rerank(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(handle, &request_json, super::nmp_app_podcast_rerank)
        })
    }
}
