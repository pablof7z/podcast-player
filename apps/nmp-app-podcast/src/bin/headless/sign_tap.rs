//! Signed-event observation tap for the headless harness.
//!
//! ## Why this exists
//!
//! The per-podcast NIP-F4 publish path (`publish_show` / `publish_episode`)
//! routes signing through the kernel via `register_podcast_signer_in_kernel`
//! (`AddSigner { make_active: false }`) followed by
//! `PublishRaw { signer_pubkey }`. To PROVE the kernel actually signs with the
//! per-podcast key (correct `pubkey` + valid `sig`), a test must observe the
//! kernel's signed output.
//!
//! Offline (no relay), a `PublishRaw` of a kind:10154/54 event never reaches
//! any FFI-readable projection that carries the signed bytes:
//!   - `action_results` records `result_json: None` for a publish terminal.
//!   - the publish-outbox projection carries `event_id` but not `pubkey`/`sig`.
//!   - the raw-event observer fires only on STORE INGEST, which does not happen
//!     for a self-published kind:10154/54 with no relay echo.
//!   - the `signed_events` sidecar is populated ONLY by `SignEventForReturn`,
//!     never by `PublishRaw`.
//!
//! The one in-process, network-free seam that exposes a signed event's
//! `pubkey` + `sig` is the D13 **sign-and-return** path
//! (`nmp_app_sign_event_for_return`): it signs an unsigned draft with a NAMED
//! (possibly non-active) account and parks the signed JSON in the
//! `signed_events` push-frame projection, keyed by a correlation id — it NEVER
//! publishes, so no relay is required.
//!
//! Crucially, sign-and-return resolves the named signer through the EXACT same
//! `sign_with_account_nonblocking(identity, pubkey, …)` call the
//! `PublishRaw { signer_pubkey }` path uses (see nmp-core
//! `actor/commands/publish.rs` vs `actor/dispatch.rs::SignEventForReturn`).
//! Both depend on the per-podcast key being present in the kernel's signer
//! roster — which is exactly what `register_podcast_signer_in_kernel` installs.
//! So driving a sign-and-return with the per-podcast pubkey proves:
//!   1. the key was registered as a usable kernel signer (drop the register
//!      call → the named signer is absent → sign returns an `Err` verdict), and
//!   2. the kernel signs with the per-podcast `pubkey`, producing a valid `sig`.
//!
//! ## Mechanism
//!
//! `signed_events` is a Tier-2 typed FlatBuffer sidecar drained into the push
//! frame on emit (not a re-runnable registered projection, so
//! `nmp_app_read_projection_json` cannot see it). We install an update callback
//! that captures each frame's bytes, decode them with
//! `nmp_app_podcast_decode_update_frame`, and read
//! `v.projections.signed_events[correlation_id]`.
//!
//! `nmp_app_podcast_decode_update_frame` is a `#[no_mangle]` symbol defined in
//! the podcast crate's `ffi/snapshot.rs`. It is not re-exported from the crate
//! root at the Rust item level (`ffi::snapshot` is `pub(crate)`), but it is a
//! linkable C-ABI symbol, so it is declared here in an `extern "C"` block.
//! Signing and the update-frame callback now go through the typed
//! `nmp_native_runtime` / `nmp_uniffi_support` surfaces instead of C-ABI calls.

use std::ffi::{c_char, CString};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use nmp_native_runtime::NmpApp;

// ── Externally-linked C-ABI symbol not re-exported from the crate root ────────
//
// `NmpApp` is an opaque kernel handle; the podcast crate itself declares this
// symbol with the identical opaque-pointer-free signature (it takes raw bytes,
// not `*mut NmpApp`), so the `improper_ctypes` lint is not applicable here.
extern "C" {
    /// Decode a raw update-frame byte slice into the
    /// `{"t":"snapshot","v":{…,"projections":{"signed_events":…}}}` JSON shape.
    /// Defined in the podcast crate's `ffi/snapshot.rs` (`#[no_mangle]`).
    fn nmp_app_podcast_decode_update_frame(bytes: *const u8, len: usize) -> *mut c_char;
}

