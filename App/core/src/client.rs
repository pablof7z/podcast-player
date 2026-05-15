//! Top-level UniFFI object. Swift holds one `PodcastrCore` for the life of
//! the app and routes every Nostr request through it.
//!
//! State discipline: async methods never hold the parking_lot guard across
//! an `.await` point.

use std::sync::Arc;

use nostr_sdk::prelude::Keys;
use parking_lot::RwLock;

use crate::errors::CoreError;
use crate::events::EventCallback;
use crate::nostr_runtime::{CallbackSlot, NostrRuntime};
use crate::session::Session;

#[derive(uniffi::Object)]
pub struct PodcastrCore {
    inner: Arc<RwLock<Inner>>,
    runtime: Arc<NostrRuntime>,
    callback_slot: CallbackSlot,
}

/// Ephemeral state for an in-flight NIP-46 `nostrconnect://` pairing.
/// Lives between `nip46_start_nostrconnect` and `nip46_await_signer`.
pub(crate) struct PendingNip46 {
    pub(crate) session_keys: Keys,
    pub(crate) secret: String,
    pub(crate) relay_url: String,
}

pub(crate) struct Inner {
    pub(crate) session: Session,
    pub(crate) pending_nip46: Option<PendingNip46>,
}

impl Inner {
    pub(crate) fn set_pending_nip46(&mut self, pending: PendingNip46) {
        self.pending_nip46 = Some(pending);
    }

    pub(crate) fn take_pending_nip46(&mut self) -> Option<PendingNip46> {
        self.pending_nip46.take()
    }
}

#[uniffi::export]
impl PodcastrCore {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        let callback_slot: CallbackSlot = Arc::new(RwLock::new(None));
        let runtime = Arc::new(
            NostrRuntime::new(callback_slot.clone())
                .expect("nostr runtime initialization must succeed"),
        );
        Arc::new(Self {
            inner: Arc::new(RwLock::new(Inner {
                session: Session::new(),
                pending_nip46: None,
            })),
            runtime,
            callback_slot,
        })
    }

    /// Wire up (or replace) the Swift-side delta sink. Pass `None` to clear.
    pub fn set_event_callback(&self, callback: Option<Arc<dyn EventCallback>>) {
        *self.callback_slot.write() = callback;
    }

    // -- Identity --

    pub fn login_nsec(&self, secret: String) -> Result<String, CoreError> {
        let pk = self.inner.write().session.login_nsec(&secret)?;
        if let Some(keys) = self.inner.read().session.keys().cloned() {
            self.runtime.set_signer(keys);
        }
        Ok(pk.to_hex())
    }

    pub fn login_pubkey(&self, npub_or_hex: String) -> Result<String, CoreError> {
        let pk = self.inner.write().session.login_pubkey(&npub_or_hex)?;
        Ok(pk.to_hex())
    }

    pub fn logout(&self) {
        self.inner.write().session.logout();
        self.runtime.unset_signer();
    }

    pub fn current_pubkey(&self) -> Option<String> {
        self.inner.read().session.pubkey().map(|p| p.to_hex())
    }

    // -- Hello world for FFI round-trip verification --

    pub fn ping(&self, message: String) -> String {
        format!("pong: {message}")
    }
}

impl PodcastrCore {
    pub fn runtime(&self) -> &Arc<NostrRuntime> {
        &self.runtime
    }

    pub(crate) fn inner(&self) -> &Arc<RwLock<Inner>> {
        &self.inner
    }

    pub(crate) fn callback_slot(&self) -> &CallbackSlot {
        &self.callback_slot
    }
}
