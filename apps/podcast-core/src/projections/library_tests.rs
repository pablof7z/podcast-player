use super::*;
use uuid::Uuid;
#[test]
fn projection_round_trip() {
    let mut value = LibraryProjection::default();
    value
        .podcasts
        .push(PodcastSummary::new(PodcastId::new(Uuid::nil()), "Demo"));
    let json = serde_json::to_string(&value).unwrap();
    let back: LibraryProjection = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}

