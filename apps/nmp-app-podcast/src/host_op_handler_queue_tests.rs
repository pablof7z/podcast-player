use super::*;
fn fresh() -> (Arc<Mutex<PlaybackQueue>>, Arc<AtomicU64>) {
    (
        Arc::new(Mutex::new(PlaybackQueue::new())),
        Arc::new(AtomicU64::new(0)),
    )
}
#[test]
fn add_next_pushes_front_and_bumps_rev() {
    let (q, rev) = fresh();
    let result = handle_queue_action(
        &q,
        &rev,
        QueueAction::AddNext { episode_id: "ep-1".into() },
    );
    assert_eq!(result, serde_json::json!({"ok": true}));
    assert_eq!(q.lock().unwrap().items(), &["ep-1".to_owned()]);
    assert_eq!(rev.load(Ordering::Relaxed), 1);
}
#[test]
fn add_last_pushes_back_and_bumps_rev() {
    let (q, rev) = fresh();
    handle_queue_action(
        &q,
        &rev,
        QueueAction::AddLast { episode_id: "ep-1".into() },
    );
    handle_queue_action(
        &q,
        &rev,
        QueueAction::AddLast { episode_id: "ep-2".into() },
    );
    assert_eq!(
        q.lock().unwrap().items(),
        &["ep-1".to_owned(), "ep-2".to_owned()]
    );
    assert_eq!(rev.load(Ordering::Relaxed), 2);
}
#[test]
fn remove_drops_episode_and_bumps_rev() {
    let (q, rev) = fresh();
    handle_queue_action(
        &q,
        &rev,
        QueueAction::AddLast { episode_id: "ep-1".into() },
    );
    handle_queue_action(
        &q,
        &rev,
        QueueAction::AddLast { episode_id: "ep-2".into() },
    );
    let pre_rev = rev.load(Ordering::Relaxed);
    let result = handle_queue_action(
        &q,
        &rev,
        QueueAction::Remove { episode_id: "ep-1".into() },
    );
    assert_eq!(result, serde_json::json!({"ok": true}));
    assert_eq!(q.lock().unwrap().items(), &["ep-2".to_owned()]);
    assert_eq!(rev.load(Ordering::Relaxed), pre_rev + 1);
}
#[test]
fn clear_empties_queue_and_bumps_rev() {
    let (q, rev) = fresh();
    handle_queue_action(
        &q,
        &rev,
        QueueAction::AddLast { episode_id: "ep-1".into() },
    );
    handle_queue_action(
        &q,
        &rev,
        QueueAction::AddLast { episode_id: "ep-2".into() },
    );
    let pre_rev = rev.load(Ordering::Relaxed);
    let result = handle_queue_action(&q, &rev, QueueAction::Clear);
    assert_eq!(result, serde_json::json!({"ok": true}));
    assert!(q.lock().unwrap().items().is_empty());
    assert_eq!(rev.load(Ordering::Relaxed), pre_rev + 1);
}

