use super::*;
#[test]
fn from_episode_db_returns_unsupported_until_implemented() {
    // The capability should still happily call us; the shell handles
    // the error envelope.
    let err = from_episode_db(b"").expect_err("stub must error");
    assert!(matches!(err, MigrationError::EpisodeDbUnsupported(_)));
    // Display impl must be human-readable — toast surfaces this verbatim.
    assert!(format!("{err}").contains("not yet supported"));
}
#[test]
fn empty_result_default_is_truly_empty() {
    let r = EpisodeDbResult::default();
    assert!(r.episodes.is_empty());
    assert!(r.episode_positions.is_empty());
    assert!(r.episodes_played.is_empty());
}

