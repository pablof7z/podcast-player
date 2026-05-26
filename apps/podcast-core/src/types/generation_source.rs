use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum GenerationSource {
    InAppChat {
        conversation_id: Uuid,
    },
    Nostr {
        root_event_id: String,
        peer_pubkey_hex: String,
    },
}

#[cfg(test)]
#[path = "generation_source_tests.rs"]
mod tests;
