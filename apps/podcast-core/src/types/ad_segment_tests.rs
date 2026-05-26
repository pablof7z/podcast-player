use super::*;
#[test]
fn ad_segment_round_trip() {
    let value = AdSegment::new(120.0, 150.0, AdKind::Midroll);
    let json = serde_json::to_string(&value).unwrap();
    let back: AdSegment = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}

