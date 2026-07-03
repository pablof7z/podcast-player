//! App-owned UniFFI global helpers that do not require a `PodcastApp` handle.

use super::uniffi_facade_legacy_support::call_legacy_global_json;

#[uniffi::export]
pub fn normalize_feed_url(request_json: String) -> Option<String> {
    call_legacy_global_json(&request_json, super::nmp_app_podcast_normalize_feed_url)
}

#[uniffi::export]
pub fn npub_from_hex(request_json: String) -> Option<String> {
    call_legacy_global_json(&request_json, super::nmp_app_podcast_npub_from_hex)
}

#[uniffi::export]
pub fn parse_pubkey(request_json: String) -> Option<String> {
    call_legacy_global_json(&request_json, super::nmp_app_podcast_parse_pubkey)
}

#[uniffi::export]
pub fn agent_action_policy(request_json: String) -> Option<String> {
    call_legacy_global_json(&request_json, super::nmp_app_podcast_agent_action_policy)
}

#[uniffi::export]
pub fn byok_authorization(request_json: String) -> Option<String> {
    call_legacy_global_json(&request_json, super::nmp_app_podcast_byok_authorization)
}
