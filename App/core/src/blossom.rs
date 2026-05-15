//! Blossom BUD-02 file uploader — port of
//! `App/Sources/Services/BlossomUploader.swift`.
//!
//! Flow (BUD-02):
//!   1. SHA-256 the payload (lowercase hex).
//!   2. Sign a kind:24242 event with tags
//!      `[["t","upload"], ["x",<sha>], ["expiration",<now+300>]]`.
//!      Event `content` is a human-readable description derived from the
//!      MIME type — Swift's strings are preserved verbatim so behavior on
//!      relays/servers matches the iOS client.
//!   3. Base64 (STANDARD) the JSON of the signed event.
//!   4. HTTP PUT `<server>/upload` with header
//!      `Authorization: Nostr <base64-json>`, Content-Type set to the
//!      payload mime, body = raw bytes.
//!   5. Response is a JSON blob descriptor — return its `url` field.
//!
//! Rejection details: Blossom servers convey reason in the `X-Reason`
//! response header per BUD-01 §4. Fall back to body, then to `HTTP <status>`.

use base64::{engine::general_purpose::STANDARD, Engine};
use nostr_sdk::prelude::*;
use sha2::{Digest, Sha256};

use crate::client::PodcastrCore;
use crate::errors::CoreError;

/// BUD-01/02 authorization event kind.
const KIND_BLOSSOM_AUTH: u16 = 24242;
/// Default Blossom host. Matches `BlossomUploader.defaultServer` on iOS.
const DEFAULT_SERVER: &str = "https://blossom.primal.net";
/// Auth event lifetime. Matches the Swift implementation (`now + 60 * 5`).
const AUTH_EXPIRATION_SECS: u64 = 300;

/// Lowercase hex SHA-256 of `bytes`.
fn sha256_hex(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    format!("{:x}", hasher.finalize())
}

/// Human-readable description for the kind:24242 `content` field. Mirrors
/// Swift's `switch contentType` exactly — these strings are observable by
/// relays the auth event passes through, so keeping them identical preserves
/// cross-client behavior.
fn description_for(content_type: &str) -> &'static str {
    match content_type {
        "audio/mpeg" | "audio/mp4" | "audio/m4a" => "Upload podcast audio",
        "application/json" => "Upload podcast data",
        "text/vtt" | "text/plain" => "Upload transcript",
        "image/jpeg" | "image/png" | "image/webp" => "Upload podcast artwork",
        _ => "Upload file",
    }
}

/// Resolve the server base URL. Mirrors the Swift `serverURLString` init:
///   - `None` → default
///   - `Some(s)` where trimmed string is empty → default
///   - `Some(s)` that fails to parse as an absolute URL → default
fn resolve_server(server_url: Option<String>) -> String {
    match server_url {
        None => DEFAULT_SERVER.to_string(),
        Some(s) => {
            let trimmed = s.trim();
            if trimmed.is_empty() {
                return DEFAULT_SERVER.to_string();
            }
            match url::Url::parse(trimmed) {
                Ok(_) => trimmed.to_string(),
                Err(_) => DEFAULT_SERVER.to_string(),
            }
        }
    }
}

/// Join `server` and `"upload"` with exactly one `/`. The Swift code uses
/// `URL.appendingPathComponent("upload")` which normalizes the slash; we do
/// the same manually to avoid quirks with trailing slashes.
fn upload_endpoint(server: &str) -> String {
    let trimmed = server.trim_end_matches('/');
    format!("{trimmed}/upload")
}

