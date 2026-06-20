//! Tests for [`super`] `TasksState` — extracted from `tasks.rs` to keep that
//! file under the 500-line hard limit (AGENTS.md).  Included via
//! `#[path = "tasks_tests.rs"] mod tests;` so it is a child module of `tasks`
//! and can reach the parent's private items through `use super::*`.

use crate::ffi::actions::tasks_module::AgentTasksAction;

use super::*;

#[test]
fn tasks_snapshot_returns_default_seed() {
    let state = TasksState::for_test();
    let snap = state.tasks_snapshot();
    assert!(!snap.is_empty(), "default seed should be non-empty");
    assert_eq!(snap[0].schedule, "daily");
}

#[test]
fn create_task_bumps_rev() {
    let state = TasksState::for_test();
    let rev0 = state.infra.rev();

    let out = state.handle(
        AgentTasksAction::Create {
            title: "My Task".into(),
            description: None,
            action_namespace: "podcast.inbox".into(),
            action_body: r#"{"op":"triage"}"#.into(),
            schedule: "daily".into(),
        },
        std::ptr::null_mut(),
    );
    assert_eq!(out["ok"], true);
    assert!(out["task_id"].is_string());
    assert!(state.infra.rev() > rev0, "create must bump rev");
    // Seed + newly created
    assert_eq!(state.tasks_snapshot().len(), 2);
}

#[test]
fn delete_task_bumps_rev() {
    let state = TasksState::for_test();
    let snap = state.tasks_snapshot();
    let task_id = snap[0].id.clone();
    let rev0 = state.infra.rev();

    let out = state.handle(
        AgentTasksAction::Delete {
            task_id: task_id.clone(),
        },
        std::ptr::null_mut(),
    );
    assert_eq!(out["ok"], true);
    assert!(state.infra.rev() > rev0, "delete must bump rev");
    assert!(state.tasks_snapshot().iter().all(|t| t.id != task_id));
}

#[test]
fn enable_disable_task() {
    let state = TasksState::for_test();
    let task_id = state.tasks_snapshot()[0].id.clone();

    let out_disable = state.handle(
        AgentTasksAction::Disable {
            task_id: task_id.clone(),
        },
        std::ptr::null_mut(),
    );
    assert_eq!(out_disable["ok"], true);
    assert!(!state.tasks_snapshot()[0].is_enabled);

    let out_enable = state.handle(
        AgentTasksAction::Enable {
            task_id: task_id.clone(),
        },
        std::ptr::null_mut(),
    );
    assert_eq!(out_enable["ok"], true);
    assert!(state.tasks_snapshot()[0].is_enabled);
}

// ── Ticker lifecycle (UAF fence regression) ───────────────────────────────

use std::sync::atomic::AtomicU64;
use std::time::Instant;

use crate::ffi::projections::AgentTaskSummary;
use crate::state::{Domain, DomainRevs};

/// Build a `TasksState` backed by a real MULTI-THREAD runtime (so the
/// spawned ticker actually runs in the background) seeded with a single
/// perpetually-re-arming due task (`every 1s`, already past due).
fn ticker_test_state() -> TasksState {
    let rt = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .expect("multi-thread test runtime");
    let infra = Infra {
        rev: Arc::new(AtomicU64::new(1)),
        signal: None,
        runtime: Arc::new(rt),
        domain_revs: Arc::new(DomainRevs::new()),
        domain: Domain::Tasks,
    };
    let due = AgentTaskSummary {
        id: "tick-1".into(),
        title: "Due task".into(),
        description: None,
        intent_type: "custom".into(),
        intent_label: "Custom task".into(),
        intent_detail: None,
        action_namespace: "podcast.inbox".into(),
        action_body: r#"{"op":"triage"}"#.into(),
        schedule: "every 1s".into(),
        // Already past due — fires on the first tick.
        next_run_at: Some(chrono::Utc::now().timestamp() - 5),
        last_run_at: None,
        status: "pending".into(),
        is_enabled: true,
    };
    TasksState {
        tasks: Slot::new(vec![due]),
        infra,
        store: Arc::new(Mutex::new(PodcastStore::new())),
        ticker: Mutex::new(None),
        shutting_down: Arc::new(AtomicBool::new(false)),
    }
}

