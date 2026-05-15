//! kind:0 profile metadata fetcher — port of
//! `App/Sources/Services/NostrProfileFetcher.swift`.
//!
//! Semantics differ from the Swift original by design: rather than running a
//! short-lived one-shot REQ against a single relay, we install a *persistent*
//! subscription on the shared `nostr-sdk` client. The notification pump in
//! [`crate::nostr_runtime`] dispatches every incoming kind:0 event through
//! [`ProfileRouter`], which parses the metadata JSON and emits
//! [`DataChangeType::ProfileUpdated`] deltas to Swift.
//!
//! No timers, no polling. The subscription stays open until Swift calls
//! `unsubscribe_profiles` (or `PodcastrCore` drops).

use std::sync::Arc;

use nostr_sdk::prelude::*;
use serde::Deserialize;

use crate::client::PodcastrCore;
use crate::errors::CoreError;
use crate::events::{DataChangeType, Delta};
use crate::models::ProfileRecord;
use crate::subscriptions::{CallbackSubscriptionId, Router};

/// JSON shape of a kind:0 event's `.content` field. Per NIP-01 every field is
/// optional; unknown keys are ignored.
#[derive(Debug, Default, Deserialize)]
struct ProfileMetadata {
    name: Option<String>,
    display_name: Option<String>,
    picture: Option<String>,
    about: Option<String>,
    nip05: Option<String>,
    lud16: Option<String>,
}

/// Routes incoming kind:0 events to the Swift callback identified by
/// `sub_id_for_callback`.
pub struct ProfileRouter {
    pub sub_id_for_callback: CallbackSubscriptionId,
}

impl Router for ProfileRouter {
    fn callback_id(&self) -> CallbackSubscriptionId {
        self.sub_id_for_callback
    }

    fn on_event(&self, event: &Event, _relay_url: &RelayUrl) -> Vec<Delta> {
        // Defensive: the filter already pins kind:0, but the pump shares this
        // router with every event on the subscription id — guard anyway.
        if event.kind != Kind::Metadata {
            return Vec::new();
        }

        // Parse the metadata payload. Malformed JSON is logged and dropped so
        // a single bad event can't crash the pump or kill the subscription.
        let metadata: ProfileMetadata = match serde_json::from_str(&event.content) {
            Ok(m) => m,
            Err(err) => {
                tracing::debug!(
                    pubkey = %event.pubkey,
                    error = %err,
                    "profile: skipping kind:0 with unparseable content",
                );
                return Vec::new();
            }
        };

        let pubkey_hex = event.pubkey.to_hex();
        let profile = ProfileRecord {
            pubkey: pubkey_hex.clone(),
            name: metadata.name,
            display_name: metadata.display_name,
            picture: metadata.picture,
            about: metadata.about,
            nip05: metadata.nip05,
            lud16: metadata.lud16,
            // Use the *event's* created_at, not anything inside the JSON
            // payload — that's the freshness signal Swift uses to pick the
            // latest record per pubkey.
            created_at: event.created_at.as_secs() as i64,
        };

        vec![Delta {
            subscription_id: self.sub_id_for_callback,
            change: DataChangeType::ProfileUpdated {
                pubkey: pubkey_hex,
                profile,
            },
        }]
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl PodcastrCore {
    /// Install a persistent kind:0 subscription for `pubkeys`. Profile
    /// updates stream to the Swift `EventCallback` as `ProfileUpdated`
    /// deltas keyed by `callback_subscription_id`.
    ///
    /// Returns the relay-side `SubscriptionId` as a String; Swift must pass
    /// it back to [`Self::unsubscribe_profiles`] to release the subscription.
    pub async fn subscribe_profiles(
        &self,
        pubkeys: Vec<String>,
        callback_subscription_id: u64,
    ) -> Result<String, CoreError> {
        if pubkeys.is_empty() {
            return Err(CoreError::InvalidInput(
                "subscribe_profiles requires at least one pubkey".into(),
            ));
        }

        let mut authors: Vec<PublicKey> = Vec::with_capacity(pubkeys.len());
        for hex in &pubkeys {
            let pk = PublicKey::from_hex(hex)
                .map_err(|e| CoreError::InvalidInput(format!("invalid pubkey {hex}: {e}")))?;
            authors.push(pk);
        }

        let filter = Filter::new().kind(Kind::Metadata).authors(authors);
        let sub_id = SubscriptionId::generate();
        let router = Arc::new(ProfileRouter {
            sub_id_for_callback: callback_subscription_id,
        });

        self.runtime()
            .subscribe(sub_id.clone(), filter, router)
            .await?;

        Ok(sub_id.to_string())
    }

    /// Tear down a profile subscription previously returned by
    /// [`Self::subscribe_profiles`]. Idempotent: unknown ids are a no-op on
    /// the relay pool side.
    pub async fn unsubscribe_profiles(&self, sub_id: String) {
        let id = SubscriptionId::new(sub_id);
        self.runtime().unsubscribe(id).await;
    }
}
