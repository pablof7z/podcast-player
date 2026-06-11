use super::*;
#[test]
fn generate_action_round_trips() {
    let action = WikiAction::Generate {
        podcast_id: "pod-1".into(),
        topic: "Bitcoin halvings".into(),
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"generate""#));
    assert!(json.contains(r#""podcast_id":"pod-1""#));
    assert!(json.contains(r#""topic":"Bitcoin halvings""#));
    let decoded: WikiAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn delete_action_round_trips() {
    let action = WikiAction::Delete {
        article_id: "art-7".into(),
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"delete""#));
    assert!(json.contains(r#""article_id":"art-7""#));
    let decoded: WikiAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn search_action_round_trips() {
    let action = WikiAction::Search {
        query: "halving".into(),
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"search""#));
    assert!(json.contains(r#""query":"halving""#));
    let decoded: WikiAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn execute_emits_dispatch_host_op() {
    let action = WikiAction::Generate {
        podcast_id: "pod-1".into(),
        topic: "topic".into(),
    };
    let commands = std::sync::Mutex::new(Vec::<ActorCommand>::new());
    WikiActionModule::execute(action, "corr-1", &|cmd| {
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
    assert_eq!(v["ns"], "podcast.wiki");
    assert_eq!(v["action"]["op"], "generate");
}
#[test]
fn namespace_is_podcast_wiki() {
    assert_eq!(WikiActionModule::NAMESPACE, "podcast.wiki");
}
