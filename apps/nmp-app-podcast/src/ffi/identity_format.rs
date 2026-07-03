//! Rust-owned Nostr identity formatting helpers for native shells.
//!
//! Native UI can display or copy identities, but NIP-19 encoding belongs with
//! the Rust identity/Nostr stack so iOS and Android cannot drift.

use std::ffi::{c_char, CStr, CString};

use nostr::nips::nip19::ToBech32;
use serde::Serialize;

use super::guard::ffi_guard;

#[derive(Debug, Serialize)]
struct NpubResponse {
    #[serde(skip_serializing_if = "Option::is_none")]
    npub: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<&'static str>,
}

#[derive(Debug, Serialize)]
struct PubkeyResponse {
    #[serde(skip_serializing_if = "Option::is_none")]
    pubkey_hex: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    npub: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<&'static str>,
}

fn encode<T: Serialize>(value: &T) -> *mut c_char {
    match encode_json(value) {
        Ok(json) => match CString::new(json) {
            Ok(c) => c.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

pub(crate) fn npub_from_hex_json(pubkey_hex: &str) -> Option<String> {
    encode_json(&npub_from_hex_response(pubkey_hex.trim())).ok()
}

pub(crate) fn parse_pubkey_json(input: &str) -> Option<String> {
    encode_json(&parse_pubkey_response(input.trim())).ok()
}

fn encode_json<T: Serialize>(value: &T) -> Result<String, serde_json::Error> {
    serde_json::to_string(value)
}

#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub fn nmp_app_podcast_npub_from_hex(pubkey_hex: *const c_char) -> *mut c_char {
    if pubkey_hex.is_null() {
        return std::ptr::null_mut();
    }
    ffi_guard("nmp_app_podcast_npub_from_hex", std::ptr::null_mut, || {
        let hex = match unsafe { CStr::from_ptr(pubkey_hex) }.to_str() {
            Ok(s) => s.trim(),
            Err(_) => {
                return encode(&NpubResponse {
                    npub: None,
                    error: Some("invalid_pubkey"),
                })
            }
        };
        encode(&npub_from_hex_response(hex))
    })
}

fn npub_from_hex_response(hex: &str) -> NpubResponse {
    match nostr::PublicKey::parse(hex).map(|pk| pk.to_bech32()) {
        Ok(Ok(npub)) => NpubResponse {
            npub: Some(npub),
            error: None,
        },
        _ => NpubResponse {
            npub: None,
            error: Some("invalid_pubkey"),
        },
    }
}

#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub fn nmp_app_podcast_parse_pubkey(input: *const c_char) -> *mut c_char {
    if input.is_null() {
        return std::ptr::null_mut();
    }
    ffi_guard("nmp_app_podcast_parse_pubkey", std::ptr::null_mut, || {
        let raw = match unsafe { CStr::from_ptr(input) }.to_str() {
            Ok(s) => s.trim(),
            Err(_) => {
                return encode(&PubkeyResponse {
                    pubkey_hex: None,
                    npub: None,
                    error: Some("invalid_pubkey"),
                })
            }
        };
        encode(&parse_pubkey_response(raw))
    })
}

fn parse_pubkey_response(raw: &str) -> PubkeyResponse {
    match nostr::PublicKey::parse(raw) {
        Ok(pubkey) => PubkeyResponse {
            pubkey_hex: Some(pubkey.to_hex()),
            npub: pubkey.to_bech32().ok(),
            error: None,
        },
        Err(_) => PubkeyResponse {
            pubkey_hex: None,
            npub: None,
            error: Some("invalid_pubkey"),
        },
    }
}
