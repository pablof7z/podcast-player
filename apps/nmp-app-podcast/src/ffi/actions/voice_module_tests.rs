use super::*;
#[test]
fn activate_action_round_trips() {
    let action = VoiceAction::Activate;
    let json = serde_json::to_string(&action).expect("encode");
    assert_eq!(json, r#"{"op":"activate"}"#);
    let decoded: VoiceAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn deactivate_action_round_trips() {
    let action = VoiceAction::Deactivate;
    let json = serde_json::to_string(&action).expect("encode");
    assert_eq!(json, r#"{"op":"deactivate"}"#);
    let decoded: VoiceAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn speak_action_round_trips_with_voice_id() {
    let action = VoiceAction::Speak {
        text: "hello world".into(),
        voice_id: Some("rachel".into()),
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"speak""#));
    assert!(json.contains(r#""text":"hello world""#));
    assert!(json.contains(r#""voice_id":"rachel""#));
    let decoded: VoiceAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn speak_action_omits_none_voice_id() {
    let action = VoiceAction::Speak {
        text: "hi".into(),
        voice_id: None,
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert_eq!(json, r#"{"op":"speak","text":"hi"}"#);
}
#[test]
fn stop_and_set_voice_round_trip() {
    assert_eq!(
        serde_json::to_string(&VoiceAction::Stop).expect("encode"),
        r#"{"op":"stop"}"#
    );
    let sv = VoiceAction::SetVoice {
        voice_id: "rachel".into(),
    };
    let json = serde_json::to_string(&sv).expect("encode");
    assert_eq!(json, r#"{"op":"set_voice","voice_id":"rachel"}"#);
    let decoded: VoiceAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, sv);
}
#[test]
fn execute_emits_dispatch_host_op() {
    let action = VoiceAction::Activate;
    let commands = std::sync::Mutex::new(Vec::<ActorCommand>::new());
    VoiceActionModule::execute(action, "corr-1", &|cmd| {
        commands.lock().unwrap().push(cmd);
    })
    .expect("execute ok");
    let commands = commands.into_inner().unwrap();
    assert_eq!(commands.len(), 1);
    let ActorCommand::DispatchHostOp {
        action_json,
        correlation_id,
    } = &commands[0]
    else {
        panic!("expected DispatchHostOp");
    };
    assert_eq!(correlation_id, "corr-1");
    let v: serde_json::Value = serde_json::from_str(action_json).expect("json");
    assert_eq!(v["op"], "activate");
}

