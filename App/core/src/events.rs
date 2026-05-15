//! Push-based change notifications from Rust core into Swift.
//!
//! Every change is wrapped in a [`Delta`] carrying a `subscription_id`, so
//! the Swift side can route deltas back to the view/store that installed
//! the subscription. `0` is reserved for app-scoped events (signer state,
//! relay status) that aren't tied to a specific subscription.

use crate::models::{
    CommentRecord, NoteAuthorRecord, PeerMessageRecord, PodcastEpisodeRecord, PodcastShowRecord,
    ProfileRecord, RelayStatus, ThreadEventRecord,
};

#[derive(Debug, Clone, uniffi::Enum)]
pub enum DataChangeType {
    /// kind:0 profile metadata arrived for `pubkey`.
    ProfileUpdated { pubkey: String, profile: ProfileRecord },
    /// A NIP-22 (kind:1111) comment arrived for the open subscription.
    CommentReceived { comment: CommentRecord },
    /// A NIP-10 thread event arrived.
    ThreadEventReceived { event: ThreadEventRecord },
    /// NIP-74 podcast show announcement (kind:30074).
    PodcastShowDiscovered { show: PodcastShowRecord },
    /// NIP-74 podcast episode announcement (kind:30075).
    PodcastEpisodeDiscovered { episode: PodcastEpisodeRecord },
    /// A peer-to-peer agent message arrived (kind:1 with `#p` tag).
    PeerMessageReceived { message: PeerMessageRecord },
    /// Note author metadata (display name + picture) resolved.
    NoteAuthorResolved { pubkey: String, author: NoteAuthorRecord },
    /// NIP-46 signer connected.
    SignerConnected { pubkey: String },
    /// NIP-46 signer disconnected / errored.
    SignerDisconnected { reason: String },
    /// A relay in the pool changed connection state.
    RelayStatusChanged { url: String, state: RelayStatus },
    /// End-of-stored-events signal for the subscription.
    SubscriptionEose,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct Delta {
    pub subscription_id: u64,
    pub change: DataChangeType,
}

#[uniffi::export(with_foreign)]
pub trait EventCallback: Send + Sync {
    fn on_data_changed(&self, delta: Delta);
}
