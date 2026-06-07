use super::*;
#[test]
fn add_next_action_round_trips() {
    let action = QueueAction::AddNext {
        episode_id: "ep-7".into(),
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"add_next""#));
    assert!(json.contains(r#""episode_id":"ep-7""#));
    let decoded: QueueAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn add_last_action_round_trips() {
    let action = QueueAction::AddLast {
        episode_id: "ep-7".into(),
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"add_last""#));
    assert!(json.contains(r#""episode_id":"ep-7""#));
    let decoded: QueueAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn remove_action_round_trips() {
    let action = QueueAction::Remove {
        episode_id: "ep-7".into(),
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"remove""#));
    assert!(json.contains(r#""episode_id":"ep-7""#));
    let decoded: QueueAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn clear_action_round_trips() {
    let action = QueueAction::Clear;
    let json = serde_json::to_string(&action).expect("encode");
    assert_eq!(json, r#"{"op":"clear"}"#);
    let decoded: QueueAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn execute_emits_dispatch_host_op() {
    let action = QueueAction::AddNext {
        episode_id: "ep-7".into(),
    };
    let commands = std::sync::Mutex::new(Vec::<ActorCommand>::new());
    QueueActionModule::execute(action, "corr-1", &|cmd| {
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
    assert_eq!(v["op"], "add_next");
    assert_eq!(v["episode_id"], "ep-7");
}
#[test]
fn namespace_is_podcast_queue() {
    assert_eq!(QueueActionModule::NAMESPACE, "podcast.queue");
}
