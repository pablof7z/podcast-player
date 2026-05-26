use super::*;
#[test]
fn voice_action_ids_match_documented_strings() {
    assert_eq!(ACTION_VOICE_SPEAK, "podcast.voice.speak");
    assert_eq!(ACTION_VOICE_STOP, "podcast.voice.stop");
    assert_eq!(ACTION_VOICE_SET_VOICE, "podcast.voice.set_voice");
}
#[test]
fn speak_action_round_trips_with_voice_id() {
    let a = SpeakAction {
        text: "hello world".into(),
        voice_id: Some("rachel".into()),
    };
    let json = serde_json::to_string(&a).expect("encode");
    assert!(json.contains("\"text\":\"hello world\""));
    assert!(json.contains("\"voice_id\":\"rachel\""));
    let decoded: SpeakAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, a);
}
#[test]
fn speak_action_omits_none_voice_id() {
    let a = SpeakAction {
        text: "hi".into(),
        voice_id: None,
    };
    let json = serde_json::to_string(&a).expect("encode");
    assert_eq!(json, r#"{"text":"hi"}"#);
    let decoded: SpeakAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, a);
}
#[test]
fn stop_voice_action_is_unit_struct() {
    let a = StopVoiceAction;
    let json = serde_json::to_string(&a).expect("encode");
    assert_eq!(json, "null");
}
#[test]
fn set_voice_action_round_trips() {
    let a = SetVoiceAction {
        voice_id: "rachel".into(),
    };
    let json = serde_json::to_string(&a).expect("encode");
    assert_eq!(json, r#"{"voice_id":"rachel"}"#);
    let decoded: SetVoiceAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, a);
}

