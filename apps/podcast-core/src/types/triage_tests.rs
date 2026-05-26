use super::*;
#[test]
fn triage_round_trip() {
    let value = TriageDecision::Inbox;
    let json = serde_json::to_string(&value).unwrap();
    let back: TriageDecision = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}

