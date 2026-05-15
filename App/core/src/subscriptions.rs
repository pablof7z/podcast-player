//! Subscription router. Maps `SubscriptionId` → handler that converts an
//! incoming `RelayPoolNotification` into zero or more [`Delta`]s.
//!
//! No polling: the single notification pump in [`crate::nostr_runtime`]
//! calls [`SubscriptionRegistry::dispatch`] on every notification and
//! the handlers are pure functions of (event, callback id).

use std::collections::HashMap;
use std::sync::Arc;

use nostr_sdk::prelude::*;
use parking_lot::RwLock;

use crate::events::Delta;

/// Identifier used by Swift to route a delta back to the view/store that
/// installed the subscription.
pub type CallbackSubscriptionId = u64;

/// A router converts a relay notification into zero or more Swift-bound
/// deltas. Implementations are owned by feature modules.
pub type SubscriptionRouter = Arc<dyn Router>;

pub trait Router: Send + Sync {
    /// The Swift-side subscription id this router fans events to.
    fn callback_id(&self) -> CallbackSubscriptionId;

    /// Convert a single event into deltas. Return `Vec::new()` for events
    /// the router doesn't care about.
    fn on_event(&self, event: &Event, relay_url: &RelayUrl) -> Vec<Delta>;

    /// Optional EOSE handler. Default: no-op.
    fn on_eose(&self) -> Vec<Delta> {
        Vec::new()
    }
}

pub struct SubscriptionRegistry {
    routes: RwLock<HashMap<SubscriptionId, SubscriptionRouter>>,
}

impl SubscriptionRegistry {
    pub fn new() -> Self {
        Self {
            routes: RwLock::new(HashMap::new()),
        }
    }

    pub fn install(&self, id: SubscriptionId, router: SubscriptionRouter) {
        self.routes.write().insert(id, router);
    }

    pub fn remove(&self, id: &SubscriptionId) {
        self.routes.write().remove(id);
    }

    /// Look up the router for a notification and produce deltas. Returns
    /// `None` if no router is interested.
    pub async fn dispatch(&self, notification: &RelayPoolNotification) -> Option<Vec<Delta>> {
        match notification {
            RelayPoolNotification::Event {
                subscription_id,
                event,
                relay_url,
            } => {
                let router = self.routes.read().get(subscription_id).cloned()?;
                let deltas = router.on_event(event, relay_url);
                if deltas.is_empty() {
                    None
                } else {
                    Some(deltas)
                }
            }
            RelayPoolNotification::Message {
                message: RelayMessage::EndOfStoredEvents(subscription_id),
                ..
            } => {
                let router = self.routes.read().get(subscription_id).cloned()?;
                let deltas = router.on_eose();
                if deltas.is_empty() {
                    None
                } else {
                    Some(deltas)
                }
            }
            _ => None,
        }
    }
}

impl Default for SubscriptionRegistry {
    fn default() -> Self {
        Self::new()
    }
}
