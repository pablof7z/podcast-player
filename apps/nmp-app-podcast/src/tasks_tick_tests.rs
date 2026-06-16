//! Tests for [`super::maybe_run_due_tasks`] — the kernel-owned periodic
//! firing path.
//!
//! Contract under test:
//!   * Past-due task fires EXACTLY ONCE across consecutive tick calls at the
//!     same wall-clock; `next_run_at` is advanced past `now` so re-fire is
//!     impossible.
//!   * Disabled task is skipped.
//!   * In-flight (`status == "running"`) task is skipped.
//!   * `once` schedule fires once and does not re-arm (next_run_at → None).
//!   * The Domain::Tasks rev counter (not merely the global rev) is bumped
//!     when the kernel tick fires at least one task — a test asserting only
//!     the global rev cannot distinguish a tasks-tick from an unrelated
//!     Misc mutation.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use crate::ffi::projections::AgentTaskSummary;
use crate::state::domain::{Domain, DomainRevs};
use crate::state::Infra;
use crate::tasks_schedule::next_run_after;

use super::maybe_run_due_tasks;

// ── Helpers ───────────────────────────────────────────────────────────────────

const NOW: i64 = 1_700_000_000_i64;

/// Build a minimal enabled task whose `next_run_at` is `now_unix - offset`
/// (i.e. already past due when `maybe_run_due_tasks(now_unix)` is called).
fn past_due_task(schedule: &str, offset_before_now: i64) -> AgentTaskSummary {
    AgentTaskSummary {
        id: uuid::Uuid::new_v4().to_string(),
        title: "Tick test task".into(),
        description: None,
        intent_type: "custom".into(),
        intent_label: "Custom task".into(),
        intent_detail: None,
        action_namespace: "podcast.inbox".into(),
        action_body: r#"{"op":"triage"}"#.into(),
        schedule: schedule.into(),
        next_run_at: Some(NOW - offset_before_now),
        last_run_at: None,
        status: "pending".into(),
        is_enabled: true,
    }
}

fn new_state_with(task: AgentTaskSummary) -> (Arc<Mutex<Vec<AgentTaskSummary>>>, Arc<AtomicU64>) {
    (
        Arc::new(Mutex::new(vec![task])),
        Arc::new(AtomicU64::new(0)),
    )
}

// ── Tests ─────────────────────────────────────────────────────────────────────

/// Past-due task fires exactly once at the first tick; a second call with
/// the SAME `now_unix` finds no due tasks because `next_run_at` was advanced.
#[test]
fn past_due_task_fires_exactly_once_across_consecutive_ticks() {
    let (tasks, rev) = new_state_with(past_due_task("daily", 60));
    let dispatch_count = Arc::new(AtomicU64::new(0));
    let dc = Arc::clone(&dispatch_count);
    let dispatch = move |_ns: &str, _body: &str| {
        dc.fetch_add(1, Ordering::Relaxed);
        true // accepted
    };

    // First tick — fires.
    let fired1 = maybe_run_due_tasks(&tasks, &rev, Some(&dispatch), NOW);
    assert_eq!(fired1, 1, "tick 1: expected 1 task fired");
    assert_eq!(dispatch_count.load(Ordering::Relaxed), 1, "dispatch called once");

    // Second tick at the same wall-clock — MUST NOT re-fire (next_run_at > NOW).
    let fired2 = maybe_run_due_tasks(&tasks, &rev, Some(&dispatch), NOW);
    assert_eq!(fired2, 0, "tick 2: same now_unix must not re-fire");
    assert_eq!(dispatch_count.load(Ordering::Relaxed), 1, "dispatch NOT called again");

    // Task is re-armed to a future slot (daily: NOW + 86400).
    let guard = tasks.lock().unwrap();
    let next = guard[0].next_run_at.expect("daily task must have next_run_at after fire");
    assert!(
        next > NOW,
        "next_run_at={next} must be in the future (> NOW={NOW})"
    );
}

/// Disabled task is never dispatched by the periodic tick.
#[test]
fn disabled_task_not_fired_by_tick() {
    let mut task = past_due_task("daily", 60);
    task.is_enabled = false;
    let (tasks, rev) = new_state_with(task);
    let dispatch = |_ns: &str, _body: &str| true;

    let fired = maybe_run_due_tasks(&tasks, &rev, Some(&dispatch), NOW);
    assert_eq!(fired, 0, "disabled task must not fire");
    assert_eq!(rev.load(Ordering::Relaxed), 0, "rev unchanged for skipped task");
}

/// A REJECTED dispatch (kernel returned no correlation_id) must STILL count as
/// fired: the task flipped to `"failed"` and `next_run_at` advanced, so the
/// caller must bump the snapshot for the `"failed"` status to push reactively.
#[test]
fn rejected_dispatch_still_counts_as_fired_and_marks_failed() {
    let (tasks, rev) = new_state_with(past_due_task("daily", 60));
    // Dispatch rejects (e.g. unknown namespace / bad body) → accepted == false.
    let dispatch = |_ns: &str, _body: &str| false;

    let fired = maybe_run_due_tasks(&tasks, &rev, Some(&dispatch), NOW);
    assert_eq!(
        fired, 1,
        "a rejected (failed) run must still count as fired so the caller bumps"
    );

    let guard = tasks.lock().unwrap();
    assert_eq!(guard[0].status, "failed", "rejected dispatch marks task failed");
    let next = guard[0].next_run_at.expect("daily task re-arms even when failed");
    assert!(next > NOW, "next_run_at={next} must advance past NOW even on failure");
}

