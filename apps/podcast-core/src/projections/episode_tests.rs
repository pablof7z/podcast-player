use super::*;
#[test]
fn projection_round_trip() {
    let mut value = EpisodeProjection::default();
    value.episodes.push(EpisodeSummary::new(
        EpisodeId::generate(),
        PodcastId::generate(),
        "Pilot",
        Utc::now(),
    ));
    let json = serde_json::to_string(&value).unwrap();
    let back: EpisodeProjection = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}

