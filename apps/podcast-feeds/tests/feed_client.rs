//! Integration tests for `podcast_feeds::client` — the FeedClient
//! request/response bridge introduced in M5.
//!
//! These tests intentionally consume only the public API
//! (`build_feed_request`, `handle_feed_response`, `FeedResult`,
//! `FeedError`) so a future refactor that re-shapes the private
//! constants or helpers can't accidentally break a contract-level
//! assertion. Keeping them out-of-source also lets `client.rs`
//! stay under the 500-LOC hard limit from `AGENTS.md`.

use chrono::{DateTime, Utc};
use podcast_core::PodcastId;
use podcast_feeds::http::{HttpMethod, HttpResult};
use podcast_feeds::refresh::EtagCache;
use podcast_feeds::{build_feed_request, handle_feed_response, FeedError, FeedResult};
use url::Url;

// The constants below are duplicated from `client.rs` so this file can
// observe the wire shape without leaning on crate-internal symbols. If
// they ever drift, this test surfaces the drift first.
const ACCEPT_HEADER: &str = "application/rss+xml, application/xml;q=0.9, */*;q=0.8";
const USER_AGENT: &str = "Podcastr/1.0";

fn t(s: &str) -> DateTime<Utc> {
    DateTime::parse_from_rfc3339(s).unwrap().with_timezone(&Utc)
}

fn feed_url() -> Url {
    Url::parse("https://example.com/feed.xml").unwrap()
}

fn minimal_rss() -> String {
    // Bare-minimum well-formed RSS with one episode. Exercises the parser
    // path end-to-end; richer fixtures live alongside the parser tests in
    // `tests/rss_parser.rs`.
    r#"<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Test Feed</title>
    <link>https://example.com</link>
    <description>A test feed.</description>
    <item>
      <title>Episode 1</title>
      <enclosure url="https://example.com/ep1.mp3" length="12345" type="audio/mpeg"/>
      <guid>ep1</guid>
      <pubDate>Wed, 31 Dec 2025 23:00:00 GMT</pubDate>
    </item>
  </channel>
</rss>
"#
    .to_string()
}

// ---- build_feed_request ---------------------------------------------------

#[test]
fn build_feed_request_without_cache_sends_only_baseline_headers() {
    let req = build_feed_request(&feed_url(), None);
    assert_eq!(req.method, HttpMethod::Get);
    assert_eq!(req.url, "https://example.com/feed.xml");
    assert!(req.body.is_none());
    // Accept + User-Agent only, in legacy order.
    assert_eq!(req.headers.len(), 2);
    assert_eq!(req.headers[0][0], "Accept");
    assert_eq!(req.headers[0][1], ACCEPT_HEADER);
    assert_eq!(req.headers[1][0], "User-Agent");
    assert_eq!(req.headers[1][1], USER_AGENT);
}

#[test]
fn build_feed_request_with_full_cache_adds_conditional_headers() {
    let cache = EtagCache::with_headers(
        t("2026-01-01T12:00:00Z"),
        Some("\"abc123\"".into()),
        Some("Wed, 31 Dec 2025 23:00:00 GMT".into()),
    );
    let req = build_feed_request(&feed_url(), Some(&cache));
    let names: Vec<_> = req.headers.iter().map(|h| h[0].as_str()).collect();
    assert_eq!(
        names,
        vec!["Accept", "User-Agent", "If-None-Match", "If-Modified-Since"]
    );
    let lookup = |name: &str| -> Option<&str> {
        req.headers
            .iter()
            .find(|h| h[0].eq_ignore_ascii_case(name))
            .map(|h| h[1].as_str())
    };
    assert_eq!(lookup("If-None-Match"), Some("\"abc123\""));
    assert_eq!(
        lookup("If-Modified-Since"),
        Some("Wed, 31 Dec 2025 23:00:00 GMT")
    );
}

#[test]
fn build_feed_request_with_etag_only_omits_if_modified_since() {
    let cache = EtagCache::with_headers(t("2026-01-01T12:00:00Z"), Some("\"abc123\"".into()), None);
    let req = build_feed_request(&feed_url(), Some(&cache));
    assert_eq!(req.headers.len(), 3);
    let names: Vec<_> = req.headers.iter().map(|h| h[0].as_str()).collect();
    assert!(names.contains(&"If-None-Match"));
    assert!(!names.contains(&"If-Modified-Since"));
}

