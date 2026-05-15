//! Relay configuration for the podcast app. Includes seed defaults and helpers
//! for parsing NIP-65 (kind:10002) relay-list events.

use nostr_sdk::prelude::*;
use serde::{Deserialize, Serialize};

/// Default relays seeded when a user has no NIP-65 list yet. Kept small —
/// covers a broad surface for discovery + general events.
pub const SEED_RELAYS: &[&str] = &[
    "wss://relay.damus.io",
    "wss://relay.primal.net",
    "wss://nos.lol",
    "wss://relay.nostr.band",
    "wss://purplepag.es",
];

/// Specific relay used for NIP-46 nostr-connect handshakes.
pub const NOSTR_CONNECT_RELAY: &str = "wss://relay.nsec.app";

/// Read-side cache relay for kind:0/3/10002 (negentropy-synced).
pub const PURPLE_PAGES_RELAY: &str = "wss://purplepag.es";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RelayConfig {
    pub url: String,
    pub read: bool,
    pub write: bool,
}

impl RelayConfig {
    pub fn both(url: impl Into<String>) -> Self {
        Self {
            url: url.into(),
            read: true,
            write: true,
        }
    }
}

pub fn seed_defaults() -> Vec<RelayConfig> {
    SEED_RELAYS
        .iter()
        .map(|u| RelayConfig::both(*u))
        .collect()
}

/// Parse a kind:10002 NIP-65 relay-list event into [`RelayConfig`] entries.
pub fn parse_nip65(event: &Event) -> Vec<RelayConfig> {
    let mut out = Vec::new();
    for tag in event.tags.iter() {
        let v = tag.as_slice();
        if v.first().map(|s| s.as_str()) != Some("r") {
            continue;
        }
        let Some(url) = v.get(1) else { continue };
        let marker = v.get(2).map(|s| s.as_str()).unwrap_or("");
        let (read, write) = match marker {
            "read" => (true, false),
            "write" => (false, true),
            _ => (true, true),
        };
        out.push(RelayConfig {
            url: url.clone(),
            read,
            write,
        });
    }
    out
}
