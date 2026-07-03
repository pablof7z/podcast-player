//! App-owned UniFFI facade over `nmp-native-runtime` (wave 1: generic runtime
//! lifecycle/session verbs only — mirrors `apps/nmp-gallery`'s validated
//! `nmp-app-gallery::facade` shape).
//!
//! This module coexists with the legacy `runtime_facade` C-ABI module during
//! the incremental migration (podcast-player#681 follow-on). [`PodcastApp`]
//! owns the single `NmpApp` instance by value; [`PodcastApp::native_handle`]
//! is a transitional escape hatch exposing the same pointer the C-ABI
//! `ffi::actions`/`ffi::snapshot`/... surface still expects, so those ~140
//! not-yet-migrated symbols keep working unmodified against the one runtime
//! instance. Each later wave shrinks what needs the escape hatch until it is
//! deleted.
//!
//! Swift call-site adoption is itself staged narrower than this module's
//! surface: wave 1 only switches `KernelBridge`'s construction/teardown
//! (`PodcastApp::new`/`native_handle`/`shutdown`) — the smallest change that
//! proves the whole chain (this facade, bindgen, the Xcode/Tuist module
//! wiring, and runtime behavior) end-to-end. The rest of this object's
//! methods (`start`, `stop`, `dispatch_action`, `resolve_ref`, ...) are
//! implemented, unit-tested, and bindgen-exported here, but their legacy
//! `nmp_app_*` C-ABI call sites in Swift are switched over individually in
//! later waves, each verified by its own build rather than swapped in bulk
//! without local build feedback.

use std::collections::HashMap;
use std::sync::Arc;

use nmp_core::{EventShape, ProfileShape, RefLiveness, RefNamespace, RefShape, SignerSource};
use nmp_native_runtime::NmpApp;
use zeroize::Zeroizing;

#[uniffi::export(callback_interface)]
pub trait PodcastUpdateSink: Send + Sync {
    fn on_update(&self, frame: Vec<u8>);
}

