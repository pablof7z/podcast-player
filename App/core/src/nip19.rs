//! NIP-19 bech32 encoders/decoders — Rust port of
//! `App/Sources/Services/NIP19.swift` plus the nsec/npub helpers from
//! `NostrKeyPair.swift`.
//!
//! Exposes free functions over UniFFI so Swift call sites (currently
//! `NIP19.naddr(...)` and `NostrKeyPair.{nsec,npub}` / its bech32 init)
//! can be cut over to the Rust core in a later phase.
//!
//! All hex inputs are case-insensitive (the underlying `nostr` crate
//! lowercases for us). All hex outputs are lowercase, matching the
//! Swift `Data.hexString` extension.
//!
//! ## Deviations from the Swift original
//!
//! 1. **Errors instead of `nil`.** Swift's `NIP19.naddr` returns
//!    `String?` (nil on bad pubkey); the Rust surface returns
//!    `Result<String, CoreError>` with `CoreError::InvalidInput` so the
//!    Swift caller can surface a precise message. Likewise the Swift
//!    `NostrKeyPair(nsec:)` initialiser throws a single
//!    `invalidPrivateKey`; the Rust decoders return the specific parse
//!    error.
//! 2. **Relay URL hint.** Swift writes arbitrary UTF-8 bytes (skipping
//!    only when `> 255` bytes). `nostr`'s `Nip19Coordinate` requires a
//!    parseable `RelayUrl`. We silently drop a relay hint that fails
//!    to parse — matching the highlighter pattern — rather than failing
//!    the whole encode. An empty / `None` relay is fine.
//! 3. **TLV ordering.** Swift emits TLVs in the order `[d, relay,
//!    pubkey, kind]`. `nostr`'s encoder picks its own (also legal)
//!    order. Both decode identically; the produced naddr string is
//!    NOT byte-identical to Swift's output. Any consumer comparing
//!    naddr strings as opaque IDs must re-encode through a single
//!    implementation.
//! 4. **HRP mismatch is loud.** `nip19_npub_decode("nsec1…")` returns
//!    `InvalidInput`; the Swift originals would silently fail
//!    (`nil`/throw). FFI surface fails loudly with the parse error.

use nostr::nips::nip01::Coordinate;
use nostr::nips::nip19::{FromBech32, Nip19Coordinate, ToBech32};
use nostr::{EventId, Kind, PublicKey, RelayUrl, SecretKey};

use crate::errors::CoreError;

/// Encode a parameterised replaceable Nostr event (NIP-33) as an
/// `naddr1…` bech32 string.
///
/// - `d_tag`: full d-tag identifier, e.g. `"podcast:guid:<uuid>"`.
/// - `pubkey_hex`: 64-char lowercase x-only pubkey hex.
/// - `kind`: Nostr event kind (e.g. 30074, 30075). Narrowed to `u16`
///   on the wire per NIP-01; values > `u16::MAX` will silently wrap.
///   Callers should pass real Nostr kinds (≤ 65535).
/// - `relay_url`: optional relay hint included as TLV type 1. Dropped
///   if it fails to parse as a relay URL.
#[uniffi::export]
pub fn nip19_naddr(
    d_tag: String,
    pubkey_hex: String,
    kind: u32,
    relay_url: Option<String>,
) -> Result<String, CoreError> {
    let public_key = PublicKey::from_hex(&pubkey_hex)
        .map_err(|e| CoreError::InvalidInput(format!("bad pubkey hex: {e}")))?;

    let coordinate = Coordinate {
        kind: Kind::from(kind as u16),
        public_key,
        identifier: d_tag,
    };

    let relays: Vec<RelayUrl> = relay_url
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .and_then(|s| RelayUrl::parse(s).ok())
        .into_iter()
        .collect();

    Nip19Coordinate::new(coordinate, relays)
        .to_bech32()
        .map_err(|e| CoreError::InvalidInput(format!("encode naddr: {e}")))
}

