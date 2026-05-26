use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AdKind {
    Preroll,
    Midroll,
    Postroll,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AdSegment {
    pub id: Uuid,
    pub start_secs: f64,
    pub end_secs: f64,
    pub kind: AdKind,
}

impl AdSegment {
    pub fn new(start_secs: f64, end_secs: f64, kind: AdKind) -> Self {
        Self {
            id: Uuid::new_v4(),
            start_secs,
            end_secs,
            kind,
        }
    }
}

#[cfg(test)]
#[path = "ad_segment_tests.rs"]
mod tests;
