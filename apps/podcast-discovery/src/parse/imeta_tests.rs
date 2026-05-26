use super::*;
#[test]
fn empty_imeta_returns_default() {
    let fields = parse_imeta_fields(&["imeta".into()]);
    assert_eq!(fields, ImetaFields::default());
}
#[test]
fn parses_publisher_emitted_block() {
    let imeta = vec![
        "imeta".into(),
        "url https://media.example/ep.m4a".into(),
        "m audio/mp4".into(),
        "x deadbeef".into(),
        "size 1234".into(),
    ];
    let fields = parse_imeta_fields(&imeta);
    assert_eq!(fields.url.as_deref(), Some("https://media.example/ep.m4a"));
    assert_eq!(fields.mime.as_deref(), Some("audio/mp4"));
    assert_eq!(fields.sha256.as_deref(), Some("deadbeef"));
    assert_eq!(fields.size, Some(1234));
}
#[test]
fn ignores_unknown_keys_and_malformed_entries() {
    let imeta = vec![
        "imeta".into(),
        "url https://x".into(),
        "no-space-entry".into(), // dropped — no ' ' delimiter
        "blurhash abcdef".into(), // unknown key — ignored
    ];
    let fields = parse_imeta_fields(&imeta);
    assert_eq!(fields.url.as_deref(), Some("https://x"));
    assert!(fields.mime.is_none());
}
#[test]
fn size_parse_failure_yields_none() {
    let imeta = vec!["imeta".into(), "size not-a-number".into()];
    let fields = parse_imeta_fields(&imeta);
    assert!(fields.size.is_none());
}

