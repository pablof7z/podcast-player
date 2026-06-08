//! JSON persistence for shared agent task rows.
//!
//! `AgentTaskSummary` intentionally skips `action_namespace` and `action_body`
//! during normal snapshot serialization so platform UIs cannot treat backend
//! action JSON as a user-facing task contract. The scheduler still needs those
//! fields after a cold launch, so this sidecar persists an internal row shape
//! that includes the dispatch payload while keeping the FFI projection clean.

use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::ffi::projections::AgentTaskSummary;

pub const AGENT_TASKS_FILE: &str = "agent-tasks.json";

#[derive(Debug, Deserialize, Serialize)]
struct PersistedAgentTask {
    id: String,
    title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    description: Option<String>,
    #[serde(default = "default_intent_type")]
    intent_type: String,
    #[serde(default = "default_intent_label")]
    intent_label: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    intent_detail: Option<String>,
    #[serde(default)]
    action_namespace: String,
    #[serde(default)]
    action_body: String,
    schedule: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    next_run_at: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    last_run_at: Option<i64>,
    status: String,
    is_enabled: bool,
}

impl From<&AgentTaskSummary> for PersistedAgentTask {
    fn from(task: &AgentTaskSummary) -> Self {
        Self {
            id: task.id.clone(),
            title: task.title.clone(),
            description: task.description.clone(),
            intent_type: task.intent_type.clone(),
            intent_label: task.intent_label.clone(),
            intent_detail: task.intent_detail.clone(),
            action_namespace: task.action_namespace.clone(),
            action_body: task.action_body.clone(),
            schedule: task.schedule.clone(),
            next_run_at: task.next_run_at,
            last_run_at: task.last_run_at,
            status: task.status.clone(),
            is_enabled: task.is_enabled,
        }
    }
}

impl From<PersistedAgentTask> for AgentTaskSummary {
    fn from(task: PersistedAgentTask) -> Self {
        Self {
            id: task.id,
            title: task.title,
            description: task.description,
            intent_type: task.intent_type,
            intent_label: task.intent_label,
            intent_detail: task.intent_detail,
            action_namespace: task.action_namespace,
            action_body: task.action_body,
            schedule: task.schedule,
            next_run_at: task.next_run_at,
            last_run_at: task.last_run_at,
            status: task.status,
            is_enabled: task.is_enabled,
        }
    }
}

/// Write the full task list to `<data_dir>/agent-tasks.json`.
pub fn save_agent_tasks(dir: &Path, tasks: &[AgentTaskSummary]) -> Result<(), String> {
    std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let rows = tasks
        .iter()
        .map(PersistedAgentTask::from)
        .collect::<Vec<_>>();
    let json = serde_json::to_vec_pretty(&rows).map_err(|e| e.to_string())?;
    let final_path = dir.join(AGENT_TASKS_FILE);
    let tmp_path = dir.join(format!("{AGENT_TASKS_FILE}.tmp"));
    std::fs::write(&tmp_path, &json).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp_path, &final_path).map_err(|e| e.to_string())
}

/// Load `<data_dir>/agent-tasks.json`.
///
/// `None` means no valid sidecar exists and callers should keep their current
/// first-launch seed. `Some(vec![])` is a valid persisted empty task list.
#[must_use]
pub fn load_agent_tasks(dir: &Path) -> Option<Vec<AgentTaskSummary>> {
    let path = dir.join(AGENT_TASKS_FILE);
    let bytes = std::fs::read(&path).ok()?;
    let rows = serde_json::from_slice::<Vec<PersistedAgentTask>>(&bytes).ok()?;
    Some(rows.into_iter().map(AgentTaskSummary::from).collect())
}

fn default_intent_type() -> String {
    "custom".to_owned()
}

fn default_intent_label() -> String {
    "Custom task".to_owned()
}

#[cfg(test)]
#[path = "agent_tasks_tests.rs"]
mod tests;
