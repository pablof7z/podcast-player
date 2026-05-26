use super::*;
#[test]
fn action_ids_match_documented_strings() {
    assert_eq!(ACTION_PUBLISH_SHOW, "podcast.nip74.publish_show");
    assert_eq!(ACTION_PUBLISH_EPISODE, "podcast.nip74.publish_episode");
    assert_eq!(ACTION_DISCOVER_PODCASTS, "podcast.nip74.discover");
}
#[test]
fn publish_show_round_trips() {
    let a = PublishShowAction {
        podcast_id: "p-1".into(),
    };
    let json = serde_json::to_string(&a).expect("encode");
    assert_eq!(json, r#"{"podcast_id":"p-1"}"#);
    let back: PublishShowAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(back, a);
}
#[test]
fn publish_episode_round_trips() {
    let a = PublishEpisodeAction {
        episode_id: "e-1".into(),
    };
    let json = serde_json::to_string(&a).expect("encode");
    assert_eq!(json, r#"{"episode_id":"e-1"}"#);
    let back: PublishEpisodeAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(back, a);
}
#[test]
fn discover_omits_none_fields() {
    let a = DiscoverPodcastsAction::default();
    let json = serde_json::to_string(&a).expect("encode");
    assert_eq!(json, "{}");
    let back: DiscoverPodcastsAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(back, a);
}
#[test]
fn discover_round_trips_with_all_fields() {
    let a = DiscoverPodcastsAction {
        query: Some("AI".into()),
        limit: Some(20),
        relay_url: Some("wss://relay.damus.io".into()),
    };
    let json = serde_json::to_string(&a).expect("encode");
    let back: DiscoverPodcastsAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(back, a);
}

