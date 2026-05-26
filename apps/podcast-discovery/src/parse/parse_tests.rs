use super::*;
fn tags() -> Vec<Vec<String>> {
    vec![
        vec!["d".into(), "show-1".into()],
        vec!["title".into(), "My Show".into()],
        vec!["t".into(), "Tech".into()],
        vec!["t".into(), "News".into()],
        vec!["image".into()], // malformed — value missing
        vec!["empty".into(), String::new()],
    ]
}
#[test]
fn first_tag_value_returns_value_when_present() {
    let t = tags();
    assert_eq!(first_tag_value(&t, "title"), Some("My Show"));
    assert_eq!(first_tag_value(&t, "d"), Some("show-1"));
}
#[test]
fn first_tag_value_returns_none_when_missing_or_empty() {
    let t = tags();
    assert_eq!(first_tag_value(&t, "summary"), None);
    // tag present but value missing
    assert_eq!(first_tag_value(&t, "image"), None);
    // tag present, value is empty string
    assert_eq!(first_tag_value(&t, "empty"), None);
}
#[test]
fn all_tag_values_collects_repeats_in_order() {
    let t = tags();
    assert_eq!(all_tag_values(&t, "t"), vec!["Tech", "News"]);
    assert!(all_tag_values(&t, "missing").is_empty());
}
#[test]
fn first_tag_returns_full_slice_for_imeta_style() {
    let t = vec![vec![
        "imeta".into(),
        "url https://a.example/x.mp3".into(),
        "m audio/mp4".into(),
    ]];
    let imeta = first_tag(&t, "imeta").expect("present");
    assert_eq!(imeta.len(), 3);
    assert_eq!(imeta[1], "url https://a.example/x.mp3");
}

