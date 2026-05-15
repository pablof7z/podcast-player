//! NIP-10 thread streaming — port of
//! `App/Sources/Services/NostrThreadFetcher.swift`.
//!
//! The Swift original is a one-shot WebSocket fetch (read until EOSE,
//! then close). For the Rust core we promote it to a *streaming*
//! subscription instead: events keep arriving as new replies are
//! posted, the Swift side hangs the conversation UI off a single open
//! subscription, and unsubscribe is explicit. The wire shape is
//! unchanged — a single conceptual REQ with two filters:
//!
//!   1. the root event itself (by id)
//!   2. every event whose `#e` tag equals the root id (replies)
//!
//! ## Why two `SubscriptionId`s under one Swift-facing handle?
//!
//! `nostr_sdk::Client::subscribe_with_id` (0.44.1) takes a single
//! `Filter`. `Filter` AND-combines predicates inside itself — there's
//! no `or()`. So we open two relay-side subscriptions and install the
//! same `Arc<ThreadRouter>` under both `SubscriptionId`s in the
//! registry. From the Swift side it's one logical "thread
//! subscription": the returned handle string packs both ids joined
//! with `|` and `unsubscribe_thread` splits + tears down both.
//!
//! ## EOSE semantics
//!
//! Both legs (root + replies) emit their own EOSE. The router fans
//! every EOSE through as a `SubscriptionEose` delta on the same Swift
//! callback id — the Swift side may want to flip its "loading"
//! indicator off on the first EOSE and treat any further EOSE as a
//! no-op. Deduping that is cheap and stays in Swift; doing it in Rust
//! would mean adding mutable state to a `Router` for the sake of a UI
//! polish concern.

use std::sync::Arc;

use nostr_sdk::prelude::*;

use crate::client::PodcastrCore;
use crate::errors::CoreError;
use crate::events::{DataChangeType, Delta};
use crate::models::ThreadEventRecord;
use crate::subscriptions::{CallbackSubscriptionId, Router};

/// Delimiter used to pack the two relay-side `SubscriptionId`s into a
/// single string handle for the Swift caller. `|` is not valid inside a
/// nostr-sdk `SubscriptionId` (it is generated as a hex/base16 token), so
/// it round-trips cleanly.
const THREAD_SUB_ID_DELIM: char = '|';

/// Routes kind:1 events (and the root itself, which is also typically
/// kind:1 — but we don't gate on kind so a kind:30023 root etc. still
/// surfaces) to the Swift callback as `ThreadEventReceived` deltas.
struct ThreadRouter {
    sub_id_for_callback: CallbackSubscriptionId,
}

impl Router for ThreadRouter {
    fn callback_id(&self) -> CallbackSubscriptionId {
        self.sub_id_for_callback
    }

    fn on_event(&self, event: &Event, _relay_url: &RelayUrl) -> Vec<Delta> {
        let record = ThreadEventRecord {
            event_id: event.id.to_hex(),
            pubkey: event.pubkey.to_hex(),
            content: event.content.clone(),
            created_at: event.created_at.as_secs() as i64,
            kind: u16::from(event.kind) as u32,
            tags: event
                .tags
                .iter()
                .map(|t| t.as_slice().to_vec())
                .collect(),
        };

        vec![Delta {
            subscription_id: self.sub_id_for_callback,
            change: DataChangeType::ThreadEventReceived { event: record },
        }]
    }

    fn on_eose(&self) -> Vec<Delta> {
        vec![Delta {
            subscription_id: self.sub_id_for_callback,
            change: DataChangeType::SubscriptionEose,
        }]
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl PodcastrCore {
    /// Open a streaming subscription that delivers the root event plus
    /// every reply (any kind whose `#e` tag points at the root). Events
    /// stream to the Swift `EventCallback` as `ThreadEventReceived`
    /// deltas keyed by `callback_subscription_id`. Each leg emits its
    /// own `SubscriptionEose` delta on the same key when initial fetch
    /// completes — Swift dedups if it cares about a single "loaded"
    /// signal.
    ///
    /// Returns a composite handle: `"<root_sub_id>|<replies_sub_id>"`.
    /// Pass the exact string back to [`Self::unsubscribe_thread`] to
    /// release both legs.
    ///
    /// Wire-format parity with Swift `NostrThreadFetcher.run`:
    ///   * leg 1: `Filter::new().id(<root>)`
    ///   * leg 2: `Filter::new().kind(1).event(<root>)` — `#e == root`
    ///
    /// Note: the Swift original additionally pins `kinds=[1]` on the
    /// replies filter; we keep that here so kind:7 reactions and other
    /// non-thread chatter that happens to e-tag the root don't pollute
    /// the conversation view.
    pub async fn subscribe_thread(
        &self,
        root_event_id: String,
        callback_subscription_id: u64,
    ) -> Result<String, CoreError> {
        let root_id = EventId::from_hex(root_event_id.trim())
            .map_err(|e| CoreError::InvalidInput(format!("invalid root event id: {e}")))?;

        let router: Arc<ThreadRouter> = Arc::new(ThreadRouter {
            sub_id_for_callback: callback_subscription_id,
        });

        // Leg 1: fetch the root event by id.
        let root_filter = Filter::new().id(root_id);
        let root_sub_id = SubscriptionId::generate();
        self.runtime()
            .subscribe(root_sub_id.clone(), root_filter, router.clone())
            .await?;

        // Leg 2: stream kind:1 replies that e-tag the root.
        let replies_filter = Filter::new().kind(Kind::TextNote).event(root_id);
        let replies_sub_id = SubscriptionId::generate();
        if let Err(e) = self
            .runtime()
            .subscribe(replies_sub_id.clone(), replies_filter, router)
            .await
        {
            // First leg already opened — tear it down before surfacing.
            self.runtime().unsubscribe(root_sub_id).await;
            return Err(e);
        }

        Ok(format!(
            "{}{}{}",
            root_sub_id, THREAD_SUB_ID_DELIM, replies_sub_id
        ))
    }

    /// Tear down a thread subscription. Accepts either the composite
    /// handle returned by [`Self::subscribe_thread`] (`"<a>|<b>"`) or a
    /// bare `SubscriptionId` for forward-compat. Idempotent.
    pub async fn unsubscribe_thread(&self, sub_id: String) {
        for part in sub_id.split(THREAD_SUB_ID_DELIM) {
            let trimmed = part.trim();
            if trimmed.is_empty() {
                continue;
            }
            self.runtime()
                .unsubscribe(SubscriptionId::new(trimmed))
                .await;
        }
    }
}
