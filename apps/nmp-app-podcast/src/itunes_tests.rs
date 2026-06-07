use super::*;
#[test]
fn url_encode_passes_through_unreserved() {
    assert_eq!(url_encode("AZaz09-_.~"), "AZaz09-_.~");
}
#[test]
fn url_encode_converts_space_to_plus() {
    assert_eq!(url_encode("a b c"), "a+b+c");
}
#[test]
fn url_encode_percent_encodes_other_chars() {
    assert_eq!(url_encode("!?"), "%21%3F");
}
#[test]
fn parse_itunes_results_returns_empty_on_garbage() {
    assert_eq!(
        parse_itunes_results("not json"),
        Vec::<PodcastSummary>::new()
    );
}
#[test]
fn parse_itunes_results_decodes_minimal_response() {
    let body = r#"{
        "results": [{
            "collectionId": 1234567,
            "collectionName": "Some Show",
            "feedUrl": "https://feed.example.com/r.rss",
            "artworkUrl600": "https://img.example.com/c.jpg",
            "artistName": "Host Name"
        }]
    }"#;
    let out = parse_itunes_results(body);
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].id, "1234567");
    assert_eq!(out[0].title, "Some Show");
    assert_eq!(
        out[0].feed_url.as_deref(),
        Some("https://feed.example.com/r.rss")
    );
    assert_eq!(out[0].author.as_deref(), Some("Host Name"));
}
