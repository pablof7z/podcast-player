use super::*;
#[test]
fn activity_type_ids_match_documented_strings() {
    assert_eq!(HANDOFF_ACTIVITY_PLAYING, "io.f7z.podcast.playing");
    assert_eq!(HANDOFF_ACTIVITY_BROWSING, "io.f7z.podcast.browsing");
}
#[test]
fn playing_constructor_populates_episode_and_position() {
    let state = HandoffState::playing("ep-1", 42.5);
    assert_eq!(state.activity_type, HANDOFF_ACTIVITY_PLAYING);
    assert_eq!(state.episode_id.as_deref(), Some("ep-1"));
    assert_eq!(state.position_secs, Some(42.5));
    assert!(state.podcast_id.is_none());
    assert!(state.is_known_activity());
}
#[test]
fn browsing_constructor_populates_podcast() {
    let state = HandoffState::browsing_podcast("pod-1");
    assert_eq!(state.activity_type, HANDOFF_ACTIVITY_BROWSING);
    assert_eq!(state.podcast_id.as_deref(), Some("pod-1"));
    assert!(state.episode_id.is_none());
    assert!(state.position_secs.is_none());
    assert!(state.is_known_activity());
}
#[test]
fn is_known_activity_rejects_unknown_string() {
    let state = HandoffState {
        activity_type: "io.f7z.podcast.future_activity".to_owned(),
        episode_id: None,
        podcast_id: None,
        position_secs: None,
    };
    assert!(!state.is_known_activity());
}
#[test]
fn handoff_state_round_trips_through_json() {
    let state = HandoffState::playing("ep-1", 12.0);
    let json = serde_json::to_string(&state).expect("encode");
    let decoded: HandoffState = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, state);
}
#[test]
fn handoff_state_omits_none_fields_in_json() {
    let state = HandoffState::browsing_podcast("pod-1");
    let json = serde_json::to_string(&state).expect("encode");
    assert!(!json.contains("episode_id"));
    assert!(!json.contains("position_secs"));
    assert!(json.contains("podcast_id"));
    assert!(json.contains("activity_type"));
}

