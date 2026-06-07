use super::*;
use podcast_core::AdKind;
fn seg(start: f64, end: f64) -> AdSegment {
    AdSegment::new(start, end, AdKind::Midroll)
}
#[test]
fn contains_left_edge_inclusive() {
    let s = seg(10.0, 20.0);
    assert!(contains(&s, 10.0), "left edge must be inclusive");
}
#[test]
fn contains_right_edge_exclusive() {
    let s = seg(10.0, 20.0);
    assert!(!contains(&s, 20.0), "right edge must be exclusive");
    assert!(contains(&s, 19.999));
}
#[test]
fn contains_outside_interval_is_false() {
    let s = seg(10.0, 20.0);
    assert!(!contains(&s, 9.999));
    assert!(!contains(&s, 25.0));
}
#[test]
fn round_trips_through_json() {
    let s = seg(60.0, 90.0);
    let json = serde_json::to_string(&s).expect("encode");
    assert!(json.contains("\"start_secs\":60"));
    let decoded: AdSegment = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, s);
}