/// A task whose status is already "running" (in-flight from a previous tick
/// that hasn't received a dispatch response yet) MUST NOT be re-dispatched.
#[test]
fn in_flight_running_task_skipped_by_tick() {
    let mut task = past_due_task("daily", 60);
    task.status = "running".into(); // simulates prior tick setting the flag
    let (tasks, rev) = new_state_with(task);
    let dispatch = |_ns: &str, _body: &str| true;

    let fired = maybe_run_due_tasks(&tasks, &rev, Some(&dispatch), NOW);
    assert_eq!(fired, 0, "in-flight task must not fire again");
}

/// A task with `schedule = "once"` fires exactly once and does NOT re-arm
/// (`next_run_at` → `None` after `next_run_after_attempt`).
#[test]
fn once_schedule_fires_once_then_not_rearmed() {
    let mut task = past_due_task("once", 1);
    // "once" tasks have next_run_at set to their creation time (already past).
    task.next_run_at = Some(NOW - 1);
    let (tasks, rev) = new_state_with(task);
    let dispatch = |_ns: &str, _body: &str| true;

    let fired = maybe_run_due_tasks(&tasks, &rev, Some(&dispatch), NOW);
    assert_eq!(fired, 1, "once task fires on first due tick");

    // After firing, next_run_at is None (once does not re-arm).
    {
        let guard = tasks.lock().unwrap();
        assert_eq!(
            guard[0].next_run_at, None,
            "once task must NOT re-arm after firing"
        );
    }

    // A subsequent tick cannot find it (no next_run_at).
    let fired2 = maybe_run_due_tasks(&tasks, &rev, Some(&dispatch), NOW);
    assert_eq!(fired2, 0, "once task must not fire a second time");
}

/// The Domain::Tasks rev is bumped when `infra.bump()` is called after the
/// tick fires tasks.  This is the regression guard: asserting only the global
/// rev cannot distinguish a tasks-domain mutation from an unrelated Misc bump.
///
/// This test simulates the `TasksState::start_ticker` hot path: it calls
/// `maybe_run_due_tasks` and then calls `infra.bump()` exactly as the ticker
/// does when `fired > 0`.
#[test]
fn tick_fire_bumps_tasks_domain_rev_not_just_global() {
    let (tasks, rev) = new_state_with(past_due_task("daily", 60));
    let domain_revs = Arc::new(DomainRevs::new());
    let tasks_rev_before = domain_revs.tasks.load(Ordering::Relaxed);
    let misc_rev_before = domain_revs.misc.load(Ordering::Relaxed);

    let infra = Infra::for_test_with_rev(Arc::clone(&rev));
    // Override the domain_revs to the one we can inspect.
    let infra = {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("test runtime");
        Infra {
            rev: Arc::clone(&rev),
            signal: None,
            runtime: Arc::new(rt),
            domain_revs: Arc::clone(&domain_revs),
            domain: Domain::Tasks,
        }
    };

    let dispatch = |_ns: &str, _body: &str| true;
    let fired = maybe_run_due_tasks(&tasks, &rev, Some(&dispatch), NOW);
    assert_eq!(fired, 1, "expected one task fired");

    // Simulate the ticker's post-fire bump.
    infra.bump();

    let tasks_rev_after = domain_revs.tasks.load(Ordering::Relaxed);
    let misc_rev_after = domain_revs.misc.load(Ordering::Relaxed);

    assert!(
        tasks_rev_after > tasks_rev_before,
        "Domain::Tasks rev must advance after tick fire (before={tasks_rev_before}, after={tasks_rev_after})"
    );
    assert_eq!(
        misc_rev_after, misc_rev_before,
        "Domain::Misc rev must NOT change when only tasks fire \
         (before={misc_rev_before}, after={misc_rev_after})"
    );
}

/// Verify that `next_run_after_attempt` for a recurring schedule produces
/// a next_run_at that is strictly AFTER `now_unix`, preventing the hot-loop
/// edge case where a very fast task interval could re-fire on the same tick.
#[test]
fn recurring_task_next_run_always_in_future_after_attempt() {
    let schedule = "every 30s";
    let next = next_run_after(schedule, NOW)
        .expect("valid schedule")
        .expect("recurring has next_run");
    assert!(
        next > NOW,
        "next_run_after must be strictly in the future (got {next}, now={NOW})"
    );
    // After an attempt, next_run_after_attempt also gives future slot.
    let next2 = crate::tasks_schedule::next_run_after_attempt(schedule, NOW)
        .expect("valid")
        .expect("recurring re-arms");
    assert!(
        next2 > NOW,
        "next_run_after_attempt must be strictly in the future (got {next2}, now={NOW})"
    );
}
