//! NIP-46 nostrconnect signer — port of
//! `App/Sources/Services/UserIdentityStore+NIP46.swift` + `RemoteSigner`.
//!
//! Flow:
//! 1. `nip46_start_nostrconnect` — generate ephemeral session keys + secret,
//!    build `nostrconnect://…` URI, stash `PendingNip46` on `Inner`, return URI.
//! 2. `nip46_await_signer` — subscribe, decrypt inbound kind:24133, match
//!    `Response.result` against our secret, run `get_public_key`, install
//!    the signer, fire `SignerConnected`.
//! 3. `nip46_disconnect` — unset signer, fire `SignerDisconnected`.
//!
//! Modeled on highlighter's `BunkerSigner` (same nostr-sdk 0.44), trimmed
//! to what we need (no `bunker://` paste, no `auth_url`, no NIP-04). We use
//! `nostr`'s `nip46::*` primitives directly — the `nostr-connect` companion
//! crate is intentionally not pulled in.

use std::sync::Arc;
use std::time::Duration;

use nostr_sdk::prelude::*;
use tokio::sync::OnceCell;

use crate::client::{PendingNip46, PodcastrCore};
use crate::errors::CoreError;
use crate::events::{DataChangeType, Delta};
use crate::nip46_uri::{build_nostr_connect_uri, random_secret};
use crate::relays::NOSTR_CONNECT_RELAY;

/// How long we wait for a NIP-46 RPC turnaround (signing, get_public_key).
const REQUEST_TIMEOUT: Duration = Duration::from_secs(60);

/// A NIP-46 remote signer paired over a single relay. Cheap to clone (state
/// is Arc-backed); implements `NostrSigner` so it installs on the shared
/// `nostr_sdk::Client`. The inbound subscription opened during pairing stays
/// alive — every subsequent `sign_event` response arrives on it.
#[derive(Debug, Clone)]
pub struct BunkerSigner {
    client: Client,
    local_keys: Keys,
    remote_signer_pubkey: PublicKey,
    /// User pubkey from `get_public_key`; cached after the first call.
    user_pubkey: Arc<OnceCell<PublicKey>>,
}

impl BunkerSigner {
    /// Listen on `relay` for an incoming remote-signer pairing response aimed
    /// at `local_keys`'s pubkey. Per the nostrconnect:// flow, the signer's
    /// first message is a `Response { result: <our_secret> }` — that's the
    /// implicit `connect` ack. On match we resolve the user pubkey via
    /// `get_public_key` over the same subscription.
    ///
    /// `timeout` bounds the inbound wait. Default in production is 5 minutes.
    pub async fn await_inbound(
        client: Client,
        local_keys: Keys,
        expected_secret: String,
        timeout: Duration,
    ) -> Result<(Self, PublicKey), CoreError> {
        let mut notifications = client.notifications();

        // `.since(now)` not `.limit(0)` — if iOS suspends us between displaying
        // the URI and the user approving in the signer, we still want the
        // relay to replay the connect response on reconnect.
        let filter = Filter::new()
            .kind(Kind::NostrConnect)
            .pubkey(local_keys.public_key())
            .since(Timestamp::now());

        let sub_id = SubscriptionId::generate();
        client
            .subscribe_with_id(sub_id.clone(), filter, None)
            .await
            .map_err(|e| CoreError::Relay(format!("subscribe nostrconnect: {e}")))?;

        let deadline = tokio::time::Instant::now() + timeout;

        loop {
            let remaining = deadline
                .checked_duration_since(tokio::time::Instant::now())
                .ok_or_else(|| CoreError::Signer("nostrconnect pairing timed out".into()))?;

            let notif = tokio::time::timeout(remaining, notifications.recv())
                .await
                .map_err(|_| CoreError::Signer("nostrconnect pairing timed out".into()))?
                .map_err(|e| CoreError::Signer(format!("notification channel: {e}")))?;

            let RelayPoolNotification::Event { event, .. } = notif else {
                continue;
            };
            if event.kind != Kind::NostrConnect {
                continue;
            }

            let decrypted = match nip44::decrypt(
                local_keys.secret_key(),
                &event.pubkey,
                event.content.as_str(),
            ) {
                Ok(v) => v,
                Err(_) => continue,
            };
            let Ok(msg) = NostrConnectMessage::from_json(&decrypted) else {
                continue;
            };

            // Per NIP-46 nostrconnect:// flow, the signer replies with a
            // Response whose `result` echoes the secret from the URI (or
            // "ack"). We do NOT receive a `connect` Request here — that's
            // the bunker:// flow. Matches highlighter's nostrconnect port and
            // observed behavior of Primal / nsec.app / Amber.
            let NostrConnectMessage::Response { result, error, .. } = msg else {
                continue;
            };

            if let Some(err) = error {
                return Err(CoreError::Signer(format!(
                    "signer rejected pairing: {err}"
                )));
            }

            let result_str = result.unwrap_or_default();
            let matches = result_str == expected_secret || result_str == "ack";
            if !matches {
                return Err(CoreError::Signer(format!(
                    "remote signer presented wrong secret: result={result_str}"
                )));
            }

            let signer = Self {
                client: client.clone(),
                local_keys: local_keys.clone(),
                remote_signer_pubkey: event.pubkey,
                user_pubkey: Arc::new(OnceCell::new()),
            };
            let user = signer.rpc_get_public_key().await?;
            let _ = signer.user_pubkey.set(user);

            // Keep the inbound subscription open — it's the same sub all
            // future sign_event responses arrive on.
            return Ok((signer, user));
        }
    }

