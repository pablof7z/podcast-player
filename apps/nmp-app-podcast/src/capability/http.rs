//! Podcast-app HTTP capability re-export — `nmp.http.capability`.
//!
//! This module exists to keep `capability::http` parallel to
//! `capability::audio` / `capability::download`. The actual types live in
//! [`podcast_feeds::http`] because `podcast-feeds` is the first low-level
//! consumer (RSS refresh, OPML probe in M2.B+C) and the kernel crate graph
//! is layered so `podcast-feeds` cannot back-dep on `nmp-app-podcast`. The
//! per-app crate re-exports them here so kernel modules that already
//! import from `crate::capability::{audio, download}` can pull HTTP from
//! the same path without learning a new crate name.
//!
//! ## Doctrine
//!
//! See [`podcast_feeds::http`] for the wire format, D6/D7 reasoning, and
//! the response-headers / case-insensitive lookup contract. Nothing new
//! happens at this layer.

pub use podcast_feeds::http::{HttpMethod, HttpRequest, HttpResult, HTTP_CAPABILITY_NAMESPACE};

#[cfg(test)]
mod tests {
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
}
