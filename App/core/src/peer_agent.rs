//! Peer agent inbound/outbound bridge — port of
//! `App/Sources/Services/NostrAgentResponder.swift` (Nostr-only parts) and
//! `App/Sources/Agent/AgentRelayBridge.swift` /
//! `App/Sources/Agent/LivePeerEventPublisher.swift`.
//!
//! Architectural carve-out: the LLM orchestration that lives in
//! `NostrAgentResponder` depends on the iOS agent SDK (provider switching,
//! cost ledger, tool dispatch, owner-consult coordinator) — none of that is
//! reachable from Rust. So this module owns ONLY the Nostr protocol
//! primitives:
//!
//!   * Persistent subscription for `#p` mentions on kind:1 (NIP-42 AUTH
//!     handled automatically by `nostr-sdk` — see note in `client.rs` /
//!     `nostr_runtime.rs`; `automatic_authentication` defaults to true in
//!     0.44.1 and `Client::builder().build()` keeps the default).
//!   * Sign + publish a kind:1 reply with NIP-10 root/reply/p tags.
//!   * Broadcast a hand-crafted, already-signed Event (Swift edge cases
//!     where the reply tag set needs the `a`-tag copy-through from the
//!     root event, which we deliberately don't replicate here).
//!   * Republish the agent's kind:0 metadata.
//!
//! Dedup, since-cursor, per-thread mutex, and the LLM loop stay in Swift.
//! Rust accepts a `since: Option<i64>` and surfaces every event past it;
//! Swift owns deduping by event id.

use std::sync::Arc;

use nostr_sdk::prelude::*;

use crate::client::PodcastrCore;
use crate::errors::CoreError;
use crate::events::{DataChangeType, Delta};
use crate::models::{PeerMessageRecord, SignedEvent};
use crate::subscriptions::{CallbackSubscriptionId, Router};

/// Routes incoming kind:1 events tagged with `my_pubkey` in `#p` to the
/// Swift callback. The router owns a captured copy of `my_pubkey` because
/// the session state isn't reachable from inside `Router::on_event`.
struct PeerMessageRouter {
    sub_id_for_callback: CallbackSubscriptionId,
    my_pubkey_hex: String,
    my_pubkey: PublicKey,
}

impl Router for PeerMessageRouter {
    fn callback_id(&self) -> CallbackSubscriptionId {
        self.sub_id_for_callback
    }

    fn on_event(&self, event: &Event, _relay_url: &RelayUrl) -> Vec<Delta> {
        // Defensive: filter already pins kind:1 and `#p` to us, but a
        // misconfigured relay (or a future filter loosening) could land
        // unrelated events here. Belt and braces — drop anything else.
        if event.kind != Kind::TextNote {
            return Vec::new();
        }

        // Confirm the `#p` mention is ours. Skip self-authored events —
        // even though Swift's gates will also drop them, doing it here
        // means we don't waste an FFI hop on the no-op delta.
        if event.pubkey == self.my_pubkey {
            return Vec::new();
        }
        let p_matches = event.tags.iter().any(|tag| {
            let parts = tag.as_slice();
            parts.first().map(|s| s.as_str()) == Some("p")
                && parts.get(1).map(|s| s.as_str()) == Some(self.my_pubkey_hex.as_str())
        });
        if !p_matches {
            return Vec::new();
        }

        let record = PeerMessageRecord {
            event_id: event.id.to_hex(),
            from_pubkey: event.pubkey.to_hex(),
            to_pubkey: self.my_pubkey_hex.clone(),
            content: event.content.clone(),
            created_at: event.created_at.as_secs() as i64,
        };

        vec![Delta {
            subscription_id: self.sub_id_for_callback,
            change: DataChangeType::PeerMessageReceived { message: record },
        }]
    }
}

