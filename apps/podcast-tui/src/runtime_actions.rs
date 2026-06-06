use serde_json::json;

use crate::runtime::{AppRuntime, Result};

impl AppRuntime {
    pub fn play_episode(&self, episode_id: &str, _position_secs: f64) -> Result<String> {
        self.dispatch_action_value(
            "podcast.player",
            &json!({"op": "play", "episode_id": episode_id}),
        )
    }

    pub fn pause(&self) -> Result<String> {
        self.dispatch_action_value("podcast.player", &json!({"op": "pause"}))
    }

    pub fn resume(&self) -> Result<String> {
        self.dispatch_action_value("podcast.player", &json!({"op": "play"}))
    }

    pub fn seek(&self, position_secs: f64) -> Result<String> {
        self.dispatch_action_value(
            "podcast.player",
            &json!({"op": "seek", "position_secs": position_secs}),
        )
    }

    pub fn skip_forward(&self) -> Result<String> {
        self.dispatch_action_value("podcast.player", &json!({"op": "skip_forward"}))
    }

    pub fn skip_backward(&self) -> Result<String> {
        self.dispatch_action_value("podcast.player", &json!({"op": "skip_backward"}))
    }

    pub fn set_speed(&self, speed: f32) -> Result<String> {
        self.dispatch_action_value(
            "podcast.player",
            &json!({"op": "set_speed", "speed": speed}),
        )
    }

    pub fn set_volume(&self, volume: f32) -> Result<String> {
        self.dispatch_action_value(
            "podcast.player",
            &json!({"op": "set_volume", "volume": volume}),
        )
    }

    pub fn stop(&self) -> Result<String> {
        self.dispatch_action_value("podcast.player", &json!({"op": "stop"}))
    }

    pub fn subscribe(&self, feed_url: &str) -> Result<String> {
        self.dispatch_action_value("podcast", &json!({"op": "subscribe", "feed_url": feed_url}))
    }

    pub fn search_itunes(&self, query: &str) -> Result<String> {
        self.dispatch_action_value("podcast", &json!({"op": "search_itunes", "query": query}))
    }

    pub fn download_episode(&self, episode_id: &str) -> Result<String> {
        self.dispatch_action_value(
            "podcast",
            &json!({"op": "download", "episode_id": episode_id}),
        )
    }

    pub fn add_to_queue(&self, episode_id: &str) -> Result<String> {
        self.dispatch_action_value(
            "podcast.queue",
            &json!({"op": "add_last", "episode_id": episode_id}),
        )
    }

    pub fn add_next_to_queue(&self, episode_id: &str) -> Result<String> {
        self.dispatch_action_value(
            "podcast.queue",
            &json!({"op": "add_next", "episode_id": episode_id}),
        )
    }

    pub fn remove_from_queue(&self, episode_id: &str) -> Result<String> {
        self.dispatch_action_value(
            "podcast.queue",
            &json!({"op": "remove", "episode_id": episode_id}),
        )
    }

    pub fn clear_queue(&self) -> Result<String> {
        self.dispatch_action_value("podcast.queue", &json!({"op": "clear"}))
    }

    pub fn mark_played(&self, episode_id: &str) -> Result<String> {
        self.dispatch_action_value(
            "podcast.inbox",
            &json!({"op": "mark_listened", "episode_id": episode_id}),
        )
    }

    pub fn mark_unplayed(&self, episode_id: &str) -> Result<String> {
        self.dispatch_action_value(
            "podcast.inbox",
            &json!({"op": "mark_unlistened", "episode_id": episode_id}),
        )
    }

    pub fn star(&self, episode_id: &str) -> Result<String> {
        self.dispatch_action_value(
            "podcast",
            &json!({"op": "star_episode", "episode_id": episode_id, "starred": true}),
        )
    }

    pub fn unstar(&self, episode_id: &str) -> Result<String> {
        self.dispatch_action_value(
            "podcast",
            &json!({"op": "star_episode", "episode_id": episode_id, "starred": false}),
        )
    }