/// Encode a 32-byte x-only public key (hex) as an `npub1…` bech32
/// string.
#[uniffi::export]
pub fn nip19_npub_encode(pubkey_hex: String) -> Result<String, CoreError> {
    let public_key = PublicKey::from_hex(&pubkey_hex)
        .map_err(|e| CoreError::InvalidInput(format!("bad pubkey hex: {e}")))?;
    public_key
        .to_bech32()
        .map_err(|e| CoreError::InvalidInput(format!("encode npub: {e}")))
}

/// Decode an `npub1…` bech32 string back to a 64-char lowercase pubkey
/// hex. Rejects any other HRP (`nsec1…`, `note1…`, etc.) with
/// `InvalidInput`.
#[uniffi::export]
pub fn nip19_npub_decode(npub: String) -> Result<String, CoreError> {
    let public_key = PublicKey::from_bech32(npub.trim())
        .map_err(|e| CoreError::InvalidInput(format!("bad npub: {e}")))?;
    Ok(public_key.to_hex())
}

/// Encode a 32-byte secp256k1 private key (hex) as an `nsec1…` bech32
/// string.
#[uniffi::export]
pub fn nip19_nsec_encode(privkey_hex: String) -> Result<String, CoreError> {
    let secret_key = SecretKey::from_hex(&privkey_hex)
        .map_err(|e| CoreError::InvalidInput(format!("bad privkey hex: {e}")))?;
    secret_key
        .to_bech32()
        .map_err(|e| CoreError::InvalidInput(format!("encode nsec: {e}")))
}

/// Decode an `nsec1…` bech32 string back to a 64-char lowercase
/// privkey hex. Rejects any other HRP with `InvalidInput`.
#[uniffi::export]
pub fn nip19_nsec_decode(nsec: String) -> Result<String, CoreError> {
    let secret_key = SecretKey::from_bech32(nsec.trim())
        .map_err(|e| CoreError::InvalidInput(format!("bad nsec: {e}")))?;
    Ok(secret_key.to_secret_hex())
}

/// Decode a `note1…` bech32 string back to a 64-char lowercase event
/// id hex. Rejects any other HRP with `InvalidInput`.
#[uniffi::export]
pub fn nip19_note_decode(note: String) -> Result<String, CoreError> {
    let event_id = EventId::from_bech32(note.trim())
        .map_err(|e| CoreError::InvalidInput(format!("bad note: {e}")))?;
    Ok(event_id.to_hex())
}

#[cfg(test)]
mod tests {
    use super::*;

    // Real example pubkey/event from the NIP-19 spec / common test vectors.
    const PUBKEY_HEX: &str =
        "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d";
    const NPUB: &str = "npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6";

    const PRIVKEY_HEX: &str =
        "67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa";
    const NSEC: &str = "nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5";

    #[test]
    fn npub_encode_matches_spec_vector() {
        let out = nip19_npub_encode(PUBKEY_HEX.to_string()).expect("encode");
        assert_eq!(out, NPUB);
    }

    #[test]
    fn npub_decode_matches_spec_vector() {
        let out = nip19_npub_decode(NPUB.to_string()).expect("decode");
        assert_eq!(out, PUBKEY_HEX);
    }

    #[test]
    fn npub_round_trip() {
        let bech = nip19_npub_encode(PUBKEY_HEX.to_string()).expect("encode");
        let hex = nip19_npub_decode(bech).expect("decode");
        assert_eq!(hex, PUBKEY_HEX);
    }

    #[test]
    fn nsec_encode_matches_spec_vector() {
        let out = nip19_nsec_encode(PRIVKEY_HEX.to_string()).expect("encode");
        assert_eq!(out, NSEC);
    }

    #[test]
    fn nsec_decode_matches_spec_vector() {
        let out = nip19_nsec_decode(NSEC.to_string()).expect("decode");
        assert_eq!(out, PRIVKEY_HEX);
    }

    #[test]
    fn nsec_round_trip() {
        let bech = nip19_nsec_encode(PRIVKEY_HEX.to_string()).expect("encode");
        let hex = nip19_nsec_decode(bech).expect("decode");
        assert_eq!(hex, PRIVKEY_HEX);
    }

