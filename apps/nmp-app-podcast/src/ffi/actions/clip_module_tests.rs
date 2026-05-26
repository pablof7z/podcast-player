use super::*;
#[test]
fn action_ids_match_documented_strings() {
    assert_eq!(ACTION_CLIP_CREATE, "podcast.clip.create");
    assert_eq!(ACTION_CLIP_DELETE, "podcast.clip.delete");
    assert_eq!(ACTION_CLIP_AUTO_SNIP, "podcast.clip.auto_snip");
}
#[test]
fn create_action_round_trips_with_title() {
    let action = ClipAction::Create {
        episode_id: "ep-1".into(),
        start_secs: 10.0,
        end_secs: 70.0,
        title: Some("Marcus on retrieval".into()),
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"create""#));
    assert!(json.contains(r#""episode_id":"ep-1""#));
    assert!(json.contains(r#""start_secs":10.0"#));
    assert!(json.contains(r#""end_secs":70.0"#));
    assert!(json.contains(r#""title":"Marcus on retrieval""#));
    let decoded: ClipAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn create_action_omits_none_title() {
    let action = ClipAction::Create {
        episode_id: "ep-1".into(),
        start_secs: 10.0,
        end_secs: 70.0,
        title: None,
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(!json.contains("\"title\""));
    let decoded: ClipAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn delete_action_round_trips() {
    let action = ClipAction::Delete {
        clip_id: "clip-1".into(),
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"delete""#));
    assert!(json.contains(r#""clip_id":"clip-1""#));
    let decoded: ClipAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn auto_snip_action_round_trips() {
    let action = ClipAction::AutoSnip {
        episode_id: "ep-1".into(),
        position_secs: 100.0,
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"auto_snip""#));
    assert!(json.contains(r#""episode_id":"ep-1""#));
    assert!(json.contains(r#""position_secs":100.0"#));
    let decoded: ClipAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn execute_emits_dispatch_host_op() {
    let action = ClipAction::Delete {
        clip_id: "clip-7".into(),
    };
    let commands = std::sync::Mutex::new(Vec::<ActorCommand>::new());
    ClipActionModule::execute(action, "corr-1", &|cmd| {
        commands.lock().unwrap().push(cmd);
    })
    .expect("execute ok");
    let commands = commands.into_inner().unwrap();
    assert_eq!(commands.len(), 1);
    let ActorCommand::DispatchHostOp { action_json, correlation_id } = &commands[0] else {
        panic!("expected DispatchHostOp");
    };
    assert_eq!(correlation_id, "corr-1");
    let v: serde_json::Value = serde_json::from_str(action_json).expect("json");
    assert_eq!(v["op"], "delete");
    assert_eq!(v["clip_id"], "clip-7");
}

