use super::*;
#[test]
fn triage_action_round_trips() {
    let action = InboxAction::Triage;
    let json = serde_json::to_string(&action).expect("encode");
    assert_eq!(json, r#"{"op":"triage"}"#);
    let decoded: InboxAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn dismiss_action_round_trips() {
    let action = InboxAction::Dismiss {
        episode_id: "ep-7".into(),
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"dismiss""#));
    assert!(json.contains(r#""episode_id":"ep-7""#));
    let decoded: InboxAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn mark_listened_action_round_trips() {
    let action = InboxAction::MarkListened {
        episode_id: "ep-7".into(),
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"mark_listened""#));
    assert!(json.contains(r#""episode_id":"ep-7""#));
    let decoded: InboxAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn mark_unlistened_action_round_trips() {
    let action = InboxAction::MarkUnlistened {
        episode_id: "ep-7".into(),
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"mark_unlistened""#));
    assert!(json.contains(r#""episode_id":"ep-7""#));
    let decoded: InboxAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn execute_emits_dispatch_host_op() {
    let action = InboxAction::Dismiss {
        episode_id: "ep-7".into(),
    };
    let commands = std::sync::Mutex::new(Vec::<ActorCommand>::new());
    InboxActionModule::execute(action, "corr-1", &|cmd| {
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
    assert_eq!(v["op"], "dismiss");
    assert_eq!(v["episode_id"], "ep-7");
}

