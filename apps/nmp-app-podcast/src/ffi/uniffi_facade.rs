//! App-owned UniFFI facade over `nmp-native-runtime`.
//!
//! [`PodcastApp`] owns the single `NmpApp` instance by value and the
//! app-domain [`PodcastHandle`]. Generic NMP runtime lifecycle, identity,
//! callback, intent, and ref APIs are consumed through this object; app-domain
//! C ABI calls are being folded into it from the lifetime spine outward.

use std::collections::HashMap;
use std::ffi::CString;
use std::sync::{Arc, OnceLock};

use nmp_core::{EventShape, ProfileShape, RefLiveness, RefNamespace, RefShape, SignerSource};
use nmp_native_runtime::NmpApp;
use zeroize::Zeroizing;

use super::audio_report::audio_report_response_json;
use super::dispatch_action::dispatch_action_json;
use super::elevenlabs_voice_catalog::elevenlabs_voice_catalog_json;
use super::handle::PodcastHandle;
use super::http_report::apply_http_report_json;
use super::local_model_catalog::local_model_catalog_json;
use super::provider_model_catalog::provider_model_catalog_json;
use super::runtime_facade::{
    classify_input_intent_json, decode_nip21_uri_json, dispatch_input_intent_json,
};
use super::snapshot::{build_snapshot_payload, decode_update_frame_json, PodcastUpdate};
use super::speech_model_catalog::speech_model_catalog_json;
use crate::llm::local_model_backend::{set_registration, LocalLlmSink};

#[uniffi::export(callback_interface)]
pub trait PodcastUpdateSink: Send + Sync {
    fn on_update(&self, frame: Vec<u8>);
}

#[uniffi::export(callback_interface)]
pub trait PodcastCapabilitySink: Send + Sync {
    fn on_capability_request(&self, request_json: String) -> String;
}

#[uniffi::export(callback_interface)]
pub trait PodcastAgentAskSink: Send + Sync {
    fn on_agent_ask_event(&self, event_json: String);
}

#[uniffi::export(callback_interface)]
pub trait PodcastLocalLlmSink: Send + Sync {
    fn infer(&self, prompt_json: String) -> String;
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
            PodcastRefShape::Profile {
                shape: PodcastProfileShape::Ref,
            } => RefShape::Profile(ProfileShape::Ref),
            PodcastRefShape::Profile {
                shape: PodcastProfileShape::Card,
            } => RefShape::Profile(ProfileShape::Card),
            PodcastRefShape::Event {
                shape: PodcastEventShape::Embed,
            } => RefShape::Event(EventShape::Embed),
            PodcastRefShape::Event {
                shape: PodcastEventShape::Raw,
            } => RefShape::Event(EventShape::Raw),
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

/// The app-owned UniFFI object. Owns the single `NmpApp` instance and the
/// app-domain `PodcastHandle`.
#[derive(uniffi::Object)]
pub struct PodcastApp {
    inner: NmpApp,
    podcast: OnceLock<Arc<PodcastHandle>>,
}

#[uniffi::export]
impl PodcastApp {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        let mut app = Arc::new(Self {
            inner: nmp_native_runtime::new_app(),
            podcast: OnceLock::new(),
        });
        let app_mut = Arc::get_mut(&mut app).expect("PodcastApp has no shared refs during init");
        let raw = std::ptr::addr_of_mut!(app_mut.inner);
        let handle = super::register::register_podcast_app(raw);
        if !handle.is_null() {
            // SAFETY: `register_podcast_app` returns `Arc::into_raw`.
            // Reclaim that strong ref into the owning UniFFI object; projection
            // closures hold their own Arc clones.
            let podcast = unsafe { Arc::from_raw(handle as *const PodcastHandle) };
            let _ = app_mut.podcast.set(podcast);
        }
        app
    }