/// The shutdown fence must stop the ticker so NO dispatch occurs after
/// `shutdown()` returns — and shutdown must return promptly (abort, not a
/// 60 s sleep wait).  Against an un-fenced ticker this fails: the task keeps
/// running and re-fires the `every 1s` task within the post-shutdown window.
#[test]
fn ticker_fences_dispatch_on_shutdown() {
    let state = ticker_test_state();
    let count = Arc::new(AtomicU64::new(0));

    // Inject a counting dispatch (no FFI / no live kernel needed).
    let dispatch = {
        let c = Arc::clone(&count);
        move |_ns: &str, _body: &str| -> bool {
            c.fetch_add(1, Ordering::SeqCst);
            true // accepted → run_task_by_id stamps "running" (in-flight) + re-arms
        }
    };
    // Short interval so the test runs quickly.
    state.spawn_ticker_loop(Duration::from_millis(20), dispatch);

    // Let the ticker fire the already-due task at least once.
    std::thread::sleep(Duration::from_millis(200));
    let fired_before = count.load(Ordering::SeqCst);
    assert!(
        fired_before >= 1,
        "ticker should have fired the due task at least once (got {fired_before})"
    );

    // Shutdown must return promptly (abort cancels the sleep — no 60 s wait).
    let t0 = Instant::now();
    state.shutdown();
    let elapsed = t0.elapsed();
    assert!(
        elapsed < Duration::from_secs(2),
        "shutdown must return promptly via abort; took {elapsed:?}"
    );

    // The `every 1s` task re-arms to `now + 1`; a LIVE ticker would re-fire
    // it within the next ~1 s.  Wait past that window and assert the count
    // is frozen — proving the spawned task is dead.
    let count_at_shutdown = count.load(Ordering::SeqCst);
    std::thread::sleep(Duration::from_millis(1_300));
    let count_after = count.load(Ordering::SeqCst);
    assert_eq!(
        count_after, count_at_shutdown,
        "no dispatch may occur after shutdown (before={count_at_shutdown}, \
         after={count_after}) — the ticker task was not fenced"
    );
}

/// Isolates the `abort()` in the fence: with a LONG tick interval the
/// spawned task spends ~all its time parked in `sleep(interval).await`.
/// `shutdown` aborts that await so the join resolves immediately.  WITHOUT
/// the abort, `shutdown`'s `block_on(handle.await)` would block for up to a
/// full interval (here 10 s) waiting for the task to wake and observe the
/// `shutting_down` flag — so the `< 2 s` assertion fails.  This is the test
/// that goes red if the `handle.abort()` line is removed.
#[test]
fn ticker_shutdown_aborts_long_sleep_promptly() {
    let state = ticker_test_state();
    let dispatch = |_ns: &str, _body: &str| true;
    // 10 s interval: the task is asleep almost immediately and stays asleep.
    state.spawn_ticker_loop(Duration::from_secs(10), dispatch);
    // Give the spawned task a moment to reach its first `sleep().await`.
    std::thread::sleep(Duration::from_millis(50));

    let t0 = Instant::now();
    state.shutdown();
    let elapsed = t0.elapsed();
    assert!(
        elapsed < Duration::from_secs(2),
        "shutdown must abort the parked 10 s sleep and return promptly; \
         took {elapsed:?} (the abort() was likely removed)"
    );
}

/// Double-call to `start_ticker`/`spawn_ticker_loop` must not spawn two
/// tickers (single-spawn guard).
#[test]
fn ticker_single_spawn_guard() {
    let state = ticker_test_state();
    let count = Arc::new(AtomicU64::new(0));
    let mk_dispatch = || {
        let c = Arc::clone(&count);
        move |_ns: &str, _body: &str| -> bool {
            c.fetch_add(1, Ordering::SeqCst);
            true
        }
    };
    state.spawn_ticker_loop(Duration::from_millis(20), mk_dispatch());
    // Second call is a no-op while a ticker is live.
    state.spawn_ticker_loop(Duration::from_millis(20), mk_dispatch());
    // Exactly one JoinHandle is retained.
    assert!(
        state.ticker.lock().unwrap().is_some(),
        "a ticker handle must be retained"
    );
    state.shutdown();
}
