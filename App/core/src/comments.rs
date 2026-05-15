//! NIP-22 (kind:1111) comment subscription + publish — port of
//! `App/Sources/Services/NostrCommentService.swift`.
//!
//! ## Wire format (matches Swift `NostrCommentService.publish`)
//!
//! A top-level NIP-22 comment on external content (an episode or a clip)
//! carries FOUR reference tags. The uppercase pair scopes the *root*
//! (the artifact being commented on); the lowercase pair scopes the
//! *parent* (the comment above in the thread). For top-level comments
//! parent == root, so the two pairs hold the same identifier:
//!
//! ```text
//! kind: 1111
//! content: "<plain text>"
//! tags:
//!   ["I", "<nip73 identifier>"]   // root
//!   ["K", "<nip73 kind>"]
//!   ["i", "<nip73 identifier>"]   // parent (== root)
//!   ["k", "<nip73 kind>"]
//! ```
//!
//! ## Subscribe shape
//!
//! Filter pins `kind=1111` and `#i = anchor.nip73_identifier()` — the
//! lowercase tag — matching Swift `NostrCommentService.sendREQ`. Limit
//! 200 events for parity.
//!
//! ## Event delivery
//!
//! The single notification pump in [`crate::nostr_runtime`] dispatches
//! through the [`Router`] this module installs. No polling. EOSE emits a
//! `DataChangeType::SubscriptionEose` so the Swift side can flip its UI
//! out of the "initial fetch" state.

use std::sync::Arc;

use nostr_sdk::prelude::*;

use crate::client::PodcastrCore;
use crate::errors::CoreError;
use crate::events::{DataChangeType, Delta};
use crate::models::{CommentAnchor, CommentRecord, SignedEvent};
use crate::subscriptions::{CallbackSubscriptionId, Router};

/// NIP-22 comment kind.
const KIND_COMMENT: u16 = 1111;
/// Match Swift `NostrCommentService.sendREQ` — pull the most recent 200
/// comments per anchor on initial fetch.
const COMMENT_FETCH_LIMIT: usize = 200;

/// Routes incoming kind:1111 events to the Swift callback as
/// `CommentReceived` deltas. The router carries the anchor identifier
/// the subscription was opened with so it can populate
/// `CommentRecord.anchor_identifier` without re-parsing the filter on
/// every event.
struct CommentRouter {
    sub_id_for_callback: CallbackSubscriptionId,
    anchor_identifier: String,
}

impl Router for CommentRouter {
    fn callback_id(&self) -> CallbackSubscriptionId {
        self.sub_id_for_callback
    }