    /// Transitional handle token for UniFFI methods whose Rust bodies still
    /// delegate through handle-scoped JSON helpers.
    /// This returns the `PodcastHandle` pointer owned by this `PodcastApp`;
    /// Swift must not free it.
    pub fn podcast_handle(&self) -> u64 {
        self.podcast_handle_ptr().map_or(0, |ptr| ptr as u64)
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
        if let Some(handle) = self.podcast.get() {
            handle.shutdown_sidecars();
        }
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

    pub fn set_podcast_data_dir(&self, path: String) {
        let Some(handle) = self.podcast_handle_ptr() else {
            return;
        };
        let Ok(path) = CString::new(path) else {
            return;
        };
        super::data_dir::nmp_app_podcast_set_data_dir(handle, path.as_ptr());
    }

    pub fn podcast_snapshot_rev(&self) -> u64 {
        self.podcast
            .get()
            .map(|handle| {
                handle
                    .state
                    .infra
                    .rev
                    .load(std::sync::atomic::Ordering::Relaxed)
            })
            .unwrap_or(0)
    }

    pub fn podcast_snapshot(&self) -> Option<String> {
        self.podcast
            .get()
            .map(|handle| build_snapshot_payload(handle))
    }

    pub fn decode_update_frame(&self, frame: Vec<u8>) -> Option<String> {
        decode_update_frame_json(&frame)
    }

    pub fn dispatch_podcast_action(
        &self,
        namespace: String,
        action_json: String,
    ) -> Option<String> {
        self.podcast
            .get()
            .map(|handle| dispatch_action_json(handle, &namespace, &action_json))
    }

    pub fn set_local_llm_sink(&self, sink: Option<Box<dyn PodcastLocalLlmSink>>) {
        let sink = sink.map(|sink| Arc::new(LocalLlmSinkAdapter { sink }) as Arc<dyn LocalLlmSink>);
        set_registration(sink);
    }

    pub fn classify_input_intent(&self, request_json: String) -> String {
        classify_input_intent_json(&self.inner, &request_json)
    }

    pub fn dispatch_input_intent(
        &self,
        request_json: String,
        session_id: Option<String>,
    ) -> String {
        dispatch_input_intent_json(&self.inner, &request_json, session_id.as_deref())
    }

    pub fn decode_nip21_uri(&self, input: String) -> String {
        decode_nip21_uri_json(&input)
    }

    pub fn signin_nsec(&self, secret: String, make_active: bool) {
        let secret = Zeroizing::new(secret);
        self.inner
            .add_signer(SignerSource::LocalNsec(secret), make_active);
    }

    pub fn signin_bunker(&self, uri: String, make_active: bool) {
        self.inner
            .add_signer(SignerSource::BunkerUri(uri), make_active);
    }

    pub fn signer_broker_init(&self) {
        let _ = self.inner.init_signer_broker();
    }

    pub fn cancel_bunker_handshake(&self) {
        self.inner.cancel_bunker_handshake();
    }

    pub fn signin_nip55(&self, signer_package: Option<String>) {
        self.inner.signin_nip55(signer_package);
    }

    pub fn deliver_external_signer_response(&self, response_json: String) {
        self.inner.deliver_external_signer_response(&response_json);
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
            self.inner
                .show_toast("Failed to decode profile JSON".to_string());
            return;
        };
        let Ok(relays) = serde_json::from_str::<Vec<(String, String)>>(&relays_json) else {
            self.inner
                .show_toast("Failed to decode relays JSON".to_string());
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
        self.inner
            .sign_event_for_return(account_pubkey_hex, unsigned_json, correlation_id.clone());
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

impl PodcastApp {
    pub(crate) fn podcast_handle_for_uniffi(&self) -> Option<&PodcastHandle> {
        self.podcast.get().map(Arc::as_ref)
    }

    fn podcast_handle_ptr(&self) -> Option<*mut PodcastHandle> {
        self.podcast
            .get()
            .map(|handle| Arc::as_ptr(handle) as *mut PodcastHandle)
    }

    /// Rust-in-process consumers such as the TUI can read the typed app update
    /// without going through the legacy C snapshot string.
    pub fn podcast_update_for_rust(&self) -> Option<PodcastUpdate> {
        self.podcast.get().map(|handle| handle.update())
    }

    pub fn audio_report_for_rust(&self, report_json: &str) -> Option<String> {
        self.podcast
            .get()
            .and_then(|handle| audio_report_response_json(handle, report_json))
    }

    pub fn http_report_for_rust(&self, report_json: &str) {
        if let Some(handle) = self.podcast.get() {
            apply_http_report_json(handle, report_json);
        }
    }

    pub fn provider_model_catalog_for_rust(&self) -> Option<String> {
        self.podcast
            .get()
            .map(|handle| provider_model_catalog_json(handle))
    }

    pub fn elevenlabs_voice_catalog_for_rust(&self) -> Option<String> {
        self.podcast
            .get()
            .map(|handle| elevenlabs_voice_catalog_json(handle))
    }

    pub fn speech_model_catalog_for_rust(&self) -> Option<String> {
        self.podcast.get().map(|_| speech_model_catalog_json())
    }

    pub fn local_model_catalog_for_rust(&self) -> Option<String> {
        self.podcast.get().map(|_| local_model_catalog_json())
    }

    #[cfg(feature = "headless")]
    pub fn headless_handle_for_rust(&self) -> Option<&PodcastHandle> {
        self.podcast.get().map(Arc::as_ref)
    }
}

impl Drop for PodcastApp {
    fn drop(&mut self) {
        if let Some(handle) = self.podcast.get() {
            handle.shutdown_sidecars();
        }
    }
}

struct LocalLlmSinkAdapter {
    sink: Box<dyn PodcastLocalLlmSink>,
}

impl LocalLlmSink for LocalLlmSinkAdapter {
    fn infer_local_llm(&self, prompt_json: String) -> String {
        self.sink.infer(prompt_json)
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
