use podcast_core::PodcastId;
use serde::{Deserialize, Serialize};
use url::Url;

/// Action: refresh a single feed by URL. The podcast identity is preserved
/// across the round trip via `podcast_id` so the dispatcher can correlate
/// the result back into the store.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RefreshFeedAction {
    pub podcast_id: PodcastId,
    pub feed_url: Url,
}

/// Action: refresh every followed feed. The dispatcher applies the
/// `RefreshPolicy` per-subscription to decide which feeds are due.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct RefreshAllFeedsAction;

/// Action: import an OPML XML document.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ImportOpmlAction {
    pub opml_xml: String,
}

/// Action: export current followed podcasts as OPML. The dispatcher
/// collects the podcast list and calls `export_opml`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExportOpmlAction;

#[cfg(test)]
#[path = "actions_tests.rs"]
mod tests;