#[test]
fn build_feed_request_skips_empty_string_etag() {
    // Defensive: legacy persistence sometimes stored "" instead of nil.
    let cache = EtagCache::with_headers(
        t("2026-01-01T12:00:00Z"),
        Some(String::new()),
        Some("Wed, 31 Dec 2025 23:00:00 GMT".into()),
    );
    let req = build_feed_request(&feed_url(), Some(&cache));
    let names: Vec<_> = req.headers.iter().map(|h| h[0].as_str()).collect();
    assert!(!names.contains(&"If-None-Match"));
    assert!(names.contains(&"If-Modified-Since"));
}

// ---- handle_feed_response -------------------------------------------------

#[test]
fn handle_response_304_returns_not_modified_with_carried_cache() {
    let prior = EtagCache::with_headers(
        t("2026-01-01T11:00:00Z"),
        Some("\"abc\"".into()),
        Some("Wed, 31 Dec 2025 23:00:00 GMT".into()),
    );
    let response = HttpResult::Ok {
        status_code: 304,
        headers: vec![],
        body: String::new(),
        body_base64: None,
    };
    let now = t("2026-01-01T12:00:00Z");
    let result = handle_feed_response(
        &feed_url(),
        PodcastId::generate(),
        &response,
        Some(&prior),
        now,
    )
    .expect("304 should not be an error");
    match result {
        FeedResult::NotModified { cache } => {
            assert_eq!(cache.last_refreshed, now);
            // ETag + Last-Modified carry forward from the prior cache.
            assert_eq!(cache.etag, Some("\"abc\"".into()));
            assert_eq!(
                cache.last_modified,
                Some("Wed, 31 Dec 2025 23:00:00 GMT".into())
            );
        }
        other => panic!("expected NotModified, got {other:?}"),
    }
}

#[test]
fn handle_response_304_without_prior_cache_yields_empty_cache() {
    // The 304 path needs to be safe when the persistence layer somehow lost
    // the prior cache headers (e.g. first refresh after migration); we just
    // record `last_refreshed = now`.
    let response = HttpResult::Ok {
        status_code: 304,
        headers: vec![],
        body: String::new(),
        body_base64: None,
    };
    let now = t("2026-01-01T12:00:00Z");
    let result = handle_feed_response(&feed_url(), PodcastId::generate(), &response, None, now)
        .expect("304 should not error");
    match result {
        FeedResult::NotModified { cache } => {
            assert_eq!(cache.last_refreshed, now);
            assert!(cache.etag.is_none());
            assert!(cache.last_modified.is_none());
        }
        other => panic!("expected NotModified, got {other:?}"),
    }
}

#[test]
fn handle_response_200_parses_and_captures_new_headers() {
    let response = HttpResult::Ok {
        status_code: 200,
        headers: vec![
            vec!["ETag".into(), "\"new-abc\"".into()],
            vec![
                "Last-Modified".into(),
                "Thu, 01 Jan 2026 12:00:00 GMT".into(),
            ],
            vec!["Content-Type".into(), "application/rss+xml".into()],
        ],
        body: minimal_rss(),
        body_base64: None,
    };
    let now = t("2026-01-01T12:00:00Z");
    let podcast_id = PodcastId::generate();
    let result = handle_feed_response(&feed_url(), podcast_id, &response, None, now)
        .expect("valid RSS should parse");
    match result {
        FeedResult::Parsed {
            feed_url: returned_url,
            parsed,
            cache,
        } => {
            assert_eq!(returned_url, feed_url());
            assert_eq!(parsed.episodes.len(), 1);
            assert_eq!(parsed.podcast.id, podcast_id);
            assert_eq!(parsed.podcast.title, "Test Feed");
            assert_eq!(cache.last_refreshed, now);
            assert_eq!(cache.etag, Some("\"new-abc\"".into()));
            assert_eq!(
                cache.last_modified,
                Some("Thu, 01 Jan 2026 12:00:00 GMT".into())
            );
        }
        other => panic!("expected Parsed, got {other:?}"),
    }
}

