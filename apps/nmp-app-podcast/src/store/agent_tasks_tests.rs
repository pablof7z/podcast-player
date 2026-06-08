use super::*;

struct TempDir {
    path: std::path::PathBuf,
}

impl TempDir {
    fn new(tag: &str) -> Self {
        static SEQ: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let n = SEQ.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "nmp-podcast-agent-tasks-{}-{}-{}",
            tag,
            std::process::id(),
            n,
        ));
        std::fs::create_dir_all(&path).expect("create tempdir");
        Self { path }
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.path);
    }
}

fn sample_task() -> AgentTaskSummary {
    AgentTaskSummary {
        id: "task-1".to_owned(),
        title: "Remember".to_owned(),
        description: Some("persist me".to_owned()),
        intent_type: "remember_memory".to_owned(),
        intent_label: "Remember memory".to_owned(),
        intent_detail: Some("topic = rust".to_owned()),
        action_namespace: "podcast.memory".to_owned(),
        action_body: r#"{"op":"remember","key":"topic","value":"rust","source":"task"}"#
            .to_owned(),
        schedule: "daily".to_owned(),
        next_run_at: Some(1_700_000_000),
        last_run_at: Some(1_699_999_000),
        status: "completed".to_owned(),
        is_enabled: true,
    }
}

#[test]
fn missing_file_keeps_current_seed() {
    let dir = TempDir::new("missing");
    assert!(load_agent_tasks(&dir.path).is_none());
}

#[test]
fn empty_list_is_valid_persisted_state() {
    let dir = TempDir::new("empty");
    save_agent_tasks(&dir.path, &[]).expect("save empty list");
    let restored = load_agent_tasks(&dir.path).expect("valid empty list");
    assert!(restored.is_empty());
}

#[test]
fn round_trip_preserves_internal_dispatch_payload() {
    let dir = TempDir::new("roundtrip");
    let task = sample_task();

    save_agent_tasks(&dir.path, std::slice::from_ref(&task)).expect("save task");
    let restored = load_agent_tasks(&dir.path).expect("restored tasks");

    assert_eq!(restored, vec![task]);
    assert_eq!(restored[0].action_namespace, "podcast.memory");
    assert!(restored[0].action_body.contains("\"remember\""));
}

#[test]
fn corrupt_file_is_treated_as_missing() {
    let dir = TempDir::new("corrupt");
    std::fs::write(dir.path.join(AGENT_TASKS_FILE), b"not-json").expect("write corrupt file");

    assert!(load_agent_tasks(&dir.path).is_none());
}

#[test]
fn task_handler_persists_after_successful_mutation() {
    use crate::ffi::actions::{AgentTaskIntent, AgentTasksAction};
    use crate::tasks_handler::handle_tasks_action_with_persist;
    use std::sync::atomic::AtomicU64;
    use std::sync::{Arc, Mutex};

    let dir = TempDir::new("handler");
    let tasks = Arc::new(Mutex::new(Vec::new()));
    let rev = Arc::new(AtomicU64::new(0));
    let persist = |snapshot: &[AgentTaskSummary]| {
        save_agent_tasks(&dir.path, snapshot).expect("persist tasks")
    };

    let result = handle_tasks_action_with_persist(
        AgentTasksAction::CreateFromIntent {
            title: "Remember".to_owned(),
            description: None,
            intent: AgentTaskIntent::RememberMemory {
                key: "topic".to_owned(),
                value: "rust".to_owned(),
            },
            schedule: "daily".to_owned(),
        },
        &tasks,
        &rev,
        None,
        Some(&persist),
    );

    assert_eq!(result["ok"], true);
    let restored = load_agent_tasks(&dir.path).expect("persisted tasks");
    assert_eq!(restored.len(), 1);
    assert_eq!(restored[0].intent_type, "remember_memory");
    assert_eq!(restored[0].action_namespace, "podcast.memory");
}
