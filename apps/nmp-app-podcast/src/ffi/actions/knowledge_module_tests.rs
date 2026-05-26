use super::*;
#[test]
fn knowledge_action_ids_match_documented_strings() {
    assert_eq!(ACTION_KNOWLEDGE_SEARCH, "podcast.knowledge.search");
    assert_eq!(
        ACTION_KNOWLEDGE_CLEAR_RESULTS,
        "podcast.knowledge.clear_results"
    );
    assert_eq!(
        ACTION_KNOWLEDGE_INDEX_EPISODE,
        "podcast.knowledge.index_episode"
    );
}
#[test]
fn search_action_round_trips() {
    let action = KnowledgeAction::Search {
        query: "machine learning".into(),
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"search""#));
    assert!(json.contains(r#""query":"machine learning""#));
    let decoded: KnowledgeAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn clear_results_action_round_trips() {
    let action = KnowledgeAction::ClearResults;
    let json = serde_json::to_string(&action).expect("encode");
    assert_eq!(json, r#"{"op":"clear_results"}"#);
    let decoded: KnowledgeAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn index_episode_action_round_trips() {
    let action = KnowledgeAction::IndexEpisode {
        episode_id: "ep-42".into(),
    };
    let json = serde_json::to_string(&action).expect("encode");
    assert!(json.contains(r#""op":"index_episode""#));
    assert!(json.contains(r#""episode_id":"ep-42""#));
    let decoded: KnowledgeAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, action);
}
#[test]
fn execute_emits_dispatch_host_op() {
    let action = KnowledgeAction::Search {
        query: "nostr".into(),
    };
    let commands = std::sync::Mutex::new(Vec::<ActorCommand>::new());
    KnowledgeActionModule::execute(action, "corr-1", &|cmd| {
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
    assert_eq!(v["op"], "search");
    assert_eq!(v["query"], "nostr");
}

