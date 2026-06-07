use super::*;
fn fresh() -> (Arc<Mutex<PodcastStore>>, Arc<AtomicU64>) {
    (
        Arc::new(Mutex::new(PodcastStore::new())),
        Arc::new(AtomicU64::new(0)),
    )
}
#[test]
fn remember_writes_through_to_store_and_bumps_rev() {
    let (store, rev) = fresh();
    let resp = handle(
        MemoryAction::Remember {
            key: "k".into(),
            value: "v".into(),
            source: None,
        },
        &store,
        &rev,
    );
    assert_eq!(resp["ok"], true);
    assert_eq!(rev.load(Ordering::Relaxed), 1);
    let facts = store.lock().unwrap().all_memory_facts();
    assert_eq!(facts.len(), 1);
    // Missing source defaults to "user".
    assert_eq!(facts[0].source, "user");
    assert_eq!(facts[0].key, "k");
}
#[test]
fn remember_with_explicit_agent_source_is_recorded() {
    let (store, rev) = fresh();
    let resp = handle(
        MemoryAction::Remember {
            key: "k".into(),
            value: "v".into(),
            source: Some("agent".into()),
        },
        &store,
        &rev,
    );
    assert_eq!(resp["ok"], true);
    assert_eq!(store.lock().unwrap().all_memory_facts()[0].source, "agent");
}
#[test]
fn remember_rejects_empty_key() {
    let (store, rev) = fresh();
    let resp = handle(
        MemoryAction::Remember {
            key: "   ".into(),
            value: "v".into(),
            source: None,
        },
        &store,
        &rev,
    );
    assert_eq!(resp["ok"], false);
    // Rejected ⇒ no rev bump, no store write.
    assert_eq!(rev.load(Ordering::Relaxed), 0);
    assert!(store.lock().unwrap().all_memory_facts().is_empty());
}
#[test]
fn forget_existing_key_bumps_rev() {
    let (store, rev) = fresh();
    store
        .lock()
        .unwrap()
        .set_memory_fact("k".into(), "v".into(), "user".into(), 1);
    let resp = handle(MemoryAction::Forget { key: "k".into() }, &store, &rev);
    assert_eq!(resp["ok"], true);
    assert_eq!(rev.load(Ordering::Relaxed), 1);
    assert!(store.lock().unwrap().all_memory_facts().is_empty());
}
#[test]
fn forget_missing_key_is_ok_without_rev_bump() {
    let (store, rev) = fresh();
    let resp = handle(MemoryAction::Forget { key: "k".into() }, &store, &rev);
    assert_eq!(resp["ok"], true);
    // Nothing changed — no need to re-poll the snapshot.
    assert_eq!(rev.load(Ordering::Relaxed), 0);
}
#[test]
fn forget_all_clears_and_bumps_rev_once_when_non_empty() {
    let (store, rev) = fresh();
    store
        .lock()
        .unwrap()
        .set_memory_fact("a".into(), "1".into(), "user".into(), 1);
    store
        .lock()
        .unwrap()
        .set_memory_fact("b".into(), "2".into(), "user".into(), 2);
    let resp = handle(MemoryAction::ForgetAll, &store, &rev);
    assert_eq!(resp["ok"], true);
    // One bump for the whole wipe — not one per fact.
    assert_eq!(rev.load(Ordering::Relaxed), 1);
    assert!(store.lock().unwrap().all_memory_facts().is_empty());
}
#[test]
fn forget_all_on_empty_store_is_noop_without_rev_bump() {
    let (store, rev) = fresh();
    let resp = handle(MemoryAction::ForgetAll, &store, &rev);
    assert_eq!(resp["ok"], true);
    assert_eq!(rev.load(Ordering::Relaxed), 0);
}