/// Captured `signed_events` rows, merged across every frame the callback has
/// seen, keyed by `correlation_id` → `signed_json` (success) or an `Err`
/// message (failure verdict). The callback decodes each frame and merges any
/// `signed_events` entries here so a poller can find its id regardless of which
/// frame carried it.
static CAPTURED: OnceLock<Mutex<Vec<(String, Result<String, String>)>>> = OnceLock::new();

fn captured() -> &'static Mutex<Vec<(String, Result<String, String>)>> {
    CAPTURED.get_or_init(|| Mutex::new(Vec::new()))
}

/// Update-frame callback. Decodes the frame and merges any `signed_events`
/// rows into `CAPTURED`. Best-effort: any decode/parse failure is a silent
/// no-op (the poller times out, never panics — matches the kernel's D6 stance).
fn capture_frame(bytes: &[u8]) {
    if bytes.is_empty() {
        return;
    }
    // SAFETY: `bytes` is a valid Rust slice, trivially valid for its own length.
    let decoded = unsafe { nmp_app_podcast_decode_update_frame(bytes.as_ptr(), bytes.len()) };
    if decoded.is_null() {
        return;
    }
    // SAFETY: `decoded` is a heap-owned NUL-terminated C string produced by
    // `CString::into_raw` inside `nmp_app_podcast_decode_update_frame`, and we
    // now own it exactly once. Reclaiming it as a `CString` frees it on drop —
    // there is no separate free-string doorway anymore.
    let owned = unsafe { CString::from_raw(decoded) };
    let Ok(json) = owned.to_str().map(str::to_owned) else {
        return;
    };
    let Ok(value) = serde_json::from_str::<serde_json::Value>(&json) else {
        return;
    };
    let Some(map) = value
        .get("v")
        .and_then(|v| v.get("projections"))
        .and_then(|p| p.get("signed_events"))
        .and_then(|s| s.as_object())
    else {
        return;
    };
    let mut guard = captured().lock().unwrap_or_else(|e| e.into_inner());
    for (correlation_id, row) in map {
        let entry = if row.get("ok").and_then(|v| v.as_bool()) == Some(true) {
            row.get("signed_json")
                .and_then(|v| v.as_str())
                .map(|s| Ok(s.to_owned()))
        } else {
            Some(Err(row
                .get("error")
                .and_then(|v| v.as_str())
                .unwrap_or("(no error message)")
                .to_owned()))
        };
        if let Some(entry) = entry {
            guard.push((correlation_id.clone(), entry));
        }
    }
}

/// Install the signed-event capture callback. Call once after `app_new`,
/// BEFORE `nmp_app_start` (mirrors the production shell ordering).
pub fn install(app: *mut NmpApp) {
    // Eagerly initialise the buffer so the callback never races the OnceLock.
    let _ = captured();
    // SAFETY: `app` is non-null (checked at construction in
    // `harness::app_new`) and live for the remainder of the process.
    nmp_uniffi_support::set_update_sink(
        unsafe { &*app },
        Some(Box::new(())),
        |_sink: &(), frame: Vec<u8>| {
            capture_frame(&frame);
        },
    );
}

