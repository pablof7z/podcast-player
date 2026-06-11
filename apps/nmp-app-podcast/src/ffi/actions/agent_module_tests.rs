use super::*;
#[test]
fn send_action_round_trips() {
    let action = AgentChatAction::Send {
        message: "What's new today?".into(),
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"send""#));
    assert!(json.contains(r#""message":"What's new today?""#));
    let decoded: AgentChatAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn clear_action_round_trips() {
    let action = AgentChatAction::Clear;
    let json = serde_json::to_string(&action).expect("encode");
    assert_eq!(json, r#"{"op":"clear"}"#);
    let decoded: AgentChatAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn namespace_is_podcast_agent() {
    assert_eq!(AgentActionModule::NAMESPACE, "podcast.agent");
}
#[test]
fn execute_emits_dispatch_host_op() {
    let action = AgentChatAction::Send {
        message: "hi".into(),
    };
    let commands = std::sync::Mutex::new(Vec::<ActorCommand>::new());
    AgentActionModule::execute(action, "corr-1", &|cmd| {
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
    assert_eq!(v["ns"], "podcast.agent");
    assert_eq!(v["action"]["op"], "send");
    assert_eq!(v["action"]["message"], "hi");
}