    #[test]
    fn note_round_trip() {
        let event_id_hex =
            "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef".to_string();
        let event_id =
            EventId::from_hex(&event_id_hex).expect("event id");
        let bech = event_id.to_bech32().expect("encode note");
        assert!(bech.starts_with("note1"), "got {bech}");

        let hex = nip19_note_decode(bech).expect("decode");
        assert_eq!(hex, event_id_hex);
    }

    #[test]
    fn naddr_round_trip_with_relay() {
        let d_tag = "podcast:guid:abc-123".to_string();
        let bech = nip19_naddr(
            d_tag.clone(),
            PUBKEY_HEX.to_string(),
            30075,
            Some("wss://relay.example.com".to_string()),
        )
        .expect("encode");
        assert!(bech.starts_with("naddr1"), "got {bech}");

        let decoded = Nip19Coordinate::from_bech32(&bech).expect("decode");
        assert_eq!(decoded.coordinate.kind.as_u16() as u32, 30075);
        assert_eq!(decoded.coordinate.identifier, d_tag);
        assert_eq!(decoded.coordinate.public_key.to_hex(), PUBKEY_HEX);
        assert!(
            decoded.relays.iter().any(|r| r.to_string().contains("relay.example.com")),
            "relays: {:?}",
            decoded.relays
        );
    }

    #[test]
    fn naddr_round_trip_without_relay() {
        let d_tag = "podcast:guid:xyz".to_string();
        let bech =
            nip19_naddr(d_tag.clone(), PUBKEY_HEX.to_string(), 30074, None).expect("encode");
        assert!(bech.starts_with("naddr1"));

        let decoded = Nip19Coordinate::from_bech32(&bech).expect("decode");
        assert_eq!(decoded.coordinate.kind.as_u16() as u32, 30074);
        assert_eq!(decoded.coordinate.identifier, d_tag);
        assert_eq!(decoded.coordinate.public_key.to_hex(), PUBKEY_HEX);
        assert!(decoded.relays.is_empty());
    }

    #[test]
    fn naddr_drops_unparseable_relay() {
        // Garbage relay URL should be silently dropped — the encode
        // still succeeds without a relay TLV.
        let bech = nip19_naddr(
            "d".to_string(),
            PUBKEY_HEX.to_string(),
            30075,
            Some("not a url".to_string()),
        )
        .expect("encode");
        let decoded = Nip19Coordinate::from_bech32(&bech).expect("decode");
        assert!(decoded.relays.is_empty());
    }

    #[test]
    fn naddr_rejects_bad_pubkey() {
        let err = nip19_naddr(
            "d".to_string(),
            "not-hex".to_string(),
            30075,
            None,
        );
        assert!(err.is_err());
    }

    #[test]
    fn npub_decode_rejects_nsec() {
        // HRP mismatch must fail loudly.
        let err = nip19_npub_decode(NSEC.to_string());
        assert!(err.is_err());
    }

    #[test]
    fn nsec_decode_rejects_npub() {
        let err = nip19_nsec_decode(NPUB.to_string());
        assert!(err.is_err());
    }

    #[test]
    fn note_decode_rejects_npub() {
        let err = nip19_note_decode(NPUB.to_string());
        assert!(err.is_err());
    }

    #[test]
    fn npub_encode_rejects_bad_hex() {
        assert!(nip19_npub_encode("not-hex".to_string()).is_err());
        // Wrong length.
        assert!(nip19_npub_encode("ab".to_string()).is_err());
    }

    #[test]
    fn nsec_encode_rejects_bad_hex() {
        assert!(nip19_nsec_encode("not-hex".to_string()).is_err());
        assert!(nip19_nsec_encode("ab".to_string()).is_err());
    }

    #[test]
    fn decoders_trim_whitespace() {
        let padded = format!("  {NPUB}  ");
        let hex = nip19_npub_decode(padded).expect("decode");
        assert_eq!(hex, PUBKEY_HEX);
    }
}
