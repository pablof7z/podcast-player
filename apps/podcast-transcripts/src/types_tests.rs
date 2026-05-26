use super::*;

#[test]
fn transcript_entry_round_trip() {
    let entry = TranscriptEntry {
        start_secs: 1.5,
        end_secs: 4.25,
        speaker: Some("Host".to_string()),
        text: "Hello world".to_string(),
        words: None,
    };
    let json = serde_json::to_string(&entry).unwrap();
    let back: TranscriptEntry = serde_json::from_str(&json).unwrap();
    assert_eq!(entry, back);
}

#[test]
fn transcript_ready_helper() {
    let transcript = Transcript::ready(
        "ep-1",
        vec![],
        "https://example.com/t.vtt",
        TranscriptKind::Vtt,
        TranscriptSource::Publisher,
    );
    assert!(matches!(
        transcript.status,
        TranscriptState::Ready {
            source: TranscriptSource::Publisher
        }
    ));
    assert_eq!(transcript.language, "en-US");
}

#[test]
fn transcript_chunk_round_trip() {
    let chunk = TranscriptChunk {
        episode_id: "ep-1".into(),
        chunk_index: 3,
        start_secs: 12.0,
        end_secs: 60.0,
        text: "some text".into(),
        word_count: 2,
    };
    let json = serde_json::to_string(&chunk).unwrap();
    let back: TranscriptChunk = serde_json::from_str(&json).unwrap();
    assert_eq!(chunk, back);
}
