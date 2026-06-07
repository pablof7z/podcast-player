use super::*;
#[test]
fn play_latest_no_podcast_id() {
    let action = SiriAction::PlayLatest { podcast_id: None };
    let json = serde_json::to_string(&action).expect("encode");
    assert_eq!(json, r#"{"op":"play_latest"}"#);
    let decoded: SiriAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn play_latest_with_podcast_id() {
    let action = SiriAction::PlayLatest {
        podcast_id: Some("pod-42".into()),
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"play_latest""#));
    assert!(json.contains(r#""podcast_id":"pod-42""#));
    let decoded: SiriAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn resume_is_unit_variant() {
    let action = SiriAction::Resume;
    let json = serde_json::to_string(&action).expect("encode");
    assert_eq!(json, r#"{"op":"resume"}"#);
    let decoded: SiriAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn execute_emits_dispatch_host_op() {
    let action = SiriAction::Resume;
    let commands = std::sync::Mutex::new(Vec::<ActorCommand>::new());
    SiriActionModule::execute(action, "corr-siri", &|cmd| {
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
    assert_eq!(correlation_id, "corr-siri");
    let v: serde_json::Value = serde_json::from_str(action_json).expect("json");
    assert_eq!(v["op"], "resume");
}