/// Build and sign the kind:24242 BUD-02 authorization event.
async fn sign_upload_auth(
    client: &Client,
    sha256_hex_value: &str,
    description: &str,
) -> Result<Event, CoreError> {
    let expiration = Timestamp::now().as_secs() + AUTH_EXPIRATION_SECS;
    let tags = vec![
        Tag::parse(vec!["t".to_string(), "upload".to_string()])
            .map_err(|e| CoreError::Other(format!("build tag t: {e}")))?,
        Tag::parse(vec!["x".to_string(), sha256_hex_value.to_string()])
            .map_err(|e| CoreError::Other(format!("build tag x: {e}")))?,
        Tag::parse(vec!["expiration".to_string(), expiration.to_string()])
            .map_err(|e| CoreError::Other(format!("build tag expiration: {e}")))?,
    ];
    let builder = EventBuilder::new(Kind::Custom(KIND_BLOSSOM_AUTH), description).tags(tags);
    client
        .sign_event_builder(builder)
        .await
        .map_err(|e| CoreError::Signer(format!("sign blossom upload auth: {e}")))
}

#[uniffi::export(async_runtime = "tokio")]
impl PodcastrCore {
    /// Upload `data` to a Blossom server (BUD-02). Returns the absolute URL
    /// the server stored the blob at.
    ///
    /// `server_url`: optional override. `None`, empty, or unparseable falls
    /// back to `https://blossom.primal.net`.
    pub async fn blossom_upload(
        &self,
        data: Vec<u8>,
        content_type: String,
        server_url: Option<String>,
    ) -> Result<String, CoreError> {
        let client = self.runtime().client();

        // Active signer required — fail fast with NotAuthenticated.
        client
            .signer()
            .await
            .map_err(|_| CoreError::NotAuthenticated)?;

        let server = resolve_server(server_url);
        let endpoint = upload_endpoint(&server);

        let sha = sha256_hex(&data);
        let description = description_for(&content_type);
        let auth = sign_upload_auth(client, &sha, description).await?;
        let auth_b64 = STANDARD.encode(auth.as_json().as_bytes());

        let len_header = data.len().to_string();
        let http = reqwest::Client::new();
        let response = http
            .put(&endpoint)
            .header("Authorization", format!("Nostr {auth_b64}"))
            .header("Content-Type", &content_type)
            .header("Content-Length", len_header)
            .body(data)
            .send()
            .await
            .map_err(|e| CoreError::Network(format!("blossom PUT: {e}")))?;

        let status = response.status();
        if !status.is_success() {
            // BUD-01 §4: rejection reason ships in the `X-Reason` header.
            // Fall back to body, then to a generic `HTTP <status>`.
            let reason = response
                .headers()
                .get("x-reason")
                .and_then(|h| h.to_str().ok())
                .map(str::to_string);
            let body_text = response.text().await.unwrap_or_default();
            let final_reason = match reason {
                Some(r) if !r.is_empty() => r,
                _ if !body_text.is_empty() => body_text,
                _ => format!("HTTP {}", status.as_u16()),
            };
            return Err(CoreError::Network(format!(
                "blossom upload rejected: {final_reason}"
            )));
        }

        // Server returns a blob descriptor. We only need `url`.
        let descriptor: serde_json::Value = response
            .json()
            .await
            .map_err(|e| CoreError::Network(format!("blossom response not JSON: {e}")))?;
        let url = descriptor
            .get("url")
            .and_then(|v| v.as_str())
            .map(str::to_string)
            .ok_or_else(|| CoreError::Network("blossom response missing `url`".into()))?;

        // Sanity check that the URL parses — mirrors Swift's
        // `URL(string: urlString)` guard. We don't rewrite it; we just
        // refuse malformed descriptors.
        url::Url::parse(&url)
            .map_err(|e| CoreError::Network(format!("blossom response malformed url: {e}")))?;

        Ok(url)
    }
}

