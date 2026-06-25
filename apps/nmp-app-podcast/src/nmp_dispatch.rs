//! NMP dispatch helpers — the seams Rust action handlers use to hand
//! work to NMP without naming relay URLs or holding secret keys.
//!
//! * [`register_podcast_signer_in_kernel`] — register a per-podcast secret as
//!   a non-active signer in the kernel's identity roster via
//!   `nmp_app_signin_nsec(make_active=0)`. Idempotent: re-registering an
//!   already-registered key is safe (the kernel's `AddSigner` path overwrites
//!   the slot). Must be dispatched BEFORE the corresponding `publish_raw_with_signer_via_nmp`
//!   or `blossom_upload_via_nmp` call — the kernel queue is FIFO so the signer
//!   is guaranteed to be present when the sign-time lookup runs (D13).
//! * [`publish_raw_with_signer_via_nmp`] — dispatch unsigned
//!   `{kind, tags, content, signer_pubkey}` to `nmp.publish { PublishRaw }`.
//!   `signer_pubkey: Some(hex)` routes signing to the named per-podcast key
//!   (registered via `register_podcast_signer_in_kernel`); `None` falls back
//!   to the active account. NMP's `sign_with_account_nonblocking` resolves the
//!   named key across local-key + remote maps, transparent to the caller.
//! * [`write_relay_urls`] — read the app's configured relays and filter to
//!   write-capable roles (write, both, both,indexer).
//! * [`publish_raw_with_signer_to_relays_via_nmp`] — dispatch unsigned
//!   `{kind, tags, content, signer_pubkey}` to `nmp.publish { PublishRaw }`
//!   with explicit write-relay routing. Falls back to Auto if no relays given.
//! * [`publish_raw_via_nmp`] — dispatch unsigned `{kind, tags, content}` to
//!   `nmp.publish { PublishRaw }`. NMP signs with the active signer (local
//!   nsec or NIP-46 bunker — both handled transparently by the kernel's
//!   `sign_active_nonblocking` / `PendingSign` path), stamps `created_at`
//!   (D9), and routes via Auto. Used for all events the user signs:
//!   kind:10064 author-claims, kind:1111 comments, kind:1 agent notes.
//! * [`blossom_upload_via_nmp`] — dispatch `nmp.blossom.upload` with
//!   `signer_pubkey: Some(hex)` so the kernel signs the kind:24242 Blossom
//!   auth event with the named per-podcast key (D13 — no raw secret bytes
//!   in app code). Returns the correlation id string; the result rides the
//!   `action_results` snapshot slot.
//! * [`push_interest_via_nmp`] — push a [`LogicalInterest`] into NMP's relay
//!   pool so the kernel opens the subscription without any iOS WebSocket.

use std::ffi::CString;

use nmp_core::dispatch_envelope::{encode_dispatch_envelope, DISPATCH_ENVELOPE_SCHEMA_VERSION};
use nmp_core::publish::{PublishAction, PublishTarget};
use nmp_core::substrate::ActionPayload;
use nmp_ffi::NmpApp;
use nmp_planner::LogicalInterest;

/// Register a per-podcast secret key in the kernel's identity roster without
/// activating it. `secret_hex` must be a 64-char lowercase hex string (the
/// form [`crate::store::podcast_keys::PodcastKeyStore`] stores and returns).
///
/// The kernel's `AddSigner` path is idempotent: re-registering an already
/// registered key overwrites the roster slot without side effects. Call this
/// BEFORE the matching `publish_raw_with_signer_via_nmp` / `blossom_upload_via_nmp`
/// — the FIFO actor queue guarantees the signer is present when the sign-time
/// lookup fires. No-op on a null app (unit tests / pre-login).
pub(crate) fn register_podcast_signer_in_kernel(app: *mut nmp_ffi::NmpApp, secret_hex: &str) {
    if app.is_null() {
        return;
    }
    // `nmp_app_signin_nsec` accepts either a bech32 `nsec1…` OR a raw 64-char
    // hex string — `parse_secret` in nmp-core tries both forms. We pass the
    // hex directly so no bech32 encoding is needed here.
    let Ok(secret_c) = CString::new(secret_hex) else {
        return;
    };
    nmp_ffi::nmp_app_signin_nsec(app, secret_c.as_ptr(), 0);
}

