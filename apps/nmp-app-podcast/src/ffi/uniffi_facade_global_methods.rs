//! App-owned UniFFI global helpers that do not require a `PodcastApp` handle.

#[uniffi::export]
pub fn normalize_feed_url(request_json: String) -> Option<String> {
    super::feed_url_normalizer::normalize_feed_url_response_json(&request_json)
}

#[uniffi::export]
pub fn npub_from_hex(request_json: String) -> Option<String> {
    super::identity_format::npub_from_hex_json(&request_json)
}

#[uniffi::export]
pub fn parse_pubkey(request_json: String) -> Option<String> {
    super::identity_format::parse_pubkey_json(&request_json)
}

#[uniffi::export]
pub fn agent_action_policy(request_json: String) -> Option<String> {
    super::agent_action_tool::agent_action_policy_json(&request_json)
}

#[uniffi::export]
pub fn byok_authorization(request_json: String) -> Option<String> {
    super::byok_auth::byok_authorization_json(&request_json)
}
