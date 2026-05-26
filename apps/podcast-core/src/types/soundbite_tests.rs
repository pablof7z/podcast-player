use super::*;
#[test]
fn soundbite_round_trip() {
    let mut value = SoundBite::new(10.0, 30.0);
    value.title = Some("Highlight".into());
    let json = serde_json::to_string(&value).unwrap();
    let back: SoundBite = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}