#[test]
fn handle_response_200_prefers_raw_body_bytes_for_declared_encoding() {
    let body = b"<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>
<rss version=\"2.0\">
  <channel>
    <title>Caf\xe9 Podcasts</title>
    <description>Latin-1 feed.</description>
    <item>
      <title>Ni\xf1o Episode</title>
      <enclosure url=\"https://example.com/ep1.mp3\" type=\"audio/mpeg\"/>
      <guid>latin-1</guid>
    </item>
  </channel>
</rss>";
    let response = HttpResult::ok_with_body_bytes(
        200,
        vec![vec!["Content-Type".into(), "application/rss+xml".into()]],
        body,
    );
    let now = t("2026-01-01T12:00:00Z");
    let result = handle_feed_response(&feed_url(), PodcastId::generate(), &response, None, now)
        .expect("latin-1 RSS should parse through raw body bytes");

    let FeedResult::Parsed { parsed, .. } = result else {
        panic!("expected Parsed");
    };
    assert_eq!(parsed.podcast.title, "Café Podcasts");
    assert_eq!(parsed.episodes[0].title, "Niño Episode");
}

#[test]
fn handle_response_200_missing_response_headers_carries_prior_cache_forward() {
    // If a server stops sending ETag (some CDNs strip them on cache hits) we
    // must keep our previously-known ETag instead of clearing it — otherwise
    // the next refresh round-trips a full body every time.
    let prior = EtagCache::with_headers(
        t("2026-01-01T11:00:00Z"),
        Some("\"prior-abc\"".into()),
        Some("Wed, 31 Dec 2025 23:00:00 GMT".into()),
    );
    let response = HttpResult::Ok {
        status_code: 200,
        headers: vec![],
        body: minimal_rss(),
        body_base64: None,
    };
    let now = t("2026-01-01T12:00:00Z");
    let result = handle_feed_response(
        &feed_url(),
        PodcastId::generate(),
        &response,
        Some(&prior),
        now,
    )
    .expect("valid RSS should parse");
    match result {
        FeedResult::Parsed { cache, .. } => {
            assert_eq!(cache.etag, Some("\"prior-abc\"".into()));
            assert_eq!(
                cache.last_modified,
                Some("Wed, 31 Dec 2025 23:00:00 GMT".into())
            );
        }
        other => panic!("expected Parsed, got {other:?}"),
    }
}

#[test]
fn handle_response_etag_lookup_is_case_insensitive_on_response_headers() {
    // Some upstreams send `etag` (lower-case); the legacy Swift checked both.
    // Our `HttpResult::header` is case-insensitive so this should Just Work.
    let response = HttpResult::Ok {
        status_code: 200,
        headers: vec![vec!["etag".into(), "\"lower-abc\"".into()]],
        body: minimal_rss(),
        body_base64: None,
    };
    let now = t("2026-01-01T12:00:00Z");
    let result = handle_feed_response(&feed_url(), PodcastId::generate(), &response, None, now)
        .expect("valid RSS should parse");
    match result {
        FeedResult::Parsed { cache, .. } => {
            assert_eq!(cache.etag, Some("\"lower-abc\"".into()));
        }
        other => panic!("expected Parsed, got {other:?}"),
    }
}

#[test]
fn handle_response_5xx_status_returns_http_error() {
    let response = HttpResult::Ok {
        status_code: 503,
        headers: vec![],
        body: String::new(),
        body_base64: None,
    };
    let now = t("2026-01-01T12:00:00Z");
    let err = handle_feed_response(&feed_url(), PodcastId::generate(), &response, None, now)
        .expect_err("5xx must surface as FeedError::Http");
    assert_eq!(err, FeedError::Http { status_code: 503 });
}

#[test]
fn handle_response_transport_error_returns_transport_failure() {
    let response = HttpResult::Error {
        message: "transport: timeout".into(),
    };
    let now = t("2026-01-01T12:00:00Z");
    let err = handle_feed_response(&feed_url(), PodcastId::generate(), &response, None, now)
        .expect_err("transport error must surface as FeedError::Transport");
    match err {
        FeedError::Transport(msg) => assert_eq!(msg, "transport: timeout"),
        other => panic!("expected Transport, got {other:?}"),
    }
}

#[test]
fn handle_response_malformed_body_returns_parse_error() {
    let response = HttpResult::Ok {
        status_code: 200,
        headers: vec![],
        body: "not actually xml".into(),
        body_base64: None,
    };
    let now = t("2026-01-01T12:00:00Z");
    let err = handle_feed_response(&feed_url(), PodcastId::generate(), &response, None, now)
        .expect_err("malformed body must surface as FeedError::Parse");
    assert!(matches!(err, FeedError::Parse(_)));
}
