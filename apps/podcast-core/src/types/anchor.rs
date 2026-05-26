use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Anchor {
    Note {
        id: Uuid,
    },
    Friend {
        id: Uuid,
    },
    Episode {
        id: Uuid,
        #[serde(default)]
        position_seconds: f64,
    },
}

#[cfg(test)]
#[path = "anchor_tests.rs"]
mod tests;