/// Register the app-owned local identity as NMP's ACTIVE signer.
///
/// `IdentityStore` is the podcast app's durable local-key store and feeds the
/// `active_account` projection. NMP publish commands sign through NMP-core's
/// active signer roster, so every successful app identity import/generate/load
/// must also register that same secret here with `make_active=1`.
pub(crate) fn activate_local_signer_in_kernel(app: *mut nmp_ffi::NmpApp, secret_hex: &str) {
    if app.is_null() {
        return;
    }
    let Ok(secret_c) = CString::new(secret_hex) else {
        return;
    };
    nmp_ffi::nmp_app_signin_nsec(app, secret_c.as_ptr(), 1);
}

/// Remove an app-owned local account from NMP-core's signer roster.
pub(crate) fn remove_account_from_kernel(app: *mut nmp_ffi::NmpApp, pubkey_hex: &str) {
    if app.is_null() {
        return;
    }
    let Ok(pubkey_c) = CString::new(pubkey_hex) else {
        return;
    };
    nmp_ffi::nmp_app_remove_account(app, pubkey_c.as_ptr());
}

/// Extract the app's configured relays filtered to write-capable roles.
/// Returns the set of relay URLs where role is "write", "both", or starts
/// with "both," (e.g. "both,indexer"). Returns an empty vec on null app,
/// poisoned lock, or no matching relays (D6: errors as data).
pub(crate) fn write_relay_urls(app: *mut NmpApp) -> Vec<String> {
    if app.is_null() {
        return Vec::new();
    }
    let slot = unsafe { &*app }.configured_relays_handle();
    let Ok(guard) = slot.lock() else {
        return Vec::new();
    };
    guard
        .as_slice()
        .iter()
        .filter(|relay| {
            relay.role().split(',').any(|r| matches!(r.trim(), "write" | "both"))
        })
        .map(|relay| relay.url().to_string())
        .collect()
}

/// Dispatch unsigned event parameters to `nmp.publish { PublishRaw }` with an
/// explicit `signer_pubkey`. The kernel's `sign_with_account_nonblocking` looks
/// up the named pubkey hex across the local-key + remote (NIP-46) roster —
/// identical to signing the active account but without switching it.
///
/// The named signer MUST be registered before this call; use
/// [`register_podcast_signer_in_kernel`] immediately before dispatching.
///
/// Returns `"queued"` (async) or `"signed"` (null app).
pub(crate) fn publish_raw_with_signer_via_nmp(
    app: *mut nmp_ffi::NmpApp,
    kind: u32,
    tags: &[Vec<String>],
    content: &str,
    signer_pubkey_hex: &str,
) -> &'static str {
    if app.is_null() {
        return "signed";
    }
    let action = PublishAction::PublishRaw {
        kind,
        tags: tags.to_vec(),
        content: content.to_string(),
        target: PublishTarget::Auto,
        signer_pubkey: Some(signer_pubkey_hex.to_string()),
    };
    dispatch_nmp_publish(app, action)
}

/// Dispatch unsigned event parameters to `nmp.publish { PublishRaw }` with
/// explicit write-relay routing via the per-podcast signer. When `relay_urls`
/// is non-empty, uses `PublishTarget::Explicit { relays }` to bypass the NIP-65
/// outbox resolver and publish directly to the given relay set. Falls back to
/// `PublishTarget::Auto` when the relay list is empty so callers that have no
/// configured write relays still get best-effort delivery.
///
/// The named signer MUST be registered before this call; use
/// [`register_podcast_signer_in_kernel`] immediately before dispatching.
///
/// Returns `"queued"` (async) or `"signed"` (null app).
pub(crate) fn publish_raw_with_signer_to_relays_via_nmp(
    app: *mut nmp_ffi::NmpApp,
    kind: u32,
    tags: &[Vec<String>],
    content: &str,
    signer_pubkey_hex: &str,
    relay_urls: &[String],
) -> &'static str {
    if !relay_urls.is_empty() {
        let action = PublishAction::PublishRaw {
            kind,
            tags: tags.to_vec(),
            content: content.to_string(),
            target: PublishTarget::Explicit { relays: relay_urls.to_vec() },
            signer_pubkey: Some(signer_pubkey_hex.to_string()),
        };
        return dispatch_nmp_publish(app, action);
    }
    publish_raw_with_signer_via_nmp(app, kind, tags, content, signer_pubkey_hex)
}

