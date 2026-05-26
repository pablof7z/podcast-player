use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SoundBite {
    pub id: Uuid,
    pub start_secs: f64,
    pub duration_secs: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
}

impl SoundBite {
    pub fn new(start_secs: f64, duration_secs: f64) -> Self {
        Self {
            id: Uuid::new_v4(),
            start_secs,
            duration_secs,
            title: None,
        }
    }
}

#[cfg(test)]
#[path = "soundbite_tests.rs"]
mod tests;