/// Drive a sign-and-return for `unsigned_json` signed by `signer_pubkey_hex`,
/// then poll the captured `signed_events` frames until the result for this
/// dispatch's correlation id appears (or `timeout` elapses).
///
/// Returns the flat signed Nostr event JSON (`{id,pubkey,created_at,kind,tags,
/// content,sig}`) on success, or `Err(message)` on a sign-failure verdict /
/// timeout / FFI error.
pub fn sign_for_return_blocking(
    app: *mut NmpApp,
    signer_pubkey_hex: &str,
    unsigned_json: &serde_json::Value,
    timeout: Duration,
) -> Result<serde_json::Value, String> {
    if app.is_null() {
        return Err("app pointer is null".to_string());
    }

    // The typed `sign_event_for_return` doorway is fire-and-forget (unlike the
    // old C-ABI, which minted and returned the correlation id) — the host
    // mints it up front, exactly like the byte-doorway dispatch path in
    // `dispatch_bytes.rs`.
    let correlation_id = nmp_app_podcast::dispatch_bytes::mint_correlation_id();
    // SAFETY: `app` is a live kernel pointer for the duration of this call.
    unsafe { &*app }.sign_event_for_return(
        signer_pubkey_hex.to_string(),
        unsigned_json.to_string(),
        correlation_id.clone(),
    );

    let deadline = Instant::now() + timeout;
    loop {
        // Scan captured rows for our id.
        {
            let guard = captured().lock().unwrap_or_else(|e| e.into_inner());
            if let Some((_, result)) = guard.iter().find(|(id, _)| id == &correlation_id) {
                return match result {
                    Ok(signed_json) => serde_json::from_str::<serde_json::Value>(signed_json)
                        .map_err(|e| format!("signed_json is not valid JSON: {e}")),
                    Err(msg) => Err(format!("kernel sign-for-return failed: {msg}")),
                };
            }
        }
        if Instant::now() >= deadline {
            return Err(format!(
                "timed out after {timeout:?} waiting for signed_events[{correlation_id}]"
            ));
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}

/// Assert the kernel signs a `kind` draft with `signer_pubkey_hex` (the
/// per-podcast key) — correct `pubkey` (NOT `active_pubkey_hex`), valid 128-hex
/// Schnorr `sig`, 64-hex `id`, matching `kind`.
///
/// `register_podcast_signer_in_kernel` must already have run for this pubkey
/// (the scenario's publish dispatches do that). If it had not, the named signer
/// is absent and the kernel returns an `Err` verdict → this returns `Err`. This
/// is the headline proof that per-podcast events are signed by the per-podcast
/// key, via the same `sign_with_account_nonblocking` resolution `PublishRaw`
/// uses.
pub fn assert_kernel_signs_with(
    app: *mut NmpApp,
    signer_pubkey_hex: &str,
    active_pubkey_hex: &str,
    kind: u32,
) -> Result<(), String> {
    // A minimal but kind-correct NIP-F4 draft. Exact tags are irrelevant to the
    // signer proof; `created_at` is advisory (the kernel re-stamps it, D7).
    let draft = serde_json::json!({
        "kind": kind,
        "content": "",
        "tags": [["d", format!("nipf4-signer-probe-{kind}")]],
        "created_at": 0,
    });

    let signed = sign_for_return_blocking(app, signer_pubkey_hex, &draft, Duration::from_secs(8))?;

    let pubkey = signed["pubkey"].as_str().unwrap_or("");
    if pubkey != signer_pubkey_hex {
        return Err(format!(
            "REGRESSION: kernel signed kind:{kind} with the WRONG pubkey. \
             expected per-podcast key {signer_pubkey_hex}, got {pubkey}"
        ));
    }
    if pubkey == active_pubkey_hex {
        return Err(format!(
            "REGRESSION: kernel signed kind:{kind} with the ACTIVE account \
             ({active_pubkey_hex}) instead of the per-podcast key — signer_pubkey \
             threading is broken"
        ));
    }
    match signed["sig"].as_str() {
        Some(sig) if sig.len() == 128 && sig.chars().all(|c| c.is_ascii_hexdigit()) => {}
        other => return Err(format!("kind:{kind} has no valid 128-hex sig: {other:?}")),
    }
    match signed["id"].as_str() {
        Some(id) if id.len() == 64 && id.chars().all(|c| c.is_ascii_hexdigit()) => {}
        other => return Err(format!("kind:{kind} has no valid 64-hex id: {other:?}")),
    }
    if signed["kind"].as_u64() != Some(kind as u64) {
        return Err(format!(
            "kind mismatch: requested {kind}, signed event has {}",
            signed["kind"]
        ));
    }
    Ok(())
}
