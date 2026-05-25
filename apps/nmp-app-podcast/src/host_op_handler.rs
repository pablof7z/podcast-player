//! `PodcastHostOpHandler` — runs podcast actions on the actor thread.
//!
//! Installed by `nmp_app_podcast_register` via
//! `NmpApp::set_host_op_handler`. The actor dispatches
//! `ActorCommand::DispatchHostOp { action_json, correlation_id }` here
//! after `PodcastActionModule::execute` routes the action.
//!
//! Each `handle` call receives the JSON-encoded `PodcastAction` and
//! returns a `{"ok":true}` or `{"ok":false,"error":"..."}` envelope.
//!
//! ## Lock discipline
//!
//! MUST release ALL `PodcastStore` / `PlayerActor` locks BEFORE calling
//! `NmpApp::dispatch_capability` to prevent deadlock with the snapshot
//! path on the main thread.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use chrono::Utc;
use nmp_core::substrate::{CapabilityRequest, HostOpHandler};
use nmp_ffi::NmpApp;
use podcast_core::PodcastId;
use podcast_feeds::client::{build_feed_request, handle_feed_response, FeedResult};
use podcast_feeds::http::{HttpResult, HTTP_CAPABILITY_NAMESPACE};

use crate::ffi::actions::podcast_module::PodcastAction;
use crate::store::PodcastStore;

pub struct PodcastHostOpHandler {
    app: *mut NmpApp,
    store: Arc<Mutex<PodcastStore>>,
    rev: Arc<AtomicU64>,
}

// SAFETY: `app` is never mutated through this pointer (only read via
// `dispatch_capability(&self, ...)`). `PodcastHostOpHandler` is dropped only
// after `nmp_app_free` joins the actor thread, fencing any in-flight call.
unsafe impl Send for PodcastHostOpHandler {}
unsafe impl Sync for PodcastHostOpHandler {}

impl PodcastHostOpHandler {
    pub fn new(
        app: *mut NmpApp,
        store: Arc<Mutex<PodcastStore>>,
        rev: Arc<AtomicU64>,
    ) -> Self {
        Self { app, store, rev }
    }

    fn handle_subscribe(&self, feed_url: String, correlation_id: &str) -> serde_json::Value {
        let url = match url::Url::parse(&feed_url) {
            Ok(u) => u,
            Err(e) => {
                return serde_json::json!({"ok": false, "error": format!("bad url: {e}")})
            }
        };

        let http_req = build_feed_request(&url, None);
        let payload_json = match serde_json::to_string(&http_req) {
            Ok(j) => j,
            Err(e) => return serde_json::json!({"ok": false, "error": format!("encode: {e}")}),
        };

        let capability_req = CapabilityRequest {
            namespace: HTTP_CAPABILITY_NAMESPACE.to_owned(),
            correlation_id: correlation_id.to_owned(),
            payload_json,
        };

        // ALL store / actor locks MUST be released before dispatch_capability
        // to prevent deadlock with the snapshot path.
        let envelope = unsafe { &*self.app }.dispatch_capability(&capability_req);

        let http_result: HttpResult = match serde_json::from_str(&envelope.result_json) {
            Ok(r) => r,
            Err(e) => {
                return serde_json::json!({"ok": false, "error": format!("decode http result: {e}")})
            }
        };

        let podcast_id = PodcastId::generate();
        match handle_feed_response(&url, podcast_id, &http_result, None, Utc::now()) {
            Ok(FeedResult::Parsed { parsed, .. }) => {
                match self.store.lock() {
                    Ok(mut s) => {
                        s.subscribe(parsed.podcast, parsed.episodes);
                        self.rev.fetch_add(1, Ordering::Relaxed);
                        serde_json::json!({"ok": true})
                    }
                    Err(_) => serde_json::json!({"ok": false, "error": "store poisoned"}),
                }
            }
            Ok(FeedResult::NotModified { .. }) => {
                serde_json::json!({"ok": true, "not_modified": true})
            }
            Err(e) => serde_json::json!({"ok": false, "error": format!("{e:?}")}),
        }
    }
}

impl HostOpHandler for PodcastHostOpHandler {
    fn handle(&self, action_json: &str, correlation_id: &str) -> serde_json::Value {
        let action: PodcastAction = match serde_json::from_str(action_json) {
            Ok(a) => a,
            Err(e) => {
                return serde_json::json!({"ok": false, "error": format!("decode action: {e}")})
            }
        };

        match action {
            PodcastAction::Subscribe { feed_url } => {
                self.handle_subscribe(feed_url, correlation_id)
            }
        }
    }
}
