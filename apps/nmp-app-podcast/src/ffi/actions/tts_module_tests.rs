use super::*;
#[test]
fn namespace_matches_documented_string() {
    assert_eq!(TTS_NAMESPACE, "podcast.tts");
    assert_eq!(TtsEpisodeModule::NAMESPACE, "podcast.tts");
}
#[test]
fn action_ids_match_documented_strings() {
    assert_eq!(ACTION_TTS_GENERATE, "podcast.tts.generate");
    assert_eq!(ACTION_TTS_DELETE, "podcast.tts.delete");
    assert_eq!(ACTION_TTS_PLAY, "podcast.tts.play");
}
#[test]
fn generate_action_round_trips_with_length() {
    let action = TtsEpisodeAction::Generate {
        topic: "AI news this week".into(),
        length_minutes: Some(7),
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"generate""#));
    assert!(json.contains(r#""topic":"AI news this week""#));
    assert!(json.contains(r#""length_minutes":7"#));
    let decoded: TtsEpisodeAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn generate_action_omits_none_length() {
    let action = TtsEpisodeAction::Generate {
        topic: "Anything".into(),
        length_minutes: None,
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert_eq!(json, r#"{"op":"generate","topic":"Anything"}"#);
    let decoded: TtsEpisodeAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn delete_action_round_trips() {
    let action = TtsEpisodeAction::Delete {
        episode_id: "tts-1".into(),
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"delete""#));
    assert!(json.contains(r#""episode_id":"tts-1""#));
    let decoded: TtsEpisodeAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn play_action_round_trips() {
    let action = TtsEpisodeAction::Play {
        episode_id: "tts-1".into(),
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"play""#));
    assert!(json.contains(r#""episode_id":"tts-1""#));
    let decoded: TtsEpisodeAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn execute_emits_dispatch_host_op() {
    let action = TtsEpisodeAction::Generate {
        topic: "Test".into(),
        length_minutes: None,
    };
    let commands = std::sync::Mutex::new(Vec::<ActorCommand>::new());
    TtsEpisodeModule::execute(action, "corr-tts-1", &|cmd| {
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
    assert_eq!(correlation_id, "corr-tts-1");
    let v: serde_json::Value = serde_json::from_str(action_json).expect("json");
    assert_eq!(v["op"], "generate");
    assert_eq!(v["topic"], "Test");
}

