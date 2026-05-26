use super::*;
fn minimal_tags() -> Vec<Vec<String>> {
    vec![
        vec!["d".into(), "ep-1".into()],
        vec!["title".into(), "Pilot".into()],
        vec!["imeta".into(), "url https://media.example/ep-1.m4a".into()],
    ]
}
#[test]
fn parse_minimal_episode_succeeds() {
    let ep = parse_episode_event(KIND_EPISODE, 999, "", &minimal_tags()).expect("parse");
    assert_eq!(ep.d_tag, "ep-1");
    assert_eq!(ep.title, "Pilot");
    assert_eq!(ep.audio_url, "https://media.example/ep-1.m4a");
    assert_eq!(ep.published_at, 999); // falls back to created_at
    assert!(ep.duration_secs.is_none());
    assert!(ep.audio_sha256_hex.is_none());
    assert!(ep.show_a_tag.is_none());
}
#[test]
fn parse_full_episode_collects_imeta_and_a_tag() {
    let tags = vec![
        vec!["d".into(), "ep-1".into()],
        vec!["title".into(), "Pilot".into()],
        vec!["summary".into(), "First episode".into()],
        vec!["published_at".into(), "1700000123".into()],
        vec!["a".into(), "10154:agent-pk:show-1".into()],
        vec!["duration".into(), "1800".into()],
        vec!["image".into(), "https://img.example/ep-1.jpg".into()],
        vec![
            "imeta".into(),
            "url https://media.example/ep-1.m4a".into(),
            "m audio/mp4".into(),
            "x deadbeef".into(),
            "size 12345".into(),
        ],
        vec![
            "chapters".into(),
            "https://chapters.example/ep-1.json".into(),
            "application/json+chapters".into(),
        ],
        vec![
            "transcript".into(),
            "https://tx.example/ep-1.vtt".into(),
            "text/vtt".into(),
        ],
    ];
    let ep = parse_episode_event(KIND_EPISODE, 0, "ignored content", &tags).expect("parse");
    assert_eq!(ep.published_at, 1_700_000_123);
    assert_eq!(ep.duration_secs, Some(1800.0));
    assert_eq!(ep.audio_mime_type.as_deref(), Some("audio/mp4"));
    assert_eq!(ep.audio_sha256_hex.as_deref(), Some("deadbeef"));
    assert_eq!(ep.audio_size_bytes, Some(12_345));
    assert_eq!(ep.image_url.as_deref(), Some("https://img.example/ep-1.jpg"));
    let show_ref = ep.show_a_tag.expect("a tag present");
    assert_eq!(show_ref.kind, 10154);
    assert_eq!(show_ref.pubkey, "agent-pk");
    assert_eq!(show_ref.d_tag, "show-1");
    assert_eq!(ep.chapters_url.as_deref(), Some("https://chapters.example/ep-1.json"));
    assert_eq!(ep.transcript_url.as_deref(), Some("https://tx.example/ep-1.vtt"));
    assert_eq!(ep.transcript_mime_type.as_deref(), Some("text/vtt"));
    assert_eq!(ep.summary, "First episode");
}
#[test]
fn parse_rejects_wrong_kind() {
    let err = parse_episode_event(KIND_EPISODE + 1, 0, "", &minimal_tags()).unwrap_err();
    assert!(matches!(err, ParseError::WrongKind { .. }));
}
#[test]
fn parse_requires_audio_url() {
    let tags = vec![
        vec!["d".into(), "ep-1".into()],
        vec!["title".into(), "Pilot".into()],
    ];
    let err = parse_episode_event(KIND_EPISODE, 0, "", &tags).unwrap_err();
    assert_eq!(err, ParseError::MissingAudioUrl);
}
#[test]
fn parse_falls_back_to_url_tag_when_imeta_missing() {
    let tags = vec![
        vec!["d".into(), "ep-1".into()],
        vec!["title".into(), "Pilot".into()],
        vec!["url".into(), "https://media.example/legacy.mp3".into()],
    ];
    let ep = parse_episode_event(KIND_EPISODE, 0, "", &tags).expect("parse");
    assert_eq!(ep.audio_url, "https://media.example/legacy.mp3");
}
#[test]
fn parse_rejects_malformed_a_tag() {
    let tags = vec![
        vec!["d".into(), "ep-1".into()],
        vec!["title".into(), "Pilot".into()],
        vec!["a".into(), "no-colons".into()],
        vec!["imeta".into(), "url https://x".into()],
    ];
    let err = parse_episode_event(KIND_EPISODE, 0, "", &tags).unwrap_err();
    assert!(matches!(err, ParseError::MalformedReference(_)));
}

