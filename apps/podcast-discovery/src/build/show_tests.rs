use super::*;
use podcast_core::types::podcast::{Podcast, PodcastId};
use url::Url;
use uuid::Uuid;
fn fixture() -> Podcast {
    let mut p = Podcast::new("My Show");
    p.id = PodcastId::new(Uuid::parse_str("12345678-1234-1234-1234-1234567890ab").unwrap());
    p.author = "Host".into();
    p.description = "A great show".into();
    p.image_url = Some(Url::parse("https://img.example/cover.jpg").unwrap());
    p.language = Some("en".into());
    p.categories = vec!["Technology".into(), "News".into()];
    p
}
#[test]
fn d_tag_is_lowercase_uuid_with_prefix() {
    let p = fixture();
    assert_eq!(
        show_d_tag(&p),
        "podcast:guid:123456781234123412341234567890ab"
    );
}
#[test]
fn minimal_show_emits_d_and_title_only() {
    let p = Podcast::new("Title Only");
    let tags = podcast_to_show_tags(&p, "agent-pk");
    assert_eq!(tags.len(), 2);
    assert_eq!(tags[0][0], "d");
    assert_eq!(tags[1], vec!["title".to_string(), "Title Only".into()]);
}
#[test]
fn full_show_emits_every_tag_in_publisher_order() {
    let p = fixture();
    let tags = podcast_to_show_tags(&p, "agent-pk");
    let names: Vec<&str> = tags.iter().filter_map(|t| t.first().map(String::as_str)).collect();
    assert_eq!(
        names,
        vec!["d", "title", "summary", "p", "image", "language", "t", "t"]
    );
    assert_eq!(tags[3], vec!["p".to_string(), "agent-pk".into()]);
    assert_eq!(tags[6], vec!["t".to_string(), "Technology".into()]);
    assert_eq!(tags[7], vec!["t".to_string(), "News".into()]);
}
#[test]
fn show_content_uses_podcast_description() {
    assert_eq!(show_content(&fixture()), "A great show");
    assert_eq!(show_content(&Podcast::new("Empty")), "");
}