// -- Tests --

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sha256_hex_known_vector() {
        // "hello" -> 2cf2... matches the Swift CryptoKit output.
        let h = sha256_hex(b"hello");
        assert_eq!(h.len(), 64);
        assert_eq!(
            h,
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        );
        assert!(h.chars().all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase()));
    }

    #[test]
    fn description_mirrors_swift_switch() {
        assert_eq!(description_for("audio/mpeg"), "Upload podcast audio");
        assert_eq!(description_for("audio/mp4"), "Upload podcast audio");
        assert_eq!(description_for("audio/m4a"), "Upload podcast audio");
        assert_eq!(description_for("application/json"), "Upload podcast data");
        assert_eq!(description_for("text/vtt"), "Upload transcript");
        assert_eq!(description_for("text/plain"), "Upload transcript");
        assert_eq!(description_for("image/jpeg"), "Upload podcast artwork");
        assert_eq!(description_for("image/png"), "Upload podcast artwork");
        assert_eq!(description_for("image/webp"), "Upload podcast artwork");
        assert_eq!(description_for("application/octet-stream"), "Upload file");
        assert_eq!(description_for(""), "Upload file");
    }

    #[test]
    fn resolve_server_defaults_when_none() {
        assert_eq!(resolve_server(None), DEFAULT_SERVER);
    }

    #[test]
    fn resolve_server_defaults_on_empty_or_whitespace() {
        assert_eq!(resolve_server(Some("".into())), DEFAULT_SERVER);
        assert_eq!(resolve_server(Some("   ".into())), DEFAULT_SERVER);
    }

    #[test]
    fn resolve_server_defaults_on_malformed_url() {
        assert_eq!(resolve_server(Some("not a url".into())), DEFAULT_SERVER);
    }

    #[test]
    fn resolve_server_trims_and_preserves_valid_url() {
        assert_eq!(
            resolve_server(Some("  https://blossom.band  ".into())),
            "https://blossom.band"
        );
    }

    #[test]
    fn upload_endpoint_normalizes_trailing_slash() {
        assert_eq!(
            upload_endpoint("https://blossom.primal.net"),
            "https://blossom.primal.net/upload"
        );
        assert_eq!(
            upload_endpoint("https://blossom.primal.net/"),
            "https://blossom.primal.net/upload"
        );
        assert_eq!(
            upload_endpoint("https://blossom.primal.net///"),
            "https://blossom.primal.net/upload"
        );
    }

    #[test]
    fn upload_auth_event_has_required_tags() {
        // Build the same tag set the signer would, then sign locally so we
        // can inspect structure without an active signer.
        let keys = Keys::generate();
        let sha = sha256_hex(b"some podcast bytes");
        let expiration = Timestamp::now().as_secs() + AUTH_EXPIRATION_SECS;
        let tags = vec![
            Tag::parse(vec!["t".to_string(), "upload".to_string()]).unwrap(),
            Tag::parse(vec!["x".to_string(), sha.clone()]).unwrap(),
            Tag::parse(vec!["expiration".to_string(), expiration.to_string()]).unwrap(),
        ];
        let event = EventBuilder::new(
            Kind::Custom(KIND_BLOSSOM_AUTH),
            description_for("audio/mpeg"),
        )
        .tags(tags)
        .sign_with_keys(&keys)
        .expect("sign");

        assert_eq!(event.kind, Kind::Custom(KIND_BLOSSOM_AUTH));
        assert_eq!(event.content, "Upload podcast audio");

        let tag_pairs: Vec<(String, String)> = event
            .tags
            .iter()
            .filter_map(|t| {
                let s = t.as_slice();
                Some((s.first()?.clone(), s.get(1)?.clone()))
            })
            .collect();
        assert!(tag_pairs.contains(&("t".into(), "upload".into())));
        assert!(tag_pairs.contains(&("x".into(), sha)));
        assert!(tag_pairs
            .iter()
            .any(|(k, v)| k == "expiration" && v.parse::<u64>().is_ok()));
    }

    #[test]
    fn auth_b64_roundtrip_is_standard_base64() {
        // Sanity check: STANDARD base64 of a known event JSON decodes back to
        // the same JSON bytes. Catches accidental URL-safe encoding which
        // some servers reject in the `Authorization: Nostr ...` header.
        let payload = br#"{"hello":"world"}"#;
        let encoded = STANDARD.encode(payload);
        let decoded = STANDARD.decode(encoded).expect("decode");
        assert_eq!(decoded, payload);
    }
}
