uniffi::setup_scaffolding!();

pub mod client;
pub mod errors;
pub mod events;
pub mod models;
pub mod nostr_runtime;
pub mod relays;
pub mod session;
pub mod subscriptions;

// Feature modules — each is filled in by a parallel agent.
pub mod blossom;
pub mod comments;
pub mod nip19;
pub mod nip46;
mod nip46_uri;
pub mod peer_agent;
pub mod podcast_discovery;
pub mod podcast_publisher;
pub mod profile;
pub mod threads;

pub use client::PodcastrCore;
pub use errors::CoreError;
pub use events::{DataChangeType, Delta, EventCallback};
