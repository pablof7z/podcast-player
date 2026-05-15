//! Owns the singleton `nostr_sdk::Client` for the life of the app.
//!
//! Async lifecycle: `PodcastrCore::new()` is a synchronous UniFFI
//! constructor, so we own a dedicated tokio runtime for connecting to
//! relays and running the notification pump.
//!
//! Event delivery is push-based: a single pump task consumes
//! `client.notifications()` and dispatches `Delta`s to whatever
//! `EventCallback` is installed. Feature modules attach themselves to the
//! [`SubscriptionRegistry`] to receive the events they care about — no
//! polling, ever.

use std::sync::Arc;

use nostr_sdk::prelude::*;
use parking_lot::RwLock;
use tokio::runtime::Runtime;
use tokio::sync::Notify;

use crate::errors::CoreError;
use crate::events::EventCallback;
use crate::relays::{seed_defaults, RelayConfig};
use crate::subscriptions::{SubscriptionRegistry, SubscriptionRouter};

pub type CallbackSlot = Arc<RwLock<Option<Arc<dyn EventCallback>>>>;

pub struct NostrRuntime {
    client: Client,
    /// Held as `Option` so Drop can `take()` it and call
    /// `shutdown_background()` — Tokio's default `Drop` blocks waiting on
    /// the spawned pump task, which never exits on its own.
    rt: Option<Runtime>,
    /// Cached copy of the relay config last applied to the pool.
    current_relays: Arc<RwLock<Vec<RelayConfig>>>,
    /// Subscription router: subscription id → handler set. The pump
    /// dispatches notifications through this.
    pub(crate) registry: Arc<SubscriptionRegistry>,
    /// Callback slot shared with the pump.
    callback_slot: CallbackSlot,
    /// Signal that fires when the pump should shut down.
    shutdown: Arc<Notify>,
}

impl Drop for NostrRuntime {
    fn drop(&mut self) {
        self.shutdown.notify_waiters();
        if let Some(rt) = self.rt.take() {
            rt.shutdown_background();
        }
    }
}

impl NostrRuntime {
    pub fn new(callback_slot: CallbackSlot) -> Result<Self, CoreError> {
        let client = Client::builder().build();

        let rt = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .thread_name("podcastr-nostr")
            .build()
            .map_err(|e| CoreError::Other(format!("build tokio runtime: {e}")))?;

        let registry = Arc::new(SubscriptionRegistry::new());
        let shutdown = Arc::new(Notify::new());

        let runtime = Self {
            client,
            rt: Some(rt),
            current_relays: Arc::new(RwLock::new(Vec::new())),
            registry: registry.clone(),
            callback_slot: callback_slot.clone(),
            shutdown: shutdown.clone(),
        };

        runtime.apply_relays(seed_defaults());
        runtime.spawn_notification_pump();

        Ok(runtime)
    }

    pub fn client(&self) -> &Client {
        &self.client
    }

    pub fn callback_slot(&self) -> CallbackSlot {
        self.callback_slot.clone()
    }

    pub fn registry(&self) -> &Arc<SubscriptionRegistry> {
        &self.registry
    }

    pub fn runtime_handle(&self) -> tokio::runtime::Handle {
        self.rt().handle().clone()
    }

    fn rt(&self) -> &Runtime {
        self.rt
            .as_ref()
            .expect("NostrRuntime::rt accessed after Drop")
    }

    /// Replace the relay pool wholesale. Used both at startup (seed_defaults)
    /// and after a NIP-65 fetch.
    pub fn apply_relays(&self, relays: Vec<RelayConfig>) {
        let urls: Vec<String> = relays.iter().map(|r| r.url.clone()).collect();
        *self.current_relays.write() = relays;
        let client = self.client.clone();
        self.rt().spawn(async move {
            for url in urls {
                if let Err(e) = client.add_relay(&url).await {
                    tracing::warn!(relay = %url, error = %e, "add_relay failed");
                }
            }
            client.connect().await;
        });
    }

    pub fn current_relays(&self) -> Vec<RelayConfig> {
        self.current_relays.read().clone()
    }

    pub fn set_signer<T>(&self, signer: T)
    where
        T: IntoNostrSigner,
    {
        self.rt().block_on(async {
            self.client.set_signer(signer).await;
        });
    }

    pub fn unset_signer(&self) {
        self.rt().block_on(async {
            self.client.unset_signer().await;
        });
    }

    /// Spawn the single notification pump. It runs until the runtime is
    /// dropped and dispatches every received event through the registry.
    fn spawn_notification_pump(&self) {
        let client = self.client.clone();
        let registry = self.registry.clone();
        let callback_slot = self.callback_slot.clone();
        let shutdown = self.shutdown.clone();

        self.rt().spawn(async move {
            let mut notifications = client.notifications();
            loop {
                tokio::select! {
                    _ = shutdown.notified() => {
                        tracing::info!("notification pump: shutdown");
                        break;
                    }
                    msg = notifications.recv() => {
                        match msg {
                            Ok(notification) => {
                                if let Some(deltas) = registry.dispatch(&notification).await {
                                    let cb = callback_slot.read().clone();
                                    if let Some(cb) = cb {
                                        for delta in deltas {
                                            cb.on_data_changed(delta);
                                        }
                                    }
                                }
                            }
                            Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                                tracing::warn!(skipped = n, "notification pump lagged");
                            }
                            Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                                tracing::info!("notification pump: channel closed");
                                break;
                            }
                        }
                    }
                }
            }
        });
    }

    /// Install a subscription on the client. The pump dispatches incoming
    /// events through the registry — feature modules don't poll.
    pub async fn subscribe(
        &self,
        sub_id: SubscriptionId,
        filter: Filter,
        router: SubscriptionRouter,
    ) -> Result<(), CoreError> {
        self.registry.install(sub_id.clone(), router);
        self.client
            .subscribe_with_id(sub_id, filter, None)
            .await
            .map_err(|e| CoreError::Relay(e.to_string()))?;
        Ok(())
    }

    pub async fn unsubscribe(&self, sub_id: SubscriptionId) {
        self.client.unsubscribe(&sub_id).await;
        self.registry.remove(&sub_id);
    }
}
