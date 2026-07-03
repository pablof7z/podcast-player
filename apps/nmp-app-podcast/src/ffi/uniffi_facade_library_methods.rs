//! App-owned UniFFI endpoint methods for projections and view data.

use super::uniffi_facade::PodcastApp;
use super::uniffi_facade_legacy_support::{call_legacy_handle, call_legacy_handle_json};

#[uniffi::export]
impl PodcastApp {
    pub fn threading_projection(&self) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle(handle, super::nmp_app_podcast_threading_projection)
        })
    }

    pub fn agent_empty_state(&self) -> Option<String> {
        self.podcast_handle_for_uniffi()
            .and_then(|handle| call_legacy_handle(handle, super::nmp_app_podcast_agent_empty_state))
    }

    pub fn library_summary(&self) -> Option<String> {
        self.podcast_handle_for_uniffi()
            .and_then(|handle| call_legacy_handle(handle, super::nmp_app_podcast_library_summary))
    }

    pub fn library_followed_podcasts(&self) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle(handle, super::nmp_app_podcast_library_followed_podcasts)
        })
    }

    pub fn library_owned_podcasts(&self) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle(handle, super::nmp_app_podcast_library_owned_podcasts)
        })
    }

    pub fn library_download_rows(&self) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle(handle, super::nmp_app_podcast_library_download_rows)
        })
    }

    pub fn library_starred_episodes(&self) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle(handle, super::nmp_app_podcast_library_starred_episodes)
        })
    }

    pub fn library_categorization_prompt(&self) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle(handle, super::nmp_app_podcast_library_categorization_prompt)
        })
    }

    pub fn agent_tts_default_voice(&self) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle(handle, super::nmp_app_podcast_agent_tts_default_voice)
        })
    }

    pub fn agent_generated_podcast_descriptor(&self) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle(
                handle,
                super::nmp_app_podcast_agent_generated_podcast_descriptor,
            )
        })
    }

    pub fn now_playing_tool_result(&self) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle(handle, super::nmp_app_podcast_now_playing_tool_result)
        })
    }

    pub fn provider_model_catalog(&self) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle(handle, super::nmp_app_podcast_provider_model_catalog)
        })
    }

    pub fn speech_model_catalog(&self) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle(handle, super::nmp_app_podcast_speech_model_catalog)
        })
    }

    pub fn local_model_catalog(&self) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle(handle, super::nmp_app_podcast_local_model_catalog)
        })
    }

    pub fn validate_openrouter_key(&self) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle(handle, super::nmp_app_podcast_validate_openrouter_key)
        })
    }

    pub fn validate_elevenlabs_key(&self) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle(handle, super::nmp_app_podcast_validate_elevenlabs_key)
        })
    }

    pub fn elevenlabs_voice_catalog(&self) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle(handle, super::nmp_app_podcast_elevenlabs_voice_catalog)
        })
    }

    pub fn audio_report(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(handle, &request_json, super::nmp_app_podcast_audio_report)
        })
    }

    pub fn download_report(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_download_report,
            )
        })
    }

    pub fn http_report(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(handle, &request_json, super::nmp_app_podcast_http_report)
        })
    }

    pub fn itunes_directory_search(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_itunes_directory_search,
            )
        })
    }

    pub fn itunes_lookup_feed_url(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_itunes_lookup_feed_url,
            )
        })
    }

    pub fn itunes_top_podcasts(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_itunes_top_podcasts,
            )
        })
    }

    pub fn threading_active_topics(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_threading_active_topics,
            )
        })
    }

    pub fn agent_inventory(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_inventory,
            )
        })
    }

    pub fn agent_inventory_list(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_agent_inventory_list,
            )
        })
    }

    pub fn local_search(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(handle, &request_json, super::nmp_app_podcast_local_search)
        })
    }

    pub fn home_continue_listening(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_home_continue_listening,
            )
        })
    }

    pub fn home_triage_rollup(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_home_triage_rollup,
            )
        })
    }

    pub fn home_subscription_list(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_home_subscription_list,
            )
        })
    }

    pub fn home_category_cards(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_home_category_cards,
            )
        })
    }

    pub fn carplay_listen_now(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_carplay_listen_now,
            )
        })
    }

    pub fn carplay_shows(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(handle, &request_json, super::nmp_app_podcast_carplay_shows)
        })
    }

    pub fn carplay_show_episodes(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_carplay_show_episodes,
            )
        })
    }

    pub fn carplay_downloads(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_carplay_downloads,
            )
        })
    }

    pub fn library_show_episodes(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_library_show_episodes,
            )
        })
    }

    pub fn library_podcast_stats(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_library_podcast_stats,
            )
        })
    }

    pub fn library_episode_for_audio_url(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_library_episode_for_audio_url,
            )
        })
    }

    pub fn library_all_episodes(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_library_all_episodes,
            )
        })
    }

    pub fn library_all_podcasts(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_library_all_podcasts,
            )
        })
    }

    pub fn library_categories(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_library_categories,
            )
        })
    }

    pub fn library_episode_lookup(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_library_episode_lookup,
            )
        })
    }

    pub fn library_subscription_status(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_library_subscription_status,
            )
        })
    }

    pub fn library_podcast_for_owner_pubkey(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_library_podcast_for_owner_pubkey,
            )
        })
    }

    pub fn library_categorization_parse(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_library_categorization_parse,
            )
        })
    }

    pub fn library_category_change(&self, request_json: String) -> Option<String> {
        self.podcast_handle_for_uniffi().and_then(|handle| {
            call_legacy_handle_json(
                handle,
                &request_json,
                super::nmp_app_podcast_library_category_change,
            )
        })
    }
}
