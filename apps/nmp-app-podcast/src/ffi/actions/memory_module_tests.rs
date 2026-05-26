use super::*;
#[test]
fn remember_action_round_trips_with_explicit_source() {
    let a = MemoryAction::Remember {
        key: "preferred_genre".into(),
        value: "technology".into(),
        source: Some("agent".into()),
    };
    let json = serde_json::to_string(&a).expect("encode");
    assert!(json.contains(r#""op":"remember""#));
    assert!(json.contains(r#""source":"agent""#));
    let decoded: MemoryAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, a);
}
#[test]
fn remember_action_omits_none_source_on_wire() {
    let a = MemoryAction::Remember {
        key: "k".into(),
        value: "v".into(),
        source: None,
    };
    let json = serde_json::to_string(&a).expect("encode");
    // `skip_serializing_if = "Option::is_none"` keeps the wire shape
    // narrow when the caller wants the default.
    assert!(!json.contains("source"));
    let decoded: MemoryAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, a);
}
#[test]
fn remember_action_decodes_without_source_field() {
    // A hand-written call from Settings doesn't include `source`.
    let json = r#"{"op":"remember","key":"k","value":"v"}"#;
    let decoded: MemoryAction = serde_json::from_str(json).expect("decode");
    assert_eq!(
        decoded,
        MemoryAction::Remember {
            key: "k".into(),
            value: "v".into(),
            source: None,
        }
    );
}
#[test]
fn forget_action_round_trips() {
    let a = MemoryAction::Forget {
        key: "preferred_genre".into(),
    };
    let json = serde_json::to_string(&a).expect("encode");
    assert!(json.contains(r#""op":"forget""#));
    assert!(json.contains(r#""key":"preferred_genre""#));
    let decoded: MemoryAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, a);
}
#[test]
fn forget_all_action_round_trips_as_bare_op() {
    let a = MemoryAction::ForgetAll;
    let json = serde_json::to_string(&a).expect("encode");
    assert_eq!(json, r#"{"op":"forget_all"}"#);
    let decoded: MemoryAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, a);
}
#[test]
fn execute_emits_dispatch_host_op() {
    let action = MemoryAction::Remember {
        key: "k".into(),
        value: "v".into(),
        source: None,
    };
    let commands = std::sync::Mutex::new(Vec::<ActorCommand>::new());
    MemoryActionModule::execute(action, "corr-7", &|cmd| {
        commands.lock().unwrap().push(cmd);
    })
    .expect("execute ok");
    let commands = commands.into_inner().unwrap();
    assert_eq!(commands.len(), 1);
    let ActorCommand::DispatchHostOp { action_json, correlation_id } = &commands[0] else {
        panic!("expected DispatchHostOp");
    };
    assert_eq!(correlation_id, "corr-7");
    let v: serde_json::Value = serde_json::from_str(action_json).expect("json");
    assert_eq!(v["op"], "remember");
}