/// Convert a signed `nostr_sdk::Event` into the UniFFI record. Tags are
/// flattened to `Vec<Vec<String>>` so Swift sees the same shape it sends.
fn signed_event_from(event: &Event) -> SignedEvent {
    SignedEvent {
        id: event.id.to_hex(),
        pubkey: event.pubkey.to_hex(),
        created_at: event.created_at.as_secs() as i64,
        kind: u16::from(event.kind) as u32,
        tags: event
            .tags
            .iter()
            .map(|t| t.as_slice().to_vec())
            .collect(),
        content: event.content.clone(),
        sig: event.sig.to_string(),
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl PodcastrCore {
    /// Install a persistent kind:1 subscription gated on `#p == <my pubkey>`.
    /// Events stream to the Swift `EventCallback` as `PeerMessageReceived`
    /// deltas keyed by `callback_subscription_id`.
    ///
    /// `since`: optional UNIX seconds floor. The Swift side owns the
    /// persisted cursor and dedup set; this argument is plumbed straight
    /// through to the relay filter.
    ///
    /// Requires an authenticated session — the `#p` filter needs our hex
    /// pubkey, and any AUTH challenge from the relay needs the configured
    /// signer (handled transparently by `nostr-sdk`'s
    /// `automatic_authentication` default).
    ///
    /// Returns the relay-side `SubscriptionId` as a String; Swift passes it
    /// back to `unsubscribe_peer_messages` to release the subscription.
    pub async fn subscribe_peer_messages(
        &self,
        since: Option<i64>,
        callback_subscription_id: u64,
    ) -> Result<String, CoreError> {
        let my_pubkey_hex = self
            .current_pubkey()
            .ok_or(CoreError::NotAuthenticated)?;
        let my_pubkey = PublicKey::from_hex(&my_pubkey_hex)
            .map_err(|e| CoreError::InvalidInput(format!("invalid session pubkey: {e}")))?;

        let mut filter = Filter::new().kind(Kind::TextNote).pubkey(my_pubkey);
        if let Some(secs) = since {
            // Negative cursors would underflow `Timestamp::from(u64)` — clamp.
            let secs = secs.max(0) as u64;
            filter = filter.since(Timestamp::from(secs));
        }

        let sub_id = SubscriptionId::generate();
        let router = Arc::new(PeerMessageRouter {
            sub_id_for_callback: callback_subscription_id,
            my_pubkey_hex,
            my_pubkey,
        });

        self.runtime()
            .subscribe(sub_id.clone(), filter, router)
            .await?;

        Ok(sub_id.to_string())
    }

    /// Tear down a peer-message subscription previously returned by
    /// [`Self::subscribe_peer_messages`]. Idempotent.
    pub async fn unsubscribe_peer_messages(&self, sub_id: String) {
        let id = SubscriptionId::new(sub_id);
        self.runtime().unsubscribe(id).await;
    }

    /// Sign and broadcast a kind:1 reply with NIP-10 tags. Swift owns
    /// content composition; the Rust side just lays down the canonical
    /// reply tag triple:
    ///   * `["e", root_id, "", "root"]`
    ///   * `["e", reply_id, "", "reply"]` (only when distinct from root)
    ///   * `["p", mention_pubkey]`
    ///
    /// `a`-tag copy-through from the root event (channel anchors) is NOT
    /// applied here — Swift handles that path via
    /// [`Self::publish_signed_event_json`] when it needs to.
    ///
    /// Requires an authenticated session with a writable signer (i.e.
    /// `login_nsec`, not `login_pubkey` — read-only sessions error with
    /// `CoreError::Signer` from `sign_event_builder`).
    pub async fn publish_peer_reply(
        &self,
        content: String,
        root_event_id: String,
        reply_to_event_id: Option<String>,
        mention_pubkey: String,
    ) -> Result<SignedEvent, CoreError> {
        if self.current_pubkey().is_none() {
            return Err(CoreError::NotAuthenticated);
        }

        let root_id = EventId::from_hex(root_event_id.trim())
            .map_err(|e| CoreError::InvalidInput(format!("invalid root event id: {e}")))?;
        let mention = PublicKey::from_hex(mention_pubkey.trim())
            .map_err(|e| CoreError::InvalidInput(format!("invalid mention pubkey: {e}")))?;
        let reply_id = match reply_to_event_id.as_deref().map(str::trim) {
            Some(s) if !s.is_empty() => Some(
                EventId::from_hex(s)
                    .map_err(|e| CoreError::InvalidInput(format!("invalid reply event id: {e}")))?,
            ),
            _ => None,
        };

        // NIP-10 marker positional: `["e", <id>, <relay-hint>, <marker>]`.
        // We don't know a per-event relay hint, so leave the slot empty
        // (matches the Swift implementation in NostrAgentResponder).
        let mut tags: Vec<Tag> = Vec::with_capacity(3);
        tags.push(
            Tag::parse(vec![
                "e".to_string(),
                root_id.to_hex(),
                "".to_string(),
                "root".to_string(),
            ])
            .map_err(|e| CoreError::Other(format!("build root e tag: {e}")))?,
        );
        if let Some(reply) = reply_id {
            if reply != root_id {
                tags.push(
                    Tag::parse(vec![
                        "e".to_string(),
                        reply.to_hex(),
                        "".to_string(),
                        "reply".to_string(),
                    ])
                    .map_err(|e| CoreError::Other(format!("build reply e tag: {e}")))?,
                );
            }
        }
        tags.push(
            Tag::parse(vec!["p".to_string(), mention.to_hex()])
                .map_err(|e| CoreError::Other(format!("build p tag: {e}")))?,
        );

        let builder = EventBuilder::new(Kind::TextNote, content).tags(tags);
        let client = self.runtime().client();
        let event = client
            .sign_event_builder(builder)
            .await
            .map_err(|e| CoreError::Signer(format!("sign peer reply: {e}")))?;
        client
            .send_event(&event)
            .await
            .map_err(|e| CoreError::Relay(format!("publish peer reply: {e}")))?;

        Ok(signed_event_from(&event))
    }

    /// Broadcast an already-signed event. Swift composes + signs the event
    /// when it needs to do something the canonical [`Self::publish_peer_reply`]
    /// tag layout doesn't support (e.g. copying `a`-tags from the root, the
    /// `AgentRelayBridge` channel-anchor case). Returns the event id hex.
    ///
    /// This is broadcast-only — no signing happens here. If the caller
    /// passes an unsigned or malformed event, parse fails with
    /// `CoreError::InvalidInput`.
    pub async fn publish_signed_event_json(
        &self,
        event_json: String,
    ) -> Result<String, CoreError> {
        let event = Event::from_json(event_json.as_bytes())
            .map_err(|e| CoreError::InvalidInput(format!("parse event json: {e}")))?;
        self.runtime()
            .client()
            .send_event(&event)
            .await
            .map_err(|e| CoreError::Relay(format!("publish signed event: {e}")))?;
        Ok(event.id.to_hex())
    }

    /// Sign and broadcast a kind:0 metadata event for the active signer.
    /// Replaces `NostrRelayService.republishProfile` in Swift.
    ///
    /// `name` is required (the JSON `name` field is the canonical handle
    /// other clients display when a peer hasn't set `display_name`);
    /// every other field is optional and only written into the payload
    /// when non-empty. Empty optionals are *omitted* rather than written
    /// as `""` so a future "clear this field" UX can do it cleanly without
    /// stale-empty-string ghosts on aggressive clients.
    pub async fn republish_agent_profile(
        &self,
        name: String,
        display_name: Option<String>,
        about: Option<String>,
        picture: Option<String>,
        nip05: Option<String>,
        lud16: Option<String>,
    ) -> Result<SignedEvent, CoreError> {
        if self.current_pubkey().is_none() {
            return Err(CoreError::NotAuthenticated);
        }

        let mut metadata = Metadata::new().name(name);
        if let Some(s) = display_name.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
            metadata = metadata.display_name(s.to_string());
        }
        if let Some(s) = about.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
            metadata = metadata.about(s.to_string());
        }
        if let Some(s) = picture.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
            let url = Url::parse(s)
                .map_err(|e| CoreError::InvalidInput(format!("invalid picture URL: {e}")))?;
            metadata = metadata.picture(url);
        }
        if let Some(s) = nip05.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
            metadata = metadata.nip05(s.to_string());
        }
        if let Some(s) = lud16.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
            metadata = metadata.lud16(s.to_string());
        }

        let builder = EventBuilder::metadata(&metadata);
        let client = self.runtime().client();
        let event = client
            .sign_event_builder(builder)
            .await
            .map_err(|e| CoreError::Signer(format!("sign metadata: {e}")))?;
        client
            .send_event(&event)
            .await
            .map_err(|e| CoreError::Relay(format!("publish metadata: {e}")))?;

        Ok(signed_event_from(&event))
    }
}
