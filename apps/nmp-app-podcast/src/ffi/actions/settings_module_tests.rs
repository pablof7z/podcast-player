use super::*;
#[test]
fn set_skip_intervals_round_trips() {
    let action = SettingsAction::SetSkipIntervals { forward_secs: 45.0, backward_secs: 10.0 };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"set_skip_intervals""#));
    assert!(json.contains(r#""forward_secs":45.0"#) || json.contains(r#""forward_secs":45"#));
    let decoded: SettingsAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn set_auto_skip_ads_round_trips() {
    let action = SettingsAction::SetAutoSkipAds { enabled: true };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"set_auto_skip_ads""#));
    assert!(json.contains(r#""enabled":true"#));
    let decoded: SettingsAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn execute_emits_dispatch_host_op() {
    let action = SettingsAction::SetAutoSkipAds { enabled: false };
    let commands = std::sync::Mutex::new(Vec::<ActorCommand>::new());
    SettingsActionModule::execute(action, "corr-1", &|cmd| {
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
    assert_eq!(v["op"], "set_auto_skip_ads");
    assert_eq!(v["enabled"], false);
}