    fn on_event(&self, event: &Event, _relay_url: &RelayUrl) -> Vec<Delta> {
        // Defensive: filter already pins kind:1111 + `#i`, but a future
        // filter loosening could land unrelated events here. Drop anything
        // that doesn't match the wire shape.
        if u16::from(event.kind) != KIND_COMMENT {
            return Vec::new();
        }

        // Confirm the lowercase `i` tag actually contains our anchor.
        // Belt-and-braces against relays that ignore tag filters.
        let matches_anchor = event.tags.iter().any(|tag| {
            let parts = tag.as_slice();
            parts.first().map(String::as_str) == Some("i")
                && parts.get(1).map(String::as_str) == Some(self.anchor_identifier.as_str())
        });
        if !matches_anchor {
            return Vec::new();
        }

        let record = CommentRecord {
            event_id: event.id.to_hex(),
            author_pubkey: event.pubkey.to_hex(),
            content: event.content.clone(),
            created_at: event.created_at.as_secs() as i64,
            anchor_identifier: self.anchor_identifier.clone(),
        };

        vec![Delta {
            subscription_id: self.sub_id_for_callback,
            change: DataChangeType::CommentReceived { comment: record },
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
    /// Open a streaming subscription for NIP-22 (kind:1111) comments
    /// anchored to `anchor`. Events stream to the Swift `EventCallback` as
    /// `CommentReceived` deltas keyed by `callback_subscription_id`; an
    /// EOSE arrival emits a `SubscriptionEose` delta on the same key.
    ///
    /// Returns the relay-side `SubscriptionId` as a String; pass it back
    /// to [`Self::unsubscribe_comments`] to release the subscription.
    ///
    /// Wire-format parity with Swift `NostrCommentService.subscribe`:
    ///   * `kind = 1111`
    ///   * `#i = anchor.nip73_identifier()`  (lowercase — parent scope)
    ///   * `limit = 200`
    pub async fn subscribe_comments(
        &self,
        anchor: CommentAnchor,
        callback_subscription_id: u64,
    ) -> Result<String, CoreError> {
        let identifier = anchor.nip73_identifier();

        let filter = Filter::new()
            .kind(Kind::Custom(KIND_COMMENT))
            .custom_tag(SingleLetterTag::lowercase(Alphabet::I), identifier.clone())
            .limit(COMMENT_FETCH_LIMIT);

        let sub_id = SubscriptionId::generate();
        let router = Arc::new(CommentRouter {
            sub_id_for_callback: callback_subscription_id,
            anchor_identifier: identifier,
        });

        self.runtime()
            .subscribe(sub_id.clone(), filter, router)
            .await?;

        Ok(sub_id.to_string())
    }

    /// Tear down a comments subscription. Idempotent.
    pub async fn unsubscribe_comments(&self, sub_id: String) {
        let id = SubscriptionId::new(sub_id);
        self.runtime().unsubscribe(id).await;
    }

    /// Build, sign, and publish a NIP-22 kind:1111 top-level comment
    /// anchored to `anchor`. Returns the signed event so the UI can
    /// optimistically append before the relay echoes it back through a
    /// live subscription (mirrors Swift `NostrCommentService.publish`).
    ///
    /// Emits the canonical four-tag set:
    ///   * `["I", <identifier>]`, `["K", <kind>]`  — root
    ///   * `["i", <identifier>]`, `["k", <kind>]`  — parent (== root)
    ///
    /// Requires an authenticated session with a writable signer (i.e.
    /// `login_nsec`, not `login_pubkey` — read-only sessions error with
    /// `CoreError::Signer` from `sign_event_builder`).
    pub async fn publish_comment(
        &self,
        content: String,
        anchor: CommentAnchor,
    ) -> Result<SignedEvent, CoreError> {
        let trimmed = content.trim();
        if trimmed.is_empty() {
            return Err(CoreError::InvalidInput("comment body is empty".into()));
        }

        let identifier = anchor.nip73_identifier();
        let kind_tag = anchor.nip73_kind();

        // Four tags, root + parent both pointing at the anchor.
        let tags: Vec<Tag> = vec![
            parse_tag(["I", identifier.as_str()])?,
            parse_tag(["K", kind_tag.as_str()])?,
            parse_tag(["i", identifier.as_str()])?,
            parse_tag(["k", kind_tag.as_str()])?,
        ];

        let builder = EventBuilder::new(Kind::Custom(KIND_COMMENT), trimmed).tags(tags);
        let client = self.runtime().client();
        let event = client
            .sign_event_builder(builder)
            .await
            .map_err(map_client_error)?;
        client
            .send_event(&event)
            .await
            .map_err(|e| CoreError::Relay(format!("publish comment: {e}")))?;

        Ok(signed_event_from(&event))
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn parse_tag<I, S>(parts: I) -> Result<Tag, CoreError>
where
    I: IntoIterator<Item = S>,
    S: Into<String>,
{
    Tag::parse(parts).map_err(|e| CoreError::Other(format!("build tag: {e}")))
}

fn map_client_error(err: nostr_sdk::client::Error) -> CoreError {
    let msg = err.to_string();
    let lower = msg.to_lowercase();
    if lower.contains("signer not configured")
        || lower.contains("not configured")
        || lower.contains("no signer")
    {
        CoreError::NotAuthenticated
    } else {
        CoreError::Signer(msg)
    }
}

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