#[uniffi::export(callback_interface)]
pub trait PodcastCapabilitySink: Send + Sync {
    fn on_capability_request(&self, request_json: String) -> String;
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct PodcastDispatchOutcome {
    pub correlation_id: Option<String>,
    pub error: Option<String>,
    pub code: Option<String>,
}

impl From<nmp_uniffi_support::DispatchOutcome> for PodcastDispatchOutcome {
    fn from(out: nmp_uniffi_support::DispatchOutcome) -> Self {
        Self {
            correlation_id: out.correlation_id,
            error: out.error,
            code: out.code,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum PodcastRefNamespace {
    Profile,
    Event,
}

impl From<PodcastRefNamespace> for RefNamespace {
    fn from(value: PodcastRefNamespace) -> Self {
        match value {
            PodcastRefNamespace::Profile => RefNamespace::Profile,
            PodcastRefNamespace::Event => RefNamespace::Event,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum PodcastProfileShape {
    Ref,
    Card,
}

#[derive(uniffi::Enum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum PodcastEventShape {
    Embed,
    Raw,
}

#[derive(uniffi::Enum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum PodcastRefShape {
    Profile { shape: PodcastProfileShape },
    Event { shape: PodcastEventShape },
}

impl From<PodcastRefShape> for RefShape {
    fn from(value: PodcastRefShape) -> Self {
        match value {
            PodcastRefShape::Profile { shape: PodcastProfileShape::Ref } => {
                RefShape::Profile(ProfileShape::Ref)
            }
            PodcastRefShape::Profile { shape: PodcastProfileShape::Card } => {
                RefShape::Profile(ProfileShape::Card)
            }
            PodcastRefShape::Event { shape: PodcastEventShape::Embed } => {
                RefShape::Event(EventShape::Embed)
            }
            PodcastRefShape::Event { shape: PodcastEventShape::Raw } => {
                RefShape::Event(EventShape::Raw)
            }
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum PodcastRefLiveness {
    CacheOk,
    Live,
}

impl From<PodcastRefLiveness> for RefLiveness {
    fn from(value: PodcastRefLiveness) -> Self {
        match value {
            PodcastRefLiveness::CacheOk => RefLiveness::CacheOk,
            PodcastRefLiveness::Live => RefLiveness::Live,
        }
    }
}

/// The app-owned UniFFI object. Owns the single `NmpApp` instance by value —
/// see the module doc for the `native_handle` transitional escape hatch.
#[derive(uniffi::Object)]
pub struct PodcastApp {
    inner: NmpApp,
}

#[uniffi::export]
impl PodcastApp {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            inner: nmp_native_runtime::new_app(),
        })
    }

    /// Transitional escape hatch (wave 1 only): the raw `*mut NmpApp` address
    /// this facade owns, for the still-C-ABI `nmp_app_podcast_*` surface.
    /// Valid only while this `PodcastApp` (and thus its Swift/Kotlin
    /// reference) is alive. Deleted once every C-ABI symbol has migrated.
    pub fn native_handle(&self) -> u64 {
        std::ptr::addr_of!(self.inner) as u64
    }

    pub fn start(&self, visible_limit: u32, emit_hz: u32) {
        nmp_uniffi_support::start_runtime(&self.inner, visible_limit, emit_hz);
    }

    pub fn configure(&self, visible_limit: u32, emit_hz: u32) {
        nmp_uniffi_support::configure_runtime(&self.inner, visible_limit, emit_hz);
    }

    pub fn stop(&self) {
        self.inner.stop_runtime();
    }

    pub fn reset(&self) {
        self.inner.reset_runtime();
    }

    pub fn shutdown(&self) {
        self.inner.shutdown();
    }

    pub fn consume_all_builtin_projections(&self) {
        self.inner.consume_all_builtin_projections();
    }

    pub fn set_storage_path(&self, path: Option<String>) {
        let _ = self.inner.set_storage_path(path);
    }

    pub fn is_alive(&self) -> bool {
        self.inner.is_alive()
    }

    pub fn lifecycle_foreground(&self) {
        self.inner.lifecycle_foreground();
    }

    pub fn lifecycle_background(&self) {
        self.inner.lifecycle_background();
    }

    pub fn set_update_sink(&self, sink: Option<Box<dyn PodcastUpdateSink>>) {
        nmp_uniffi_support::set_update_sink(&self.inner, sink, |sink, frame| {
            sink.on_update(frame);
        });
    }

    pub fn set_capability_callback(&self, sink: Option<Box<dyn PodcastCapabilitySink>>) {
        nmp_uniffi_support::set_capability_callback(&self.inner, sink, |sink, request_json| {
            sink.on_capability_request(request_json)
        });
    }

    pub fn dispatch_capability_json(&self, request_json: String) -> String {
        nmp_uniffi_support::dispatch_capability_json(&self.inner, &request_json)
    }

    pub fn dispatch_action(&self, envelope: Vec<u8>) -> PodcastDispatchOutcome {
        nmp_uniffi_support::dispatch_action_vec(&self.inner, envelope).into()
    }

    pub fn signin_nsec(&self, secret: String, make_active: bool) {
        let secret = Zeroizing::new(secret);
        self.inner
            .add_signer(SignerSource::LocalNsec(secret), make_active);
    }

    pub fn signin_bunker(&self, uri: String, make_active: bool) {
        self.inner.add_signer(SignerSource::BunkerUri(uri), make_active);
    }

    pub fn signer_broker_init(&self) {
        let _ = self.inner.init_signer_broker();
    }

    pub fn cancel_bunker_handshake(&self) {
        self.inner.cancel_bunker_handshake();
    }

    pub fn nostrconnect_uri(&self, callback_scheme: Option<String>) -> Option<String> {
        let scheme = callback_scheme
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty());
        self.inner.nostrconnect_uri(scheme)
    }

    pub fn remove_account(&self, identity_id: String) {
        self.inner.remove_account(identity_id);
    }

    /// `profile_json`/`relays_json` keep the same wire shape the legacy
    /// C-ABI symbol used (`HashMap<String, String>` / `Vec<(String,
    /// String)>` JSON) rather than a UniFFI record — this is a 1:1 behavior
    /// port, not a redesign; the JSON shape is owned by the Swift call site
    /// today and changing it is out of scope for wave 1.
    pub fn create_new_account(
        &self,
        profile_json: String,
        relays_json: String,
        mls: bool,
        make_active: bool,
    ) {
        let Ok(profile) = serde_json::from_str::<HashMap<String, String>>(&profile_json) else {
            self.inner.show_toast("Failed to decode profile JSON".to_string());
            return;
        };
        let Ok(relays) = serde_json::from_str::<Vec<(String, String)>>(&relays_json) else {
            self.inner.show_toast("Failed to decode relays JSON".to_string());
            return;
        };
        self.inner
            .create_account(profile, relays, Vec::new(), mls, make_active);
    }

    pub fn sign_event_for_return(
        &self,
        account_pubkey_hex: String,
        unsigned_json: String,
    ) -> String {
        let correlation_id = mint_correlation_id();
        self.inner.sign_event_for_return(
            account_pubkey_hex,
            unsigned_json,
            correlation_id.clone(),
        );
        correlation_id
    }

    pub fn resolve_ref(
        &self,
        namespace: PodcastRefNamespace,
        key: String,
        consumer_id: String,
        shape: PodcastRefShape,
        liveness: PodcastRefLiveness,
    ) {
        self.inner.resolve_ref(
            namespace.into(),
            key,
            consumer_id,
            shape.into(),
            liveness.into(),
        );
    }

    pub fn release_ref(&self, namespace: PodcastRefNamespace, key: String, consumer_id: String) {
        self.inner.release_ref(namespace.into(), key, consumer_id);
    }
}

fn mint_correlation_id() -> String {
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let now_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    let seq = COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("{now_ms:016x}{seq:016x}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn constructor_and_native_handle_round_trip_to_legacy_c_abi() {
        let app = PodcastApp::new();
        let handle = app.native_handle();
        assert_ne!(handle, 0);

        // The escape hatch must produce a pointer the legacy `*mut NmpApp`
        // C-ABI surface can dereference identically to `nmp_app_new()`'s
        // return value.
        let raw = handle as *mut NmpApp;
        let via_escape_hatch = unsafe { &*raw };
        assert!(!via_escape_hatch.is_alive());
    }

    #[test]
    fn lifecycle_start_stop_shutdown_do_not_panic() {
        let app = PodcastApp::new();
        app.start(64, 4);
        app.configure(64, 4);
        app.stop();
        app.reset();
        app.shutdown();
    }

    #[test]
    fn dispatch_empty_envelope_returns_error_outcome() {
        let app = PodcastApp::new();
        let out = app.dispatch_action(Vec::new());
        assert!(out.correlation_id.is_none());
        assert!(out.error.is_some());
    }
}
