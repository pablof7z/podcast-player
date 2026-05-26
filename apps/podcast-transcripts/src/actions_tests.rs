use super::*;

#[test]
fn ingest_action_round_trip() {
    let action = IngestTranscript {
        episode_id: "ep-1".into(),
        publisher_url: Some("https://example.com/t.vtt".into()),
        publisher_kind: Some(TranscriptKind::Vtt),
    };
    let json = serde_json::to_string(&action).unwrap();
    let back: IngestTranscript = serde_json::from_str(&json).unwrap();
    assert_eq!(action, back);
}

#[test]
fn retry_action_round_trip() {
    let action = RetryTranscript {
        episode_id: "ep-1".into(),
    };
    let json = serde_json::to_string(&action).unwrap();
    let back: RetryTranscript = serde_json::from_str(&json).unwrap();
    assert_eq!(action, back);
}

#[test]
fn override_action_round_trip() {
    let action = OverrideProvider {
        episode_id: "ep-1".into(),
        provider: SttProvider::AssemblyAi,
    };
    let json = serde_json::to_string(&action).unwrap();
    let back: OverrideProvider = serde_json::from_str(&json).unwrap();
    assert_eq!(action, back);
}