/// Dispatch `nmp.blossom.upload` routing the kind:24242 signature to a named
/// per-podcast key. The kernel Build → Sign → Transport pipeline handles
/// hashing, auth-event construction, and HTTP transport — no raw secret bytes
/// or HTTP in app code (D13).
///
/// `servers` must contain at least one valid `http(s)://` URL or the kernel's
/// `UploadAction::start` will reject the dispatch.
///
/// The named signer MUST be registered before this call; use
/// [`register_podcast_signer_in_kernel`] immediately before dispatching.
///
/// Returns a correlation id string the caller can use to retrieve the blob
/// descriptor from the `action_results` snapshot slot, or `None` when `app`
/// is null (unit tests / pre-login) or the dispatch was rejected.
pub(crate) fn blossom_upload_via_nmp(
    app: *mut nmp_ffi::NmpApp,
    file_path: &str,
    servers: &[String],
    signer_pubkey_hex: &str,
) -> Option<String> {
    if app.is_null() {
        return None;
    }
    let input = nmp_blossom::UploadInput {
        file_path: file_path.to_string(),
        content_type: None,
        servers: servers.to_vec(),
        signer_pubkey: Some(signer_pubkey_hex.to_string()),
    };
    let response = dispatch_typed_envelope(app, "nmp.blossom.upload", &input.encode())?;

    // Parse the correlation_id from the accept envelope.
    let parsed: serde_json::Value = serde_json::from_str(&response).ok()?;
    parsed
        .get("correlation_id")
        .and_then(|v| v.as_str())
        .map(str::to_owned)
}

/// Dispatch unsigned event parameters to `nmp.publish { PublishRaw }` using
/// the ACTIVE account signer. NMP signs with the active signer (local nsec or
/// NIP-46 bunker — transparent to the caller; bunker ops park on the kernel's
/// `PendingSign` queue and resolve asynchronously), stamps `created_at` (D9),
/// and routes via `PublishTarget::Auto`. NMP resolves `Auto` through the NIP-65
/// outbox resolver: cached author write relays first, with the active account's
/// locally configured write relays as the bootstrap fallback before the user's
/// kind:10002 relay list has echoed back. No secret bytes in app code.
/// Used for events the user signs: kind:10064 author-claims, kind:1111 comments,
/// kind:1 notes, and kind:9802 highlights.
/// For per-podcast keys use [`publish_raw_with_signer_via_nmp`] instead.
/// Returns `"queued"` or `"signed"` (null app).
pub(crate) fn publish_raw_via_nmp(
    app: *mut nmp_ffi::NmpApp,
    kind: u32,
    tags: &[Vec<String>],
    content: &str,
) -> &'static str {
    if app.is_null() {
        return "signed";
    }
    let action = PublishAction::PublishRaw {
        kind,
        tags: tags.to_vec(),
        content: content.to_string(),
        target: PublishTarget::Auto,
        signer_pubkey: None,
    };
    dispatch_nmp_publish(app, action)
}

/// Dispatch a kind:0 profile metadata update to `nmp.publish { PublishProfile }`.
/// `fields` is a flat string-valued JSON object (`name`, `display_name`,
/// `about`, `picture`, …); the kernel serialises it into the kind:0 `content`,
/// signs with the active signer, stamps `created_at` (D7), and routes via the
/// NIP-65 outbox. No secret bytes in app code; the host never builds the event.
/// Returns `"queued"` or `"signed"` (null app).
pub(crate) fn publish_profile_via_nmp(
    app: *mut nmp_ffi::NmpApp,
    fields: serde_json::Map<String, serde_json::Value>,
) -> &'static str {
    if app.is_null() {
        return "signed";
    }
    let action = PublishAction::PublishProfile { fields };
    dispatch_nmp_publish(app, action)
}

/// Self-enqueue a `podcast.publish` action back onto the actor queue.
///
/// `nmp_app_dispatch_action` only *validates* the action and enqueues an
/// `ActorCommand::DispatchHostOp` (D8: no actor round-trip, no blocking),
/// then returns immediately. Calling it from inside a host-op handler
/// appends a follow-up command to the actor's own queue — so the dispatched
/// op runs in its OWN later tick and the actor yields in between. This is the
/// non-blocking way for a handler to fan a single op out into N independent
/// ops without stalling reactivity (the old Swift loop's per-episode
/// `kernelPublishEpisode` had this property; this preserves it while keeping
/// the policy in the kernel — D0).
///
/// Returns `true` when the action was accepted (a `correlation_id` was
/// minted), `false` on a null app (tests / pre-login) or a rejected action.
pub(crate) fn self_dispatch_publish(app: *mut nmp_ffi::NmpApp, body: serde_json::Value) -> bool {
    if app.is_null() {
        return false;
    }
    // `podcast.publish` is an APP-OWNED namespace whose `Action` the kernel does
    // not model — it rides the OPAQUE byte route (#1756): the kernel passes the
    // serde-JSON bytes through undecoded and the module's own `serde_json` deser
    // reconstructs the action.
    let Ok(payload) = serde_json::to_vec(&body) else {
        return false;
    };
    match dispatch_opaque_envelope(app, "podcast.publish", &payload) {
        Some(response) => response.contains("\"correlation_id\""),
        None => false,
    }
}

