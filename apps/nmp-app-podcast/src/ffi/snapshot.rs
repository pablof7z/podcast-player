//! Snapshot + unregister entry points the host calls against a
//! [`PodcastHandle`] returned by [`super::register::nmp_app_podcast_register`].
//!
//! ## Snapshot contract
//!
//! The kernel already emits identity fields (`accounts`, `active_account`,
//! `bunker_handshake`) inside its own `projections` map on every tick. Swift
//! reads those fields from the full kernel snapshot via `nmp_app_set_update_callback`.
//!
//! `nmp_app_podcast_snapshot` is a secondary, on-demand read that the Podcast
//! host can call outside the kernel tick (e.g. on first launch to paint the
//! initial UI before the first tick fires). It returns the same identity
//! contract described by [`PodcastUpdate`].
//!
//! Podcast-domain fields (feed list, playback state, episode queue, etc.)
//! will be added in subsequent milestones as the corresponding projections
//! are implemented.

use std::ffi::{c_char, CString};

use serde::Serialize;

use super::handle::PodcastHandle;

// ---------------------------------------------------------------------------
// Snapshot types (Rust source of truth; Swift mirrors as `Decodable`)
// ---------------------------------------------------------------------------

/// NIP-01 kind:0 account summary — mirrors `nmp-core`'s internal
/// `AccountSummary` shape but owned by this crate so the Podcast snapshot can
/// serialize it independently of `nmp-core`'s `pub(crate)` restriction.
///
/// `nmp-core` populates this shape under the `accounts` / `active_account`
/// projection keys on every kernel tick. The Podcast crate re-declares the
/// shape for documentation fidelity and future `nmp_app_podcast_snapshot`
/// serialization.
#[derive(Clone, Debug, Default, Serialize)]
pub struct AccountSummary {
    /// Stable identity id (hex pubkey).
    pub id: String,
    /// Bech32 npub (`npub1…`).
    pub npub: String,
    /// Short npub for compact display (`npub1abc…xyz`).
    pub npub_short: String,
    /// Resolved display name (kind:0 `name` → fallback `npub_short`).
    pub display_name: String,
    /// Signer backend label (`"local"`, `"bunker"`, etc.).
    pub signer_kind: String,
    /// Human-readable signer status.
    pub signer_label: String,
    /// `true` when the signer is remote (NIP-46 bunker).
    pub signer_is_remote: bool,
    /// `true` for the currently-active account.
    pub is_active: bool,
    /// Profile picture URL, if resolved from a kind:0.
    pub picture_url: Option<String>,
    /// Fallback initials for the avatar placeholder.
    pub avatar_initials: String,
    /// Fallback hex color for the avatar placeholder.
    pub avatar_color_hex: String,
}

/// NIP-46 / onboarding state exposed in the snapshot.
///
/// Swift uses this to decide whether to show the onboarding flow or the main
/// app surface. All fields default to the "no account / onboarding needed"
/// state.
#[derive(Clone, Debug, Serialize)]
pub struct Nip46OnboardingState {
    /// `true` when no account is present (onboarding flow should be shown).
    pub is_signed_out: bool,
    /// `true` while a NIP-46 bunker handshake is in flight.
    pub bunker_in_progress: bool,
}

impl Default for Nip46OnboardingState {
    fn default() -> Self {
        Self {
            is_signed_out: true,
            bunker_in_progress: false,
        }
    }
}

/// Live NIP-46 bunker handshake state — mirrors `BunkerHandshakeDto`.
///
/// `nmp-core` populates this under the `bunker_handshake` projection key via
/// its built-in snapshot projection registered during actor init.
#[derive(Clone, Debug, Serialize)]
pub struct BunkerHandshakeState {
    /// Stage string: `"idle"` | `"connecting"` | `"awaiting_pubkey"` |
    /// `"ready"` | `"failed"`.
    pub stage: String,
    /// Optional human-readable status (e.g. relay URL, error reason).
    pub message: Option<String>,
    /// `true` when `stage == "idle"` (no handshake in flight).
    pub is_idle: bool,
    /// `true` while the handshake is actively making progress.
    pub is_in_flight: bool,
    /// `true` when the handshake ended in a failure.
    pub is_failed: bool,
    /// `true` when the handshake completed successfully.
    pub is_terminal_success: bool,
    /// `true` when the user can invoke `nmp_app_cancel_bunker_handshake`.
    pub can_cancel: bool,
    /// Localised stage label for the UI progress indicator.
    pub stage_label: String,
}

impl Default for BunkerHandshakeState {
    fn default() -> Self {
        Self {
            stage: "idle".to_string(),
            message: None,
            is_idle: true,
            is_in_flight: false,
            is_failed: false,
            is_terminal_success: false,
            can_cancel: false,
            stage_label: String::new(),
        }
    }
}

