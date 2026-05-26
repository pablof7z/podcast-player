use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TriageDecision {
    Inbox,
    Archived,
}

#[cfg(test)]
#[path = "triage_tests.rs"]
mod tests;
