use super::*;
#[test]
fn chapter_round_trip() {
    let value = Chapter::new("Intro", 0.0);
    let json = serde_json::to_string(&value).unwrap();
    let back: Chapter = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}