/// Push a [`LogicalInterest`] into NMP's relay pool. The kernel opens the
/// subscription through its own connections — no iOS WebSocket ever opened.
pub(crate) fn push_interest_via_nmp(app: *mut nmp_ffi::NmpApp, interest: LogicalInterest) {
    if app.is_null() {
        return;
    }
    // SAFETY: app is non-null.
    unsafe { &*app }.push_interest(interest);
}

fn dispatch_nmp_publish(app: *mut nmp_ffi::NmpApp, action: PublishAction) -> &'static str {
    match dispatch_typed_envelope(app, "nmp.publish", &action.encode()) {
        Some(_) => "queued",
        None => "signed",
    }
}

/// Mint a fresh, process-unique envelope correlation id.
///
/// On the byte lane the operation identity is the HOST-SUPPLIED envelope
/// `correlation_id`, echoed back end-to-end (ADR-0064 §4). A random UUIDv4
/// (already a workspace dep) is the simplest collision-free choice.
fn mint_correlation_id() -> String {
    uuid::Uuid::new_v4().to_string()
}

/// Build a `DispatchEnvelope` carrying a TYPED FlatBuffers `payload` for
/// `namespace` and dispatch it through the byte doorway. Returns the response
/// JSON string (`{"correlation_id":…}` / `{"error":…}`), or `None` on a null
/// app or a `payload` longer than the envelope encoder can frame.
///
/// `payload` is the output of an [`ActionPayload::encode`] (e.g.
/// `PublishAction::encode` / `UploadInput::encode`) — the kernel decodes it
/// through the namespace's typed `decode_payload`.
fn dispatch_typed_envelope(
    app: *mut nmp_ffi::NmpApp,
    namespace: &str,
    payload: &[u8],
) -> Option<String> {
    dispatch_envelope(app, namespace, payload)
}

/// Build a `DispatchEnvelope` carrying an OPAQUE app-owned `payload` (serde-JSON
/// bytes) for an app-owned `podcast.*` `namespace` and dispatch it through the
/// byte doorway. Identical framing to [`dispatch_typed_envelope`] — the only
/// difference is the kernel route: an opaque-opted module (`accepts_opaque_payload`)
/// passes the bytes through undecoded and runs its own `serde_json` deser.
fn dispatch_opaque_envelope(
    app: *mut nmp_ffi::NmpApp,
    namespace: &str,
    payload: &[u8],
) -> Option<String> {
    dispatch_envelope(app, namespace, payload)
}

/// Shared envelope build + byte-doorway dispatch. Mints a correlation id, frames
/// the `DispatchEnvelope` (`encode_dispatch_envelope`), drives the bytes through
/// `nmp_app_dispatch_action_bytes`, and returns the response JSON string. The
/// envelope framing is identical for the typed and opaque routes; only the
/// kernel-side decode differs (by namespace registration).
fn dispatch_envelope(
    app: *mut nmp_ffi::NmpApp,
    namespace: &str,
    payload: &[u8],
) -> Option<String> {
    if app.is_null() {
        return None;
    }
    let correlation_id = mint_correlation_id();
    let envelope = encode_dispatch_envelope(
        &correlation_id,
        namespace,
        DISPATCH_ENVELOPE_SCHEMA_VERSION,
        payload,
    );
    let raw = nmp_ffi::nmp_app_dispatch_action_bytes(app, envelope.as_ptr(), envelope.len());
    if raw.is_null() {
        return None;
    }
    // SAFETY: `raw` is a heap-owned NUL-terminated C string minted by
    // `nmp_app_dispatch_action_bytes`; read it, copy out, then free.
    let response = unsafe { std::ffi::CStr::from_ptr(raw) }
        .to_string_lossy()
        .into_owned();
    nmp_ffi::nmp_free_string(raw);
    Some(response)
}
