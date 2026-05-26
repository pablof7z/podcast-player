use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::types::episode::Episode;
use crate::types::podcast::PodcastId;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "mode", rename_all = "snake_case")]
pub enum AutoDownloadMode {
    Off,
    LatestN { count: u32 },
    AllNew,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AutoDownloadPolicy {
    #[serde(flatten)]
    pub mode: AutoDownloadMode,
    pub wifi_only: bool,
}

impl AutoDownloadPolicy {
    pub fn new(mode: AutoDownloadMode, wifi_only: bool) -> Self {
        Self { mode, wifi_only }
    }

    pub fn default_policy() -> Self {
        Self {
            mode: AutoDownloadMode::AllNew,
            wifi_only: true,
        }
    }

    /// First-pass decision: should the per-subscription policy auto-download
    /// `episode`?
    ///
    /// This is the M4.A skeleton: it only inspects the [`AutoDownloadMode`]
    /// variant. Real policy — storage cap, network-type guard (`wifi_only`),
    /// per-subscription "newest N already downloaded" counting, time-of-day
    /// window — lives in `podcast-feeds::refresh::policy`. Callers in M4.A
    /// use this for the action-emission decision; M4.B
    /// will refine the policy site without breaking this signature.
    ///
    /// Behaviour today:
    /// * `Off` → `false`.
    /// * `AllNew` → `true`.
    /// * `LatestN { count }` → `true` when `count > 0`. The newest-first cap
    ///   (e.g. "only the latest 5 episodes") requires counting how many are
    ///   already downloaded for this subscription, which this signature
    ///   doesn't carry. M4.B refines.
    ///
    /// `wifi_only` is intentionally **not** checked here — the network type
    /// isn't an input. M4.B's policy site has access to the path monitor and
    /// will gate the action emission accordingly.
    #[must_use]
    pub fn should_auto_download(&self, _episode: &Episode) -> bool {
        match self.mode {
            AutoDownloadMode::Off => false,
            AutoDownloadMode::AllNew => true,
            AutoDownloadMode::LatestN { count } => count > 0,
        }
    }
}

impl Default for AutoDownloadPolicy {
    fn default() -> Self {
        Self::default_policy()
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PodcastSubscription {
    pub podcast_id: PodcastId,
    pub subscribed_at: DateTime<Utc>,
    pub auto_download: AutoDownloadPolicy,
    pub notifications_enabled: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub default_playback_rate: Option<f64>,
}

impl PodcastSubscription {
    pub fn new(podcast_id: PodcastId) -> Self {
        Self {
            podcast_id,
            subscribed_at: Utc::now(),
            auto_download: AutoDownloadPolicy::default_policy(),
            notifications_enabled: true,
            default_playback_rate: None,
        }
    }

    pub fn id(&self) -> PodcastId {
        self.podcast_id
    }
}

#[cfg(test)]
#[path = "subscription_tests.rs"]
mod tests;
