//! HTTP capability schema — `nmp.http.capability`.
//!
//! Rust mirror of the wire vocabulary the iOS executor in
//! `ios/Podcast/Podcast/Capabilities/HttpCapability.swift` already implements.
//! `nmp-app-podcast::capability::http` re-exports these so consumers in either
//! crate dispatch by the same types; this module is the canonical home because
//! `podcast-feeds` is the first consumer (RSS / OPML refresh) and lives lower
//! in the crate graph than `nmp-app-podcast`.
//!
//! ## Doctrine
//!
//! * **D6 — errors as data.** [`HttpResult`] is a tagged enum; transport
//!   failure (DNS, TLS, timeout, malformed request) is the `Error` variant,
//!   not a panic. The Rust side never `?`'s on the wire — callers pattern
//!   match.
//! * **D7 — capabilities execute, never decide.** The iOS executor performs
//!   the exact GET/POST [`HttpRequest`] describes and reports the raw
//!   [`HttpResult`]. *Which* URL to call (RSS feed, iTunes search,
//!   transcript fetch) and *what to do* with the body are kernel
//!   decisions.
//! * **D15 — bounded input.** Header pairs that aren't exactly
//!   `[name, value]` are ignored on the iOS side; the Rust types here
//!   should never produce malformed pairs.
//!
//! ## Wire format
//!
//! The Swift counterpart in `HttpCapability.swift` is the source of truth
//! for byte-for-byte JSON. Examples:
//!
//! ```text
//! request:  {"method":"GET","url":"https://…","headers":[["Accept","application/rss+xml"]]}
//! result:   {"status":"ok","status_code":200,"headers":[["ETag","\"abc\""]],"body":"<rss>…</rss>"}
//! error:    {"status":"error","message":"transport: timeout"}
//! ```
//!
//! Notes for anyone touching this file:
//!
//! - The result is tagged on `"status"`, not `"type"`. Don't reflexively copy
//!   the `audio` / `download` capability shape — it's a different tag key.
//! - `HttpMethod` is `UPPERCASE` (`"GET"` / `"POST"`), not `snake_case`.
//! - Headers travel as arrays of two-element string arrays
//!   (`Vec<Vec<String>>`), not a map — RSS feeds sometimes send the same
//!   header twice and we want to preserve order/multiplicity. The iOS side
//!   reads `[[String]]` and writes them with `setValue(_:forHTTPHeaderField:)`.
//! - The response body is a UTF-8 string. The iOS executor lossy-converts the
//!   `Data` to a `String` via `String(data:encoding:.utf8)`. RSS feeds with
//!   non-UTF-8 encodings (Windows-1252, ISO-8859-1) lose the original bytes
//!   here. This is a pre-existing limitation inherited from the shipped
//!   Swift contract and the legacy Swift `RSSParser`; tracked for follow-up
//!   in BACKLOG. Don't widen the contract in this PR.
//!
//! ## Schema stability
//!
//! M5 introduces this Rust schema for the first time — the canonical
//! `nmp-core::capability::http` referenced from Chirp's `HttpCapability.swift`
//! has not landed upstream yet (no `nmp-core/src/substrate/http.rs` exists).
//! When that upstream type does land, this module reconciles against it.

use serde::{Deserialize, Serialize};

/// Capability namespace string. Mirrors `HttpCapability::namespace` in the
/// Swift executor so the iOS-side router (`PodcastCapabilities.handleJSON`)
/// dispatches the same way `KeyringCapability` and `AudioCapability` do.
pub const HTTP_CAPABILITY_NAMESPACE: &str = "nmp.http.capability";

// ---------------------------------------------------------------------------
// HTTP method
// ---------------------------------------------------------------------------

/// HTTP verb. Wire form is `UPPERCASE`: `"GET"` / `"POST"`.
///
/// Intentionally narrow — every M5 caller (RSS refresh, iTunes search) is
/// `GET`-only; `Post` is here for the iTunes search / Blossom upload (M10)
/// callers and matches the Swift `HttpMethod` enum.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "UPPERCASE")]
pub enum HttpMethod {
    Get,
    Post,
}

impl HttpMethod {
    /// Returns the wire string (`"GET"` / `"POST"`) without going through
    /// serde — useful for inspecting a request without re-encoding.
    #[must_use]
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Get => "GET",
            Self::Post => "POST",
        }
    }
}

// ---------------------------------------------------------------------------
// Rust → iOS: HttpRequest
// ---------------------------------------------------------------------------

/// Capability-private request payload — what travels in
/// `CapabilityRequest.payload_json`.
///
/// Headers are array-of-pairs (not a map) because some HTTP clients send the
/// same header twice and we preserve order/multiplicity across the bridge.
/// Empty / absent headers decode as `Vec::new()` on both sides.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct HttpRequest {
    /// HTTP verb. Wire form `UPPERCASE`.
    pub method: HttpMethod,
    /// Absolute URL (`http://` or `https://`). Validated as a URL on the
    /// iOS side; an unparseable string yields `HttpResult::Error{message:
    /// "invalid-url"}`.
    pub url: String,
    /// Header `[name, value]` pairs. The iOS side ignores pairs that
    /// aren't exactly length 2.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub headers: Vec<Vec<String>>,
    /// UTF-8 request body. `None` (the wire-omitted form) for `GET`;
    /// `Some(body)` for `POST`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub body: Option<String>,
}

