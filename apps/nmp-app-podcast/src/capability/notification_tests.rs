use super::*;
#[test]
fn namespace_matches_canonical_capability_plan() {
    assert_eq!(
        NOTIFICATION_CAPABILITY_NAMESPACE,
        "nmp.notification.capability"
    );
}
#[test]
fn schedule_new_episode_serde_roundtrips() {
    let cmd = NotificationCommand::schedule_new_episode(
        "The Big Reveal",
        "Mystery Hour",
        "ep-42",
    );
    let json = serde_json::to_string(&cmd).expect("encode");
    assert!(json.contains("\"type\":\"schedule_new_episode\""));
    assert!(json.contains("\"episode_title\":\"The Big Reveal\""));
    assert!(json.contains("\"podcast_title\":\"Mystery Hour\""));
    assert!(json.contains("\"episode_id\":\"ep-42\""));
    let decoded: NotificationCommand = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, cmd);
}
#[test]
fn notification_command_json_helper_round_trips() {
    let cmd = NotificationCommand::schedule_new_episode(
        "Episode Two",
        "Podcast One",
        "ep-2",
    );
    let json = notification_command_json(&cmd);
    let decoded: NotificationCommand = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, cmd);
}
#[test]
fn wire_keys_are_snake_case() {
    // The Swift `Codable` decoder uses snake_case keys to match the Rust
    // `#[serde(rename_all = "snake_case")]` on the variant fields. Lock
    // that contract here so renaming a field on either side trips the test.
    let cmd = NotificationCommand::schedule_new_episode("t", "p", "id");
    let json = serde_json::to_string(&cmd).expect("encode");
    assert!(!json.contains("episodeTitle"));
    assert!(!json.contains("podcastTitle"));
    assert!(!json.contains("episodeId"));
}