    /// Cached user pubkey resolved at pair-time.
    pub fn user_pubkey(&self) -> Option<PublicKey> {
        self.user_pubkey.get().copied()
    }

    async fn rpc_get_public_key(&self) -> Result<PublicKey, CoreError> {
        let res = self.send_request(NostrConnectRequest::GetPublicKey).await?;
        res.to_get_public_key()
            .map_err(|e| CoreError::Signer(format!("get_public_key failed: {e}")))
    }

    async fn send_request(
        &self,
        req: NostrConnectRequest,
    ) -> Result<ResponseResult, CoreError> {
        let msg = NostrConnectMessage::request(&req);
        let req_id = msg.id().to_string();
        let method = req.method();

        let event = EventBuilder::nostr_connect(
            &self.local_keys,
            self.remote_signer_pubkey,
            msg,
        )
        .map_err(|e| CoreError::Signer(format!("build nip46 event: {e}")))?
        .sign_with_keys(&self.local_keys)
        .map_err(|e| CoreError::Signer(format!("sign nip46 event: {e}")))?;

        let mut notifications = self.client.notifications();

        self.client
            .send_event(&event)
            .await
            .map_err(|e| CoreError::Relay(format!("send nip46 request: {e}")))?;

        let deadline = tokio::time::Instant::now() + REQUEST_TIMEOUT;
        loop {
            let remaining = deadline
                .checked_duration_since(tokio::time::Instant::now())
                .ok_or_else(|| CoreError::Signer("nip46 request timed out".into()))?;
            let notif = tokio::time::timeout(remaining, notifications.recv())
                .await
                .map_err(|_| CoreError::Signer("nip46 request timed out".into()))?
                .map_err(|e| CoreError::Signer(format!("notification: {e}")))?;

            let RelayPoolNotification::Event { event, .. } = notif else {
                continue;
            };
            if event.kind != Kind::NostrConnect || event.pubkey != self.remote_signer_pubkey {
                continue;
            }

            let Ok(plaintext) = nip44::decrypt(
                self.local_keys.secret_key(),
                &event.pubkey,
                event.content.as_str(),
            ) else {
                continue;
            };
            let Ok(msg) = NostrConnectMessage::from_json(&plaintext) else {
                continue;
            };

            if msg.id() != req_id || !msg.is_response() {
                continue;
            }

            let response = msg
                .to_response(method)
                .map_err(|e| CoreError::Signer(format!("parse nip46 response: {e}")))?;
            if let Some(err) = response.error {
                return Err(CoreError::Signer(err));
            }
            return response
                .result
                .ok_or_else(|| CoreError::Signer("empty nip46 response".into()));
        }
    }

    async fn sign_unsigned(&self, unsigned: UnsignedEvent) -> Result<Event, CoreError> {
        let res = self
            .send_request(NostrConnectRequest::SignEvent(unsigned))
            .await?;
        res.to_sign_event()
            .map_err(|e| CoreError::Signer(format!("sign_event: {e}")))
    }

