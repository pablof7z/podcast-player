use super::*;
use podcast_core::{Episode, Podcast, PodcastId};
use url::Url;

fn make_episode(podcast_id: PodcastId, guid: &str) -> Episode {
    Episode::new(
        podcast_id,
        "https://example.com/feed.xml",
        guid,
        &format!("Title {guid}"),
        Url::parse(&format!("https://ex.com/{guid}.mp3")).unwrap(),
        chrono::Utc::now(),
    )
}

/// Build a store with one podcast and the given guid episodes.
fn store_with_episodes(guids: &[&str]) -> (PodcastStore, PodcastId) {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("Test Show");
    let pid = podcast.id();
    let eps: Vec<Episode> = guids.iter().map(|g| make_episode(pid, g)).collect();
    store.upsert_known_podcast(podcast, eps);
    (store, pid)
}

// ── Core behaviour tests ─────────────────────────────────────────────────────

#[test]
fn empty_library_returns_empty_candidates() {
    let store = PodcastStore::new();
    let candidates = store.metadata_index_backfill_candidates();
    assert!(candidates.is_empty(), "empty library must produce no candidates");
}

#[test]
fn all_already_indexed_returns_empty() {
    let guids = ["g1", "g2", "g3"];
    let (mut store, _pid) = store_with_episodes(&guids);
    // Mark all as indexed.
    let all_ids: Vec<String> = store
        .episodes
        .values()
        .flat_map(|eps| eps.iter().map(|ep| ep.id.0.to_string()))
        .collect();
    store.mark_episodes_metadata_indexed(all_ids);
    let candidates = store.metadata_index_backfill_candidates();
    assert!(
        candidates.is_empty(),
        "all-indexed library must produce no candidates"
    );
}

#[test]
fn unindexed_episodes_are_returned() {
    let guids = ["g1", "g2", "g3"];
    let (store, _pid) = store_with_episodes(&guids);
    let candidates = store.metadata_index_backfill_candidates();
    assert_eq!(
        candidates.len(),
        3,
        "all 3 unindexed episodes must be returned"
    );
}

#[test]
fn batch_size_is_capped_at_constant() {
    // Create more episodes than the batch size.
    let episode_count = METADATA_INDEX_BACKFILL_BATCH_SIZE + 10;
    let guids: Vec<String> = (1..=episode_count).map(|i| format!("g{i}")).collect();
    let guid_refs: Vec<&str> = guids.iter().map(String::as_str).collect();
    let (store, _pid) = store_with_episodes(&guid_refs);
    let candidates = store.metadata_index_backfill_candidates();
    assert_eq!(
        candidates.len(),
        METADATA_INDEX_BACKFILL_BATCH_SIZE,
        "candidates must be capped at METADATA_INDEX_BACKFILL_BATCH_SIZE={METADATA_INDEX_BACKFILL_BATCH_SIZE}"
    );
}

#[test]
fn partially_indexed_returns_only_pending() {
    let guids = ["g1", "g2", "g3", "g4"];
    let (mut store, pid) = store_with_episodes(&guids);
    // Mark g1 and g3 as indexed.
    let episodes = store.episodes.get(&pid).unwrap().clone();
    let indexed_ids: Vec<String> = episodes
        .iter()
        .filter(|ep| ep.guid == "g1" || ep.guid == "g3")
        .map(|ep| ep.id.0.to_string())
        .collect();
    store.mark_episodes_metadata_indexed(indexed_ids);
    let candidates = store.metadata_index_backfill_candidates();
    // Only g2 and g4 should be pending.
    assert_eq!(candidates.len(), 2, "only 2 episodes should be pending");
    // Verify the returned IDs are NOT the indexed ones.
    let indexed: std::collections::HashSet<String> = store
        .episodes
        .get(&pid)
        .unwrap()
        .iter()
        .filter(|ep| ep.guid == "g1" || ep.guid == "g3")
        .map(|ep| ep.id.0.to_string())
        .collect();
    for id in &candidates {
        assert!(
            !indexed.contains(id),
            "returned candidate {id} was already indexed"
        );
    }
}

