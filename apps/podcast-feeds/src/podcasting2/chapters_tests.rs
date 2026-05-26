use super::*;

#[test]
fn parses_basic_chapters() {
    let json = r#"{
        "version": "1.2.0",
        "chapters": [
            {"startTime": 0, "title": "Intro"},
            {"startTime": 60.5, "title": "Topic A", "img": "https://example.com/a.jpg"},
            {"startTime": 120, "endTime": 240, "title": "Topic B", "url": "https://example.com/notes"}
        ]
    }"#;
    let chapters = parse_chapters_json(json).unwrap();
    assert_eq!(chapters.len(), 3);
    assert_eq!(chapters[0].title, "Intro");
    assert_eq!(chapters[0].start_secs, 0.0);
    assert_eq!(chapters[1].start_secs, 60.5);
    assert_eq!(chapters[2].end_secs, Some(240.0));
    assert!(chapters[1].image_url.is_some());
    assert!(chapters[2].link_url.is_some());
}

#[test]
fn skips_empty_title_entries() {
    let json = r#"{"chapters":[
        {"startTime": 0, "title": "Intro"},
        {"startTime": 30, "title": ""},
        {"startTime": 60, "title": "   "},
        {"startTime": 90, "title": "Outro"}
    ]}"#;
    let chapters = parse_chapters_json(json).unwrap();
    assert_eq!(chapters.len(), 2);
    assert_eq!(chapters[0].title, "Intro");
    assert_eq!(chapters[1].title, "Outro");
}

#[test]
fn sorts_ascending_by_start() {
    let json = r#"{"chapters":[
        {"startTime": 120, "title": "Late"},
        {"startTime": 0, "title": "First"},
        {"startTime": 60, "title": "Middle"}
    ]}"#;
    let chapters = parse_chapters_json(json).unwrap();
    assert_eq!(chapters[0].title, "First");
    assert_eq!(chapters[1].title, "Middle");
    assert_eq!(chapters[2].title, "Late");
}

#[test]
fn toc_defaults_to_true() {
    let json = r#"{"chapters":[
        {"startTime": 0, "title": "A"},
        {"startTime": 10, "title": "B", "toc": false}
    ]}"#;
    let chapters = parse_chapters_json(json).unwrap();
    assert!(chapters[0].include_in_toc);
    assert!(!chapters[1].include_in_toc);
}

#[test]
fn missing_start_time_defaults_to_zero() {
    let json = r#"{"chapters":[{"title": "Anchor"}]}"#;
    let chapters = parse_chapters_json(json).unwrap();
    assert_eq!(chapters[0].start_secs, 0.0);
}

#[test]
fn malformed_json_errors() {
    let result = parse_chapters_json("not json");
    assert!(matches!(result, Err(ChaptersError::Decode(_))));
}
