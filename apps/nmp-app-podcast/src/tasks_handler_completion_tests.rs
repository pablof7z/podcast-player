//! Completion-correctness and time-injection regression tests for
//! [`super::tasks_handler`].
//!
//! Extracted from `tasks_handler_tests.rs` to keep every file under the
//! 500-line hard limit.  Tests here guard against the premature-completion
//! bug (dispatch is fire-and-forget; tasks must stay "running" after
//! dispatch, not flip to "completed") and verify that `default_seed` uses
//! caller-supplied time rather than `Utc::now()`.

use super::*;

fn new_state() -> (Arc<Mutex<Vec<AgentTaskSummary>>>, Arc<AtomicU64>) {
    (
        Arc::new(Mutex::new(Vec::new())),
        Arc::new(AtomicU64::new(0)),
    )
}

const TEST_NOW: i64 = 1_700_000_000_i64;

/// Helper: create one enabled task and return its id.
fn create_task(tasks: &Arc<Mutex<Vec<AgentTaskSummary>>>, rev: &Arc<AtomicU64>) -> String {
    let create = handle_tasks_action(
        AgentTasksAction::Create {
            title: "T".into(),
            description: None,
            action_namespace: "podcast.x".into(),
            action_body: "{}".into(),
            schedule: "once".into(),
        },
        tasks,
        rev,
        None,
    );
    create["task_id"].as_str().unwrap().to_string()
}

// ── Time-injection and completion-correctness regression tests ────────────────

/// `default_seed` uses the caller-supplied `now` parameter for `next_run_at`
/// rather than calling `Utc::now()` internally.  With a fixed timestamp the
/// result is fully deterministic — daily is exactly 86 400 s from `now`.
#[test]
fn default_seed_next_run_at_is_deterministic_with_injected_time() {
    let seed = default_seed(TEST_NOW);
    assert_eq!(
        seed[0].next_run_at,
        Some(TEST_NOW + 86_400),
        "daily next_run_at must be exactly 86400 s from the injected now"
    );
    // A different `now` produces a different but equally deterministic result.
    let seed2 = default_seed(TEST_NOW + 3_600);
    assert_eq!(seed2[0].next_run_at, Some(TEST_NOW + 3_600 + 86_400));
}

/// A task whose dispatch was ACCEPTED stays "running" (in-flight), never
/// "completed".  This is the correctness regression guard for the premature
/// completion bug: dispatch is fire-and-forget (action enqueued only); the
/// kernel task subsystem has no downstream completion signal, so reporting
/// "completed" at dispatch time was always a lie.
#[test]
fn dispatched_but_unfinished_task_is_never_completed() {
    let (tasks, rev) = new_state();
    // Create a task with a known namespace/body.
    let create = handle_tasks_action(
        AgentTasksAction::Create {
            title: "Regression guard".into(),
            description: None,
            action_namespace: "podcast.inbox".into(),
            action_body: r#"{"op":"triage"}"#.into(),
            schedule: "once".into(),
        },
        &tasks,
        &rev,
        None,
    );
    let task_id = create["task_id"].as_str().unwrap().to_owned();

    // Dispatch accepts — this is the ONLY signal tasks_handler can observe.
    let dispatch = |_ns: &str, _body: &str| true;
    let result = handle_tasks_action(
        AgentTasksAction::RunNow { task_id: task_id.clone() },
        &tasks,
        &rev,
        Some(&dispatch),
    );

    assert_eq!(result["ok"], true, "dispatch was accepted");
    assert_ne!(
        result["status"].as_str().unwrap_or(""),
        "completed",
        "P1 regression: dispatched-but-unfinished task MUST NOT be 'completed'"
    );
    assert_eq!(result["status"], "running");

    let guard = tasks.lock().unwrap();
    let task = guard.iter().find(|t| t.id == task_id).unwrap();
    assert_ne!(task.status, "completed", "task slot must not claim completion");
    assert_eq!(task.status, "running", "task slot must be 'running' (in-flight)");
}

/// RunDue counts accepted-dispatch tasks in the `accepted` JSON field.
/// After the completion fix, `accepted` corresponds to tasks whose status
/// is "running" (dispatch enqueued), not a stale "completed" count.
#[test]
fn run_due_counts_dispatched_tasks_in_accepted_field() {
    let (tasks, rev) = new_state();
    // Create two due tasks.
    for i in 0..2 {
        handle_tasks_action(
            AgentTasksAction::Create {
                title: format!("T{i}"),
                description: None,
                action_namespace: "podcast.inbox".into(),
                action_body: r#"{"op":"triage"}"#.into(),
                schedule: "once".into(),
            },
            &tasks,
            &rev,
            None,
        );
    }
    let dispatch_count = std::sync::atomic::AtomicU64::new(0);
    let dispatch = |_ns: &str, _body: &str| {
        dispatch_count.fetch_add(1, Ordering::Relaxed);
        true // accept
    };
    let result = handle_tasks_action(AgentTasksAction::RunDue, &tasks, &rev, Some(&dispatch));
    assert_eq!(result["ok"], true);
    assert_eq!(result["ran"], 2);
    assert_eq!(result["accepted"], 2, "both tasks dispatched → both accepted");
    assert_eq!(result["failed"], 0);
    // All tasks are in-flight, not prematurely completed.
    let guard = tasks.lock().unwrap();
    assert!(
        guard.iter().all(|t| t.status == "running"),
        "all dispatched tasks must be 'running', not 'completed'"
    );
}

/// An accepting dispatch (kernel minted a correlation_id) means the action
/// was ENQUEUED, NOT that downstream work is done.  The task must stay
/// "running" (in-flight), never "completed".
#[test]
fn run_now_accepted_dispatch_stays_running_not_completed() {
    let (tasks, rev) = new_state();
    let task_id = create_task(&tasks, &rev);
    let dispatch = |_ns: &str, _body: &str| true;
    let result = handle_tasks_action(
        AgentTasksAction::RunNow {
            task_id: task_id.clone(),
        },
        &tasks,
        &rev,
        Some(&dispatch),
    );
    assert_eq!(result["ok"], true);
    // Dispatch accepted → in-flight, NOT prematurely completed.
    assert_ne!(
        result["status"], "completed",
        "dispatched-but-unfinished task must NOT be 'completed'"
    );
    assert_eq!(
        result["status"], "running",
        "accepted dispatch must leave task in 'running' (in-flight) status"
    );
    let guard = tasks.lock().unwrap();
    assert_eq!(guard[0].status, "running");
    assert!(guard[0].last_run_at.is_some());
}
