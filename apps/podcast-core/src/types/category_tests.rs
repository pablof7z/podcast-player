use super::*;
#[test]
fn category_round_trip() {
    let value = PodcastCategory::new("Tech Deep-Dives", "tech-deep-dives");
    let json = serde_json::to_string(&value).unwrap();
    let back: PodcastCategory = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}