/// Top-level Podcast snapshot — the contract Swift's `PodcastUpdate: Decodable`
/// implements.
///
/// Identity fields are populated from the kernel's built-in projections
/// (`accounts`, `active_account`, `bunker_handshake`) that arrive via
/// `nmp_app_set_update_callback`. Podcast-domain fields (library, playback,
/// agent, etc.) will be added in M2–M13.
///
/// Swift MUST use `CodingKeys` to ignore unknown fields so schema additions in
/// future milestones do not break decoding of older builds (forward compat).
#[derive(Clone, Debug, Serialize)]
pub struct PodcastUpdate {
    /// `true` while the kernel actor is running normally.
    pub running: bool,
    /// Monotonically increasing tick counter.
    pub rev: u64,
    /// Increment on every incompatible schema change. Current: `1`.
    pub schema_version: u32,

    // -----------------------------------------------------------------------
    // Identity (M1.A)
    // -----------------------------------------------------------------------
    /// Currently-active account. `None` when no account is signed in.
    /// Drives onboarding flow visibility in Swift.
    pub active_account: Option<AccountSummary>,
    /// All registered accounts (may be empty on first launch).
    pub accounts: Vec<AccountSummary>,
    /// Derived onboarding / sign-in state — computed from `active_account`.
    pub nip46_onboarding: Nip46OnboardingState,
    /// Live NIP-46 bunker handshake progress. `stage == "idle"` when quiescent.
    pub bunker_handshake: BunkerHandshakeState,
    /// Toast message to surface, if any. `None` when no pending toast.
    /// Set by the actor's identity-error and publish-verdict arms (D6).
    pub toast: Option<String>,
}

impl Default for PodcastUpdate {
    fn default() -> Self {
        Self {
            running: true,
            rev: 0,
            schema_version: 1,
            active_account: None,
            accounts: vec![],
            nip46_onboarding: Nip46OnboardingState::default(),
            bunker_handshake: BunkerHandshakeState::default(),
            toast: None,
        }
    }
}

// ---------------------------------------------------------------------------
// FFI entry points
// ---------------------------------------------------------------------------

/// Serialize the current app state into a JSON C string.
///
/// Returns a stub `PodcastUpdate` (identity fields at their defaults — all
/// `None` / empty) until the Podcast crate wires a full Rust-side projection.
/// Swift should prefer the live stream from `nmp_app_set_update_callback` for
/// identity state; this entry point exists for on-demand reads outside the
/// tick (e.g. initial paint before the first tick fires).
///
/// Returns null on any failure (null handle, JSON encode error, CString nul
/// conflict). The returned pointer is owned by the caller; pass it to
/// [`nmp_app_podcast_snapshot_free`] when done.
#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_snapshot(handle: *mut PodcastHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    // SAFETY: caller guarantees `handle` is a valid pointer returned by
    // `nmp_app_podcast_register` and not yet freed.
    let _handle = unsafe { &*handle };

    // Return the default PodcastUpdate (running = true, identity at defaults).
    // Later milestones will extend this with real projection data read from the
    // kernel's snapshot state.
    let update = PodcastUpdate::default();
    let Ok(json) = serde_json::to_string(&update) else {
        return std::ptr::null_mut();
    };
    let Ok(cstr) = CString::new(json) else {
        return std::ptr::null_mut();
    };
    cstr.into_raw()
}

/// Free a snapshot string previously returned by [`nmp_app_podcast_snapshot`].
/// Null pointer is a silent no-op.
#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_snapshot_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    // SAFETY: caller guarantees `ptr` came from `CString::into_raw` in
    // `nmp_app_podcast_snapshot` and has not been freed.
    unsafe {
        let _ = CString::from_raw(ptr);
    }
}

/// Drop the handle and free associated resources.
/// Idempotent: null pointer is a silent no-op. The handle MUST NOT be used
/// after this call.
#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_unregister(handle: *mut PodcastHandle) {
    if handle.is_null() {
        return;
    }
    // SAFETY: caller guarantees `handle` came from `nmp_app_podcast_register`
    // and has not already been freed.
    let boxed = unsafe { Box::from_raw(handle) };
    // Future milestones will use `boxed.app` to call
    // `app_ref.unregister_event_observer(observer_id)` for each registered
    // projection. For now the handle carries the `app` pointer so subsequent
    // milestones can add unregister logic here without changing the FFI type.
    let _ = boxed.app;
    // boxed dropped here.
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_snapshot_serialises_identity_fields() {
        let update = PodcastUpdate::default();
        let json = serde_json::to_string(&update).expect("serialise");
        let v: serde_json::Value = serde_json::from_str(&json).expect("parse");
        assert_eq!(v["schema_version"], 1);
        assert_eq!(v["running"], true);
        assert!(v["active_account"].is_null());
        assert!(v["accounts"].is_array());
        assert_eq!(v["nip46_onboarding"]["is_signed_out"], true);
        assert_eq!(v["bunker_handshake"]["stage"], "idle");
        assert!(v["toast"].is_null());
    }

    #[test]
    fn bunker_handshake_state_idle_defaults() {
        let bh = BunkerHandshakeState::default();
        assert!(bh.is_idle);
        assert!(!bh.is_in_flight);
        assert!(!bh.is_failed);
        assert!(!bh.is_terminal_success);
    }

    #[test]
    fn nip46_onboarding_defaults_signed_out() {
        let state = Nip46OnboardingState::default();
        assert!(state.is_signed_out);
        assert!(!state.bunker_in_progress);
    }
}
