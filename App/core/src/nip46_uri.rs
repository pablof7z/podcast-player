//! `nostrconnect://` URI construction + small helpers used by the NIP-46
//! pairing flow. Split out from `nip46.rs` to keep that file under the
//! 500-line cap.

use nostr_sdk::prelude::*;

use crate::errors::CoreError;

/// Generate a 16-byte hex secret for the `nostrconnect://` URI. The remote
/// signer echoes this back so we know it's the same peer we handed the URI to.
pub(crate) fn random_secret() -> String {
    use rand::RngCore;
    let mut buf = [0u8; 16];
    rand::rngs::OsRng.fill_bytes(&mut buf);
    hex::encode(buf)
}

// `rand` is re-exported by `nostr_sdk::prelude::*` (via secp256k1). No extra
// dependency added.

/// Build the outgoing `nostrconnect://<local>?metadata=…&relay=…&secret=…`
/// URI we render as a QR / hand to a signer app.
pub(crate) fn build_nostr_connect_uri(
    local_public_key: PublicKey,
    relay_url: &str,
    metadata: &NostrConnectMetadata,
    secret: &str,
) -> Result<String, CoreError> {
    let relay = RelayUrl::parse(relay_url)
        .map_err(|e| CoreError::InvalidInput(format!("nostrconnect relay: {e}")))?;

    // `NostrConnectURI::Display` for the Client variant encodes
    // `metadata=<json>&relay=…` but does NOT include the `secret=` query,
    // and the secret is mandatory for our flow. Build the query by hand so
    // the bytes still round-trip through the SDK's `parse`.
    let metadata_json = metadata.as_json();
    Ok(format!(
        "nostrconnect://{}?metadata={}&relay={}&secret={}",
        local_public_key.to_hex(),
        percent_encode(&metadata_json),
        relay.as_str_without_trailing_slash(),
        percent_encode(secret),
    ))
}

/// Minimal percent-encoder for query values (RFC 3986 unreserved set).
fn percent_encode(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for b in input.bytes() {
        let keep = matches!(b,
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' |
            b'-' | b'_' | b'.' | b'~'
        );
        if keep {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{:02X}", b));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_uri_contains_required_params() {
        let keys = Keys::generate();
        let mut md = NostrConnectMetadata::new("Podcastr");
        if let Ok(u) = Url::parse("https://podcastr.example") {
            md = md.url(u);
        }
        let uri = build_nostr_connect_uri(
            keys.public_key(),
            "wss://relay.nsec.app",
            &md,
            "deadbeef00",
        )
        .expect("build uri");

        assert!(uri.starts_with("nostrconnect://"));
        assert!(uri.contains(&keys.public_key().to_hex()));
        assert!(uri.contains("relay=wss://relay.nsec.app"));
        assert!(uri.contains("secret=deadbeef00"));
        assert!(uri.contains("metadata="));
    }

    #[test]
    fn random_secret_is_32_hex_chars() {
        let s = random_secret();
        assert_eq!(s.len(), 32);
        assert!(s.chars().all(|c| c.is_ascii_hexdigit()));
    }
}