impl HttpRequest {
    /// Construct a `GET` request with the given headers.
    ///
    /// `headers` is `(name, value)` tuples; converted to the wire pair
    /// form at call sites that find a tuple shape cleaner.
    #[must_use]
    pub fn get<I, K, V>(url: impl Into<String>, headers: I) -> Self
    where
        I: IntoIterator<Item = (K, V)>,
        K: Into<String>,
        V: Into<String>,
    {
        Self {
            method: HttpMethod::Get,
            url: url.into(),
            headers: headers
                .into_iter()
                .map(|(k, v)| vec![k.into(), v.into()])
                .collect(),
            body: None,
        }
    }
}

// ---------------------------------------------------------------------------
// iOS → Rust: HttpResult
// ---------------------------------------------------------------------------

/// Capability-private result payload — what travels in
/// `CapabilityEnvelope.result_json`.
///
/// Tagged on `"status"` so the wire shape matches the existing Swift
/// `HttpResult` enum byte-for-byte:
///
/// ```text
/// {"status":"ok","status_code":200,"headers":[["ETag","\"abc\""]],"body":"…"}
/// {"status":"error","message":"…"}
/// ```
///
/// **Headers on `Ok`:** populated from `HTTPURLResponse.allHeaderFields` on
/// the iOS side so the Rust caller (FeedClient, etc.) can read `ETag` /
/// `Last-Modified` without a second round-trip. Empty when the response had
/// no headers (e.g. `file://` short-circuit on iOS).
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum HttpResult {
    /// Transport succeeded. `status_code` is the raw HTTP status — a 200 and
    /// a 404 are both `Ok` here; interpretation is the caller's policy (D7).
    Ok {
        status_code: u16,
        /// Response headers as `[name, value]` pairs. The iOS side writes
        /// `name`s as the canonical-case strings from
        /// `HTTPURLResponse.allHeaderFields`; callers that look up specific
        /// headers should match case-insensitively (see
        /// [`Self::header`]).
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        headers: Vec<Vec<String>>,
        /// UTF-8 body. Non-UTF-8 bytes are lossy-converted by the iOS
        /// executor — see the file-level doc on this pre-existing
        /// limitation.
        body: String,
    },
    /// Transport-level failure (DNS, TLS, timeout, malformed request,
    /// capability stopped, etc.). The message is a human-readable
    /// diagnostic, not a stable enum.
    Error { message: String },
}

