use super::*;
#[test]
fn anchor_note_round_trip() {
    let value = Anchor::Note { id: Uuid::nil() };
    let json = serde_json::to_string(&value).unwrap();
    let back: Anchor = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}
#[test]
fn anchor_episode_round_trip() {
    let value = Anchor::Episode {
        id: Uuid::nil(),
        position_seconds: 42.5,
    };
    let json = serde_json::to_string(&value).unwrap();
    let back: Anchor = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}

