//! App-owned UniFFI endpoint methods for agent, provider, and capability reports.

use std::sync::Arc;

use super::uniffi_facade::{PodcastAgentAskSink, PodcastApp};
use super::uniffi_facade_legacy_support::call_legacy_handle_json;

#[uniffi::export]
impl PodcastApp {
    pub fn agent_chat_title_prompt(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_chat_title_prompt,
            )
        })
    }

    pub fn agent_chat_title_parse(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_chat_title_parse,
            )
        })
    }

    pub fn agent_nostr_peer_prompt(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_nostr_peer_prompt,
            )
        })
    }

    pub fn agent_system_prompt(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_system_prompt,
            )
        })
    }

    pub fn agent_conversation_history(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_conversation_history,
            )
        })
    }

    pub fn agent_voice_list(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_voice_list,
            )
        })
    }

    pub fn agent_youtube_search_plan(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_youtube_search_plan,
            )
        })
    }

    pub fn agent_youtube_search_results(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_youtube_search_results,
            )
        })
    }

    pub fn agent_directory_search_plan(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_directory_search_plan,
            )
        })
    }

    pub fn agent_directory_search_results(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_directory_search_results,
            )
        })
    }

    pub fn agent_category_list(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_category_list,
            )
        })
    }

    pub fn agent_episode_list_plan(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_episode_list_plan,
            )
        })
    }

    pub fn agent_episode_list_results(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_episode_list_results,
            )
        })
    }

    pub fn agent_episode_list_error(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_episode_list_error,
            )
        })
    }

    pub fn agent_owned_podcast_tool(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_owned_podcast_tool,
            )
        })
    }

    pub fn agent_search_tool(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_search_tool,
            )
        })
    }

    pub fn agent_action_tool(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_action_tool,
            )
        })
    }

    pub fn storage_breakdown(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_storage_breakdown,
            )
        })
    }

    pub fn agent_tts_episode_plan(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_tts_episode_plan,
            )
        })
    }

    pub fn agent_tts_tool_plan(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_tts_tool_plan,
            )
        })
    }

    pub fn agent_tts_tool_result(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_tts_tool_result,
            )
        })
    }

    pub fn agent_voice_configure_plan(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_voice_configure_plan,
            )
        })
    }

    pub fn agent_voice_configure_result(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_voice_configure_result,
            )
        })
    }

    pub fn voice_report(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(handle, &request_json, super::nmp_app_podcast_voice_report)
        })
    }

    pub fn network_report(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(handle, &request_json, super::nmp_app_podcast_network_report)
        })
    }

    pub fn transcript_report(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_transcript_report,
            )
        })
    }

    pub fn transcript_ingest_plan(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_transcript_ingest_plan,
            )
        })
    }

    pub fn transcript_auto_ingest_candidates(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_transcript_auto_ingest_candidates,
            )
        })
    }

    pub fn transcript_tool_result(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_transcript_tool_result,
            )
        })
    }

    pub fn episode_mutation_tool_result(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_episode_mutation_tool_result,
            )
        })
    }

    pub fn playback_tool_result(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_playback_tool_result,
            )
        })
    }

    pub fn external_play_plan(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_external_play_plan,
            )
        })
    }

    pub fn agent_ask_enqueue(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_ask_enqueue,
            )
        })
    }

    pub fn agent_ask_settle(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_ask_settle,
            )
        })
    }

    pub fn memory_remember_text(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_memory_remember_text,
            )
        })
    }

    pub fn episode_events(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(handle, &request_json, super::nmp_app_podcast_episode_events)
        })
    }

    pub fn record_episode_event(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_record_episode_event,
            )
        })
    }

    pub fn set_agent_ask_sink(&self, sink: Option<Box<dyn PodcastAgentAskSink>>) {
        let Some(handle) = self.podcast_handle_for_uniffi() else {
            return;
        };
        let callback = sink.map(|sink| {
            Arc::new(move |event_json: String| {
                sink.on_agent_ask_event(event_json);
            }) as super::agent_ask::AgentAskCallback
        });
        super::agent_ask::set_agent_ask_callback(handle, callback);
    }
}
