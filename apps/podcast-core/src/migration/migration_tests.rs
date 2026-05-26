use super::*;
#[test]
fn combine_with_no_sources_is_empty() {
    let r = MigrationResult::combine(None, None);
    assert!(r.podcasts.is_empty());
    assert!(r.subscriptions.is_empty());
    assert!(r.episode_positions.is_empty());
    assert!(r.episodes_played.is_empty());
}
#[test]
fn migration_done_key_uses_pcst_namespace() {
    // The plan doc historically used `podcastr.migration.v1.done`; the
    // shipping key was renamed to the canonical `pcst.` namespace so
    // every NMP-side key shares a prefix.
    assert!(MIGRATION_DONE_KEY.starts_with("pcst."));
    assert!(MIGRATION_DONE_KEY.ends_with(".done"));
}