    async fn nip44_encrypt_req(
        &self,
        peer: PublicKey,
        text: String,
    ) -> Result<String, CoreError> {
        let res = self
            .send_request(NostrConnectRequest::Nip44Encrypt {
                public_key: peer,
                text,
            })
            .await?;
        res.to_nip44_encrypt()
            .map_err(|e| CoreError::Signer(format!("nip44_encrypt: {e}")))
    }

    async fn nip44_decrypt_req(
        &self,
        peer: PublicKey,
        ciphertext: String,
    ) -> Result<String, CoreError> {
        let res = self
            .send_request(NostrConnectRequest::Nip44Decrypt {
                public_key: peer,
                ciphertext,
            })
            .await?;
        res.to_nip44_decrypt()
            .map_err(|e| CoreError::Signer(format!("nip44_decrypt: {e}")))
    }
}

impl NostrSigner for BunkerSigner {
    fn backend(&self) -> SignerBackend<'_> {
        SignerBackend::NostrConnect
    }

    fn get_public_key(&self) -> BoxedFuture<'_, Result<PublicKey, SignerError>> {
        Box::pin(async move {
            if let Some(pk) = self.user_pubkey.get().copied() {
                return Ok(pk);
            }
            self.rpc_get_public_key()
                .await
                .map_err(SignerError::backend)
        })
    }

    fn sign_event(&self, unsigned: UnsignedEvent) -> BoxedFuture<'_, Result<Event, SignerError>> {
        Box::pin(async move {
            self.sign_unsigned(unsigned)
                .await
                .map_err(SignerError::backend)
        })
    }

    fn nip04_encrypt<'a>(
        &'a self,
        _public_key: &'a PublicKey,
        _content: &'a str,
    ) -> BoxedFuture<'a, Result<String, SignerError>> {
        Box::pin(async move {
            Err(SignerError::backend(CoreError::Signer(
                "nip04 not supported by this NIP-46 client".to_string(),
            )))
        })
    }

    fn nip04_decrypt<'a>(
        &'a self,
        _public_key: &'a PublicKey,
        _content: &'a str,
    ) -> BoxedFuture<'a, Result<String, SignerError>> {
        Box::pin(async move {
            Err(SignerError::backend(CoreError::Signer(
                "nip04 not supported by this NIP-46 client".to_string(),
            )))
        })
    }

    fn nip44_encrypt<'a>(
        &'a self,
        public_key: &'a PublicKey,
        content: &'a str,
    ) -> BoxedFuture<'a, Result<String, SignerError>> {
        Box::pin(async move {
            self.nip44_encrypt_req(*public_key, content.to_string())
                .await
                .map_err(SignerError::backend)
        })
    }

    fn nip44_decrypt<'a>(
        &'a self,
        public_key: &'a PublicKey,
        content: &'a str,
    ) -> BoxedFuture<'a, Result<String, SignerError>> {
        Box::pin(async move {
            self.nip44_decrypt_req(*public_key, content.to_string())
                .await
                .map_err(SignerError::backend)
        })
    }
}

// -- UniFFI exports --

#[uniffi::export(async_runtime = "tokio")]
impl PodcastrCore {
    /// Begin a nostrconnect:// pairing. Generates an ephemeral session keypair
    /// and secret, stores them as pending state, and returns the URI string
    /// the caller renders as a QR / opens in a signer app. The handshake does
    /// not start until `nip46_await_signer` is called.
    ///
    /// `relay_url` may be empty / "default" — we fall back to
    /// `NOSTR_CONNECT_RELAY` (relay.nsec.app) in that case.
    pub async fn nip46_start_nostrconnect(
        &self,
        relay_url: String,
        app_name: String,
        app_url: Option<String>,
        app_image: Option<String>,
    ) -> Result<String, CoreError> {
        let relay = if relay_url.trim().is_empty() {
            NOSTR_CONNECT_RELAY.to_string()
        } else {
            relay_url
        };

        let session_keys = Keys::generate();
        let secret = random_secret();

        let mut metadata = NostrConnectMetadata::new(app_name);
        if let Some(u) = app_url.as_deref().filter(|s| !s.is_empty()) {
            if let Ok(parsed) = Url::parse(u) {
                metadata = metadata.url(parsed);
            }
        }
        if let Some(img) = app_image.as_deref().filter(|s| !s.is_empty()) {
            if let Ok(parsed) = Url::parse(img) {
                metadata = metadata.icons(vec![parsed]);
            }
        }

        let uri = build_nostr_connect_uri(
            session_keys.public_key(),
            &relay,
            &metadata,
            &secret,
        )?;

        // Make sure the NIP-46 relay is part of the pool *before*
        // `nip46_await_signer` opens its subscription. `add_relay` is a no-op
        // if the relay is already in the pool.
        let client = self.runtime().client().clone();
        if let Err(e) = client.add_relay(&relay).await {
            tracing::warn!(relay = %relay, error = %e, "add_relay nip46");
        }
        client.connect().await;

        self.inner().write().set_pending_nip46(PendingNip46 {
            session_keys,
            secret,
            relay_url: relay,
        });

        Ok(uri)
    }

