use super::*;
#[test]
fn clip_round_trip() {
    let value = Clip::new(EpisodeId::generate(), PodcastId::generate(), 1000, 4000);
    let json = serde_json::to_string(&value).unwrap();
    let back: Clip = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
    assert_eq!(value.duration_secs(), 3.0);
}
#[test]
fn boundary_round_trip() {
    let value = ClipBoundary {
        start_ms: 0,
        end_ms: 5000,
    };
    let json = serde_json::to_string(&value).unwrap();
    let back: ClipBoundary = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}

