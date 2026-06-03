//! User-identity social publishing — kind:0 (profile), kind:1 (note),
//! and kind:9802 (NIP-84 highlight) for the signed-in user.
//!
//! ## What this is
//!
//! These handlers publish the user's social events through the kernel's
//! active-account signer. No secret bytes and no `nostr::Event` construction
//! live here: each handler assembles plain `{kind, tags, content}` (or the
//! kind:0 `fields` map) and dispatches `nmp.publish { PublishRaw }` /
//! `nmp.publish { PublishProfile }`. NMP fills `pubkey` from the active
//! account, stamps `created_at` (D7 — kernel owns the wall clock), signs with
//! the active signer (local nsec OR NIP-46 bunker — both are handled by the
//! kernel), and routes through the NIP-65 outbox (D3).
//!
//! ## Active-account requirement
//!
//! Publishing requires a signed-in account. The kernel owns the signer; this
//! handler guards on the podcast-app [`IdentityStore`]'s `pubkey_hex` (mirror
//! of the signed-in state) and returns `{"ok": false, "error": "not signed
//! in"}` when empty. Both local-key and bunker identities publish through the
//! same kernel path now — the prior "local key only" limitation is gone since
//! signing no longer happens in app code.
//!
//! ## Null-app guard
//!
//! Unit tests run with `app == null_mut()`. The dispatch helpers in
//! [`crate::nmp_dispatch`] short-circuit to `"signed"` under a null pointer,
//! so the handlers return `{"ok": true, "status": "signed"}` without touching
//! the FFI boundary.

use std::sync::{Arc, Mutex};

use serde_json::json;

use crate::nmp_dispatch::{publish_profile_via_nmp, publish_raw_via_nmp};
use crate::store::identity::IdentityStore;
use nmp_ffi::NmpApp;

/// NIP-84 highlight event kind.
const KIND_HIGHLIGHT: u32 = 9802;
/// NIP-01 text note event kind.
const KIND_TEXT_NOTE: u32 = 1;

/// Guard: the active account must be signed in. Returns the `{"ok": false}`
/// error envelope (already shaped for return) when not, so callers early-return.
fn require_signed_in(identity: &Arc<Mutex<IdentityStore>>) -> Result<(), serde_json::Value> {
    match identity.lock() {
        Ok(id) if id.pubkey_hex.is_some() => Ok(()),
        Ok(_) => Err(json!({"ok": false, "error": "not signed in"})),
        Err(_) => Err(json!({"ok": false, "error": "identity poisoned"})),
    }
}

// ── kind:0 profile ───────────────────────────────────────────────────

/// Assemble the kind:0 `fields` map from the supplied profile values.
/// Pure helper so the field shape can be unit-tested without a kernel.
pub(crate) fn build_profile_fields(
    name: &str,
    display_name: Option<&str>,
    about: Option<&str>,
    picture: Option<&str>,
) -> serde_json::Map<String, serde_json::Value> {
    let mut fields = serde_json::Map::new();
    fields.insert("name".to_string(), json!(name));
    if let Some(v) = display_name {
        fields.insert("display_name".to_string(), json!(v));
    }
    if let Some(v) = about {
        fields.insert("about".to_string(), json!(v));
    }
    if let Some(v) = picture {
        fields.insert("picture".to_string(), json!(v));
    }
    fields
}

/// `podcast.social` `publish_profile` — publish a kind:0 metadata event with
/// the supplied profile fields via the kernel's active-account signer.
#[allow(clippy::too_many_arguments)]
pub fn handle_publish_profile(
    app: *mut NmpApp,
    identity: &Arc<Mutex<IdentityStore>>,
    name: &str,
    display_name: Option<&str>,
    about: Option<&str>,
    picture: Option<&str>,
    _correlation_id: &str,
) -> serde_json::Value {
    if let Err(e) = require_signed_in(identity) {
        return e;
    }
    let fields = build_profile_fields(name, display_name, about, picture);
    let status = publish_profile_via_nmp(app, fields);
    json!({"ok": true, "status": status})
}

// ── kind:1 note ──────────────────────────────────────────────────────

/// `podcast.social` `publish_note` — publish a kind:1 text note carrying the
/// supplied free-form tags verbatim. Rejects empty content (parity with
/// `agent_note_handler`).
pub fn handle_publish_note(
    app: *mut NmpApp,
    identity: &Arc<Mutex<IdentityStore>>,
    content: &str,
    tags: Option<&Vec<Vec<String>>>,
    _correlation_id: &str,
) -> serde_json::Value {
    if content.trim().is_empty() {
        return json!({"ok": false, "error": "empty note"});
    }
    if let Err(e) = require_signed_in(identity) {
        return e;
    }
    let tags = tags.cloned().unwrap_or_default();
    let status = publish_raw_via_nmp(app, KIND_TEXT_NOTE, &tags, content);
    json!({"ok": true, "status": status})
}

// ── kind:9802 highlight (NIP-84) ─────────────────────────────────────

/// `podcast.social` `publish_highlight` — publish a kind:9802 NIP-84
/// highlight carrying the supplied free-form tags verbatim. The caller
/// (Swift `publishUserClip`) assembles the full NIP-73 / NIP-84 tag set;
/// tag *assembly* staying Swift-side is not a D7 violation — only signing
/// moved to the kernel, and the kernel now owns it entirely.
pub fn handle_publish_highlight(
    app: *mut NmpApp,
    identity: &Arc<Mutex<IdentityStore>>,
    content: &str,
    tags: Option<&Vec<Vec<String>>>,
    _correlation_id: &str,
) -> serde_json::Value {
    if content.trim().is_empty() {
        return json!({"ok": false, "error": "empty highlight"});
    }
    if let Err(e) = require_signed_in(identity) {
        return e;
    }
    let tags = tags.cloned().unwrap_or_default();
    let status = publish_raw_via_nmp(app, KIND_HIGHLIGHT, &tags, content);
    json!({"ok": true, "status": status})
}

#[cfg(test)]
#[path = "social_publish_handler_tests.rs"]
mod tests;
