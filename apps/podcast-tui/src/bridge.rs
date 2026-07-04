use std::sync::mpsc::{self, Receiver, Sender};

use nmp_app_podcast::ffi::{PodcastApp, PodcastUpdateSink};

/// Lightweight signal that the kernel has emitted a new snapshot.
/// The actual payload is read on the main thread via
/// `AppRuntime::podcast_update` so we never block the listener
/// callback thread with store locks.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NmpEvent;

pub struct NmpUpdateBridge {
    tx: Sender<NmpEvent>,
}

impl NmpUpdateBridge {
    #[must_use]
    pub fn channel() -> (Box<Self>, Receiver<NmpEvent>) {
        let (tx, rx) = mpsc::channel();
        (Box::new(Self { tx }), rx)
    }

    /// Register `bridge` as the app-owned UniFFI facade's update listener.
    pub fn register(app: &PodcastApp, bridge: &mut Box<Self>) {
        let tx = bridge.tx.clone();
        app.set_update_sink(Some(Box::new(TuiUpdateSink { tx })));
    }
}

struct TuiUpdateSink {
    tx: Sender<NmpEvent>,
}

impl PodcastUpdateSink for TuiUpdateSink {
    fn on_update(&self, _frame: Vec<u8>) {
        let _ = self.tx.send(NmpEvent);
    }
}

pub fn unregister(app: &PodcastApp) {
    app.set_update_sink(None);
}