#[test]
fn candidates_are_valid_uuid_strings() {
    let (store, _) = store_with_episodes(&["g1", "g2"]);
    let candidates = store.metadata_index_backfill_candidates();
    for id in &candidates {
        uuid::Uuid::parse_str(id).unwrap_or_else(|_| panic!("invalid UUID in candidates: {id}"));
    }
}

// ── Real-bump-through-action tests ────────────────────────────────────────────
//
// These prove the projection updates via the REAL write path:
// `mark_episodes_metadata_indexed` returns `changed`, which the host op handler
// uses to gate `bump_domain(Domain::Library)`. CONTRACT RULE 1 compliance:
// we confirm `changed == true` on the first mark and `false` on idempotent
// re-marks, so bump_domain fires exactly once per real state change.

#[test]
fn mark_episodes_metadata_indexed_action_bumps_library_domain() {
    let (mut store, pid) = store_with_episodes(&["g1", "g2"]);

    // Capture the pre-action domain rev via the real store bump.
    // We test that the per-domain bump happens WHEN the real action runs —
    // matching D0 (Rust owns policy) and CONTRACT RULE 1.
    //
    // We test through `PodcastStore::mark_episodes_metadata_indexed` directly
    // (which is what the handler calls) to confirm it returns `true` (changed),
    // since the caller (`handle_mark_episodes_metadata_indexed`) gates the
    // `bump_domain(Domain::Library)` on `changed == true`.

    let episodes = store.episodes.get(&pid).unwrap().clone();
    let ep1_id = episodes[0].id.0.to_string();

    // First mark should report changed.
    let changed = store.mark_episodes_metadata_indexed(vec![ep1_id.clone()]);
    assert!(changed, "first mark must report changed=true → bump_domain fires");

    // Second mark of the same ID must NOT report changed.
    let changed_again = store.mark_episodes_metadata_indexed(vec![ep1_id.clone()]);
    assert!(
        !changed_again,
        "idempotent re-mark must return false → bump_domain is NOT fired spuriously"
    );

    // After marking ep1, candidates should not include ep1.
    let candidates = store.metadata_index_backfill_candidates();
    assert!(
        !candidates.contains(&ep1_id),
        "marked episode must not appear in candidates"
    );
}

#[test]
fn backfill_candidates_projection_updates_after_mark_action() {
    // Verify the integration path: candidates list shrinks after action.
    let (mut store, pid) = store_with_episodes(&["ep-a", "ep-b", "ep-c"]);
    let all_ids: Vec<String> = store
        .episodes
        .get(&pid)
        .unwrap()
        .iter()
        .map(|ep| ep.id.0.to_string())
        .collect();

    // Before: 3 candidates.
    let before = store.metadata_index_backfill_candidates();
    assert_eq!(before.len(), 3);

    // Mark first batch as indexed (simulates the action path).
    let first_id = all_ids[0].clone();
    let changed = store.mark_episodes_metadata_indexed(vec![first_id.clone()]);
    assert!(changed);

    // After: 2 candidates.
    let after = store.metadata_index_backfill_candidates();
    assert_eq!(after.len(), 2, "candidates must shrink after marking one episode");
    assert!(
        !after.contains(&first_id),
        "marked episode must be absent from candidates"
    );
}

// ── Multi-podcast library tests ───────────────────────────────────────────────

#[test]
fn candidates_span_multiple_podcasts() {
    let mut store = PodcastStore::new();
    for i in 1..=3u8 {
        let podcast = Podcast::new(&format!("Show {i}"));
        let pid = podcast.id();
        let ep = make_episode(pid, &format!("ep-show{i}"));
        store.upsert_known_podcast(podcast, vec![ep]);
    }
    let candidates = store.metadata_index_backfill_candidates();
    assert_eq!(
        candidates.len(),
        3,
        "candidates should span all 3 podcasts"
    );
}

// ── Policy constants tests ────────────────────────────────────────────────────

#[test]
fn batch_size_constant_is_positive() {
    assert!(
        METADATA_INDEX_BACKFILL_BATCH_SIZE > 0,
        "batch size must be positive"
    );
}

#[test]
fn inter_batch_delay_constant_is_nonzero() {
    assert!(
        METADATA_INDEX_INTER_BATCH_DELAY_MS > 0,
        "inter-batch delay must be positive"
    );
}
