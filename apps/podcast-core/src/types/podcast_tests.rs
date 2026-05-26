use super::*;
#[test]
fn podcast_id_unknown_matches_swift_sentinel() {
    // UUIDs print lowercase via `Display`; the Swift literal is upper-case
    // but UUID equality is hex-case-insensitive so the lowercase form is
    // what we compare against.
    let id = PodcastId::unknown();
    assert_eq!(
        id.0.to_string(),
        "00000000-eeee-eeee-eeee-000000000000"
    );
}
#[test]
fn podcast_round_trip() {
    let mut value = Podcast::new("My Show");
    value.author = "Host".into();
    value.feed_url = Some(Url::parse("https://example.com/feed.xml").unwrap());
    value.categories = vec!["Technology".into(), "News".into()];
    let json = serde_json::to_string(&value).unwrap();
    let back: Podcast = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}
#[test]
fn synthetic_unknown_round_trip() {
    let value = Podcast::unknown();
    let json = serde_json::to_string(&value).unwrap();
    let back: Podcast = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
    assert_eq!(value.id, PodcastId::unknown());
}

