use super::*;
#[test]
fn transcript_kind_round_trip() {
    let value = TranscriptKind::Vtt;
    let json = serde_json::to_string(&value).unwrap();
    let back: TranscriptKind = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}
#[test]
fn transcript_kind_from_mime_with_charset() {
    assert_eq!(
        TranscriptKind::from_mime("text/vtt; charset=utf-8"),
        Some(TranscriptKind::Vtt)
    );
    assert_eq!(
        TranscriptKind::from_mime("application/json; foo=bar"),
        Some(TranscriptKind::Json)
    );
    assert_eq!(TranscriptKind::from_mime("audio/mpeg"), None);
}
#[test]
fn transcript_state_round_trip() {
    let value = TranscriptState::Ready {
        source: TranscriptSource::Scribe,
    };
    let json = serde_json::to_string(&value).unwrap();
    let back: TranscriptState = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}
#[test]
fn transcript_state_transcribing_round_trip() {
    let value = TranscriptState::Transcribing { progress: 0.42 };
    let json = serde_json::to_string(&value).unwrap();
    let back: TranscriptState = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}