    pub fn auto_snip(&self, episode_id: &str, position_secs: f64) -> Result<String> {
        self.dispatch_action_value(
            "podcast.clip",
            &json!({"op": "auto_snip", "episode_id": episode_id, "position_secs": position_secs}),
        )
    }

    pub fn delete_clip(&self, clip_id: &str) -> Result<String> {
        self.dispatch_action_value("podcast.clip", &json!({"op": "delete", "clip_id": clip_id}))
    }

    pub fn send_agent_message(&self, message: &str) -> Result<String> {
        self.dispatch_action_value("podcast.agent", &json!({"op": "send", "message": message}))
    }

    pub fn clear_agent(&self) -> Result<String> {
        self.dispatch_action_value("podcast.agent", &json!({"op": "clear"}))
    }

    pub fn fetch_contacts(&self) -> Result<String> {
        self.dispatch_action_value("podcast", &json!({"op": "fetch_contacts"}))
    }

    pub fn fetch_agent_notes(&self) -> Result<String> {
        self.dispatch_action_value("podcast", &json!({"op": "fetch_agent_notes"}))
    }

    pub fn delete_wiki_article(&self, article_id: &str) -> Result<String> {
        self.dispatch_action_value(
            "podcast.wiki",
            &json!({"op": "delete", "article_id": article_id}),
        )
    }

    pub fn set_auto_play_next(&self, enabled: bool) -> Result<String> {
        self.dispatch_action_value(
            "podcast.settings",
            &json!({"op": "set_auto_play_next", "enabled": enabled}),
        )
    }

    pub fn set_auto_mark_played_at_end(&self, enabled: bool) -> Result<String> {
        self.dispatch_action_value(
            "podcast.settings",
            &json!({"op": "set_auto_mark_played_at_end", "enabled": enabled}),
        )
    }

    pub fn set_auto_skip_ads(&self, enabled: bool) -> Result<String> {
        self.dispatch_action_value(
            "podcast.settings",
            &json!({"op": "set_auto_skip_ads", "enabled": enabled}),
        )
    }

    pub fn set_auto_delete_downloads_after_played(&self, enabled: bool) -> Result<String> {
        self.dispatch_action_value(
            "podcast.settings",
            &json!({"op": "set_auto_delete_downloads_after_played", "enabled": enabled}),
        )
    }

    pub fn set_notify_on_new_episodes(&self, enabled: bool) -> Result<String> {
        self.dispatch_action_value(
            "podcast.settings",
            &json!({"op": "set_notify_on_new_episodes", "enabled": enabled}),
        )
    }

    pub fn set_wiki_auto_generate(&self, enabled: bool) -> Result<String> {
        self.dispatch_action_value(
            "podcast.settings",
            &json!({"op": "set_wiki_auto_generate_on_transcript_ingest", "enabled": enabled}),
        )
    }

    pub fn set_auto_ingest_publisher_transcripts(&self, enabled: bool) -> Result<String> {
        self.dispatch_action_value(
            "podcast.settings",
            &json!({"op": "set_auto_ingest_publisher_transcripts", "enabled": enabled}),
        )
    }

    pub fn set_auto_fallback_to_scribe(&self, enabled: bool) -> Result<String> {
        self.dispatch_action_value(
            "podcast.settings",
            &json!({"op": "set_auto_fallback_to_scribe", "enabled": enabled}),
        )
    }

    pub fn set_nostr_enabled(&self, enabled: bool) -> Result<String> {
        self.dispatch_action_value(
            "podcast.settings",
            &json!({"op": "set_nostr_enabled", "enabled": enabled}),
        )
    }

    pub fn set_default_playback_rate(&self, rate: f64) -> Result<String> {
        self.dispatch_action_value(
            "podcast.settings",
            &json!({"op": "set_default_playback_rate", "rate": rate}),
        )
    }
}