impl HttpResult {
    /// Case-insensitive header lookup. Returns the first matching value or
    /// `None`. Header names from the wire are whatever case the upstream
    /// server returned (preserved by `HTTPURLResponse.allHeaderFields`),
    /// so callers must not assume `"ETag"` vs `"etag"`.
    #[must_use]
    pub fn header(&self, name: &str) -> Option<&str> {
        let headers = match self {
            Self::Ok { headers, .. } => headers,
            Self::Error { .. } => return None,
        };
        for pair in headers {
            if pair.len() == 2 && pair[0].eq_ignore_ascii_case(name) {
                return Some(pair[1].as_str());
            }
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // ---- HttpMethod ------------------------------------------------------

    #[test]
    fn http_method_uppercase_serde_get() {
        let json = serde_json::to_string(&HttpMethod::Get).expect("encode");
        assert_eq!(json, r#""GET""#);
        let back: HttpMethod = serde_json::from_str(&json).expect("decode");
        assert_eq!(back, HttpMethod::Get);
    }

    #[test]
    fn http_method_uppercase_serde_post() {
        let json = serde_json::to_string(&HttpMethod::Post).expect("encode");
        assert_eq!(json, r#""POST""#);
        let back: HttpMethod = serde_json::from_str(&json).expect("decode");
        assert_eq!(back, HttpMethod::Post);
    }

    #[test]
    fn http_method_as_str_matches_wire() {
        assert_eq!(HttpMethod::Get.as_str(), "GET");
        assert_eq!(HttpMethod::Post.as_str(), "POST");
    }

    // ---- HttpRequest -----------------------------------------------------

    #[test]
    fn http_request_get_no_headers_omits_fields() {
        let req = HttpRequest::get("https://example.com/feed.xml", std::iter::empty::<(&str, &str)>());
        let json = serde_json::to_string(&req).expect("encode");
        // `skip_serializing_if` keeps headers + body off the wire when absent.
        assert_eq!(json, r#"{"method":"GET","url":"https://example.com/feed.xml"}"#);
        let back: HttpRequest = serde_json::from_str(&json).expect("decode");
        assert_eq!(back, req);
    }

    #[test]
    fn http_request_get_serializes_headers_as_pair_arrays() {
        let req = HttpRequest::get(
            "https://example.com/feed.xml",
            [("Accept", "application/rss+xml"), ("If-None-Match", "\"abc123\"")],
        );
        let json = serde_json::to_string(&req).expect("encode");
        // Match the literal Swift encoder produces from the same shape.
        assert_eq!(
            json,
            r#"{"method":"GET","url":"https://example.com/feed.xml","headers":[["Accept","application/rss+xml"],["If-None-Match","\"abc123\""]]}"#
        );
        let back: HttpRequest = serde_json::from_str(&json).expect("decode");
        assert_eq!(back, req);
    }

    #[test]
    fn http_request_post_round_trips_body() {
        let req = HttpRequest {
            method: HttpMethod::Post,
            url: "https://example.com/api".into(),
            headers: vec![vec!["Content-Type".into(), "application/json".into()]],
            body: Some(r#"{"x":1}"#.into()),
        };
        let json = serde_json::to_string(&req).expect("encode");
        let back: HttpRequest = serde_json::from_str(&json).expect("decode");
        assert_eq!(back, req);
    }

    #[test]
    fn http_request_absent_headers_decode_to_empty() {
        // Wire from Swift when no headers were supplied: field omitted.
        let json = r#"{"method":"GET","url":"https://example.com/feed.xml"}"#;
        let req: HttpRequest = serde_json::from_str(json).expect("decode");
        assert!(req.headers.is_empty());
        assert!(req.body.is_none());
    }

    // ---- HttpResult ------------------------------------------------------

    #[test]
    fn http_result_ok_matches_swift_wire_shape() {
        let result = HttpResult::Ok {
            status_code: 200,
            headers: vec![
                vec!["ETag".into(), "\"abc123\"".into()],
                vec!["Last-Modified".into(), "Wed, 31 Dec 2025 23:00:00 GMT".into()],
            ],
            body: "<rss/>".into(),
        };
        let json = serde_json::to_string(&result).expect("encode");
        assert_eq!(
            json,
            r#"{"status":"ok","status_code":200,"headers":[["ETag","\"abc123\""],["Last-Modified","Wed, 31 Dec 2025 23:00:00 GMT"]],"body":"<rss/>"}"#
        );
        let back: HttpResult = serde_json::from_str(&json).expect("decode");
        assert_eq!(back, result);
    }

    #[test]
    fn http_result_ok_omits_empty_headers() {
        let result = HttpResult::Ok {
            status_code: 304,
            headers: vec![],
            body: String::new(),
        };
        let json = serde_json::to_string(&result).expect("encode");
        // Matches the legacy Swift `.ok(statusCode:body:)` wire — additive
        // headers field stays off the wire when absent.
        assert_eq!(json, r#"{"status":"ok","status_code":304,"body":""}"#);
    }

    #[test]
    fn http_result_error_matches_swift_wire_shape() {
        let result = HttpResult::Error {
            message: "transport: timeout".into(),
        };
        let json = serde_json::to_string(&result).expect("encode");
        assert_eq!(json, r#"{"status":"error","message":"transport: timeout"}"#);
        let back: HttpResult = serde_json::from_str(&json).expect("decode");
        assert_eq!(back, result);
    }

    #[test]
    fn http_result_decodes_legacy_ok_without_headers_field() {
        // The shipped Swift `HttpResult.ok` (pre-M5) encodes only status_code
        // + body. The Rust decoder must keep accepting that shape so an
        // older iOS build (or a 304 with no headers) doesn't trip a deserialize
        // error.
        let json = r#"{"status":"ok","status_code":200,"body":"<rss/>"}"#;
        let result: HttpResult = serde_json::from_str(json).expect("decode");
        match result {
            HttpResult::Ok {
                status_code,
                headers,
                body,
            } => {
                assert_eq!(status_code, 200);
                assert!(headers.is_empty());
                assert_eq!(body, "<rss/>");
            }
            HttpResult::Error { .. } => panic!("expected Ok"),
        }
    }

    #[test]
    fn http_result_header_lookup_is_case_insensitive() {
        let result = HttpResult::Ok {
            status_code: 200,
            headers: vec![
                vec!["ETag".into(), "\"abc\"".into()],
                vec!["Last-Modified".into(), "Wed, 31 Dec 2025 23:00:00 GMT".into()],
            ],
            body: String::new(),
        };
        assert_eq!(result.header("etag"), Some("\"abc\""));
        assert_eq!(result.header("ETAG"), Some("\"abc\""));
        assert_eq!(result.header("Last-Modified"), Some("Wed, 31 Dec 2025 23:00:00 GMT"));
        assert_eq!(result.header("missing"), None);
    }

    #[test]
    fn http_result_header_lookup_on_error_returns_none() {
        let result = HttpResult::Error {
            message: "boom".into(),
        };
        assert_eq!(result.header("ETag"), None);
    }

    #[test]
    fn namespace_matches_canonical_capability_plan() {
        assert_eq!(HTTP_CAPABILITY_NAMESPACE, "nmp.http.capability");
    }
}
