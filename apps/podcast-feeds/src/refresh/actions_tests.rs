use super::*;

#[test]
fn refresh_feed_action_round_trip() {
    let action = RefreshFeedAction {
        podcast_id: PodcastId::generate(),
        feed_url: Url::parse("https://example.com/feed.xml").unwrap(),
    };
    let json = serde_json::to_string(&action).unwrap();
    let back: RefreshFeedAction = serde_json::from_str(&json).unwrap();
    assert_eq!(action, back);
}

#[test]
fn import_opml_action_round_trip() {
    let action = ImportOpmlAction {
        opml_xml: "<opml/>".into(),
    };
    let json = serde_json::to_string(&action).unwrap();
    let back: ImportOpmlAction = serde_json::from_str(&json).unwrap();
    assert_eq!(action, back);
}