    /// Wait up to `timeout_secs` for the remote signer to respond to the URI
    /// returned by `nip46_start_nostrconnect`. On success: installs the signer
    /// on the shared client, updates `Session` with the remote pubkey, fires
    /// a `SignerConnected { pubkey }` delta, and returns the hex pubkey.
    /// On timeout/error: fires `SignerDisconnected { reason }` and returns
    /// `CoreError::Signer(...)`.
    pub async fn nip46_await_signer(&self, timeout_secs: u64) -> Result<String, CoreError> {
        let pending = self
            .inner()
            .write()
            .take_pending_nip46()
            .ok_or_else(|| {
                CoreError::Signer(
                    "nip46_await_signer called without a pending nostrconnect session".into(),
                )
            })?;

        let timeout = Duration::from_secs(timeout_secs.max(1));
        let client = self.runtime().client().clone();

        let pair_result = BunkerSigner::await_inbound(
            client.clone(),
            pending.session_keys,
            pending.secret,
            timeout,
        )
        .await;

        let (signer, user_pubkey) = match pair_result {
            Ok(v) => v,
            Err(e) => {
                let reason = e.to_string();
                self.fire_delta(DataChangeType::SignerDisconnected { reason });
                return Err(e);
            }
        };

        // Install the signer on the shared client. We're inside a uniffi
        // async export running on uniffi's tokio runtime; calling
        // `client.set_signer(...).await` directly avoids the `block_on` in
        // `NostrRuntime::set_signer`, which would panic if we accidentally
        // tried it from inside the same runtime as the pool's pump.
        client.set_signer(signer).await;

        // Update session state (pubkey only — keys remain None for remote
        // signing). `login_pubkey` accepts hex.
        let pubkey_hex = user_pubkey.to_hex();
        let pk_for_session = pubkey_hex.clone();
        if let Err(e) = self.inner().write().session.login_pubkey(&pk_for_session) {
            tracing::warn!(error = %e, "session.login_pubkey after nip46 pair");
        }

        self.fire_delta(DataChangeType::SignerConnected {
            pubkey: pubkey_hex.clone(),
        });

        // Relay base url is logged for debugging; not currently persisted.
        tracing::info!(relay = %pending.relay_url, "nip46 pairing complete");

        Ok(pubkey_hex)
    }

    /// Tear down the active NIP-46 signer. Clears any pending pairing state,
    /// unsets the signer on the client, and fires `SignerDisconnected`.
    pub async fn nip46_disconnect(&self) {
        let _ = self.inner().write().take_pending_nip46();
        // Match the (sync) `logout` path: clear local pubkey state too so the
        // Swift side observes a consistent "not authenticated" view. Callers
        // that want to keep a read-only pubkey after disconnecting the remote
        // signer can re-call `login_pubkey` afterward.
        self.inner().write().session.logout();
        self.runtime().client().unset_signer().await;
        self.fire_delta(DataChangeType::SignerDisconnected {
            reason: "disconnected by user".into(),
        });
    }
}

impl PodcastrCore {
    /// Fire an app-scope delta (`subscription_id == 0`) through the installed
    /// callback, if any.
    fn fire_delta(&self, change: DataChangeType) {
        let cb = self.callback_slot().read().clone();
        if let Some(cb) = cb {
            cb.on_data_changed(Delta {
                subscription_id: 0,
                change,
            });
        }
    }
}
