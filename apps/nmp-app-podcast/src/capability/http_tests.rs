use super::*;
#[test]
fn re_export_preserves_namespace_string() {
    assert_eq!(HTTP_CAPABILITY_NAMESPACE, "nmp.http.capability");
}
#[test]
fn re_export_round_trips_request() {
    // Smoke-test that the re-exported types are usable (not just visible).
    let req = HttpRequest::get(
        "https://example.com/feed.xml",
        [("Accept", "application/rss+xml")],
    );
    let json = serde_json::to_string(&req).expect("encode");
    let back: HttpRequest = serde_json::from_str(&json).expect("decode");
    assert_eq!(back, req);
    assert_eq!(back.method, HttpMethod::Get);
}
#[test]
fn re_export_round_trips_result_ok_with_headers() {
    let result = HttpResult::Ok {
        status_code: 200,
        headers: vec![vec!["ETag".into(), "\"abc\"".into()]],
        body: "<rss/>".into(),
    };
    let json = serde_json::to_string(&result).expect("encode");
    let back: HttpResult = serde_json::from_str(&json).expect("decode");
    assert_eq!(back, result);
    assert_eq!(back.header("etag"), Some("\"abc\""));
}

