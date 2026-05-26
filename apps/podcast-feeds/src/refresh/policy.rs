use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};

/// User-facing refresh cadence for a subscription. The Swift
/// `SubscriptionRefreshService` only had a hardcoded 30-minute interval;
/// this enum introduces the explicit policy levels the M2.C spec calls for.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RefreshPolicy {
    Manual,
    Hourly,
    Every4h,
    Every12h,
    Daily,
}

impl RefreshPolicy {
    /// Minimum interval between refreshes, or `None` for `Manual` (never
    /// auto-refresh — the user drives it from the UI).
    pub fn interval(self) -> Option<Duration> {
        match self {
            RefreshPolicy::Manual => None,
            RefreshPolicy::Hourly => Some(Duration::hours(1)),
            RefreshPolicy::Every4h => Some(Duration::hours(4)),
            RefreshPolicy::Every12h => Some(Duration::hours(12)),
            RefreshPolicy::Daily => Some(Duration::hours(24)),
        }
    }
}

/// Decides whether a feed is due for refresh given the time of its last
/// successful refresh and the policy. Pure decision logic — callers
/// (M5 HTTP capability) execute the fetch.
pub fn should_refresh(
    last_refreshed: Option<DateTime<Utc>>,
    policy: RefreshPolicy,
    now: DateTime<Utc>,
) -> bool {
    let interval = match policy.interval() {
        Some(i) => i,
        None => return false,
    };
    let last = match last_refreshed {
        Some(t) => t,
        None => return true,
    };
    now.signed_duration_since(last) >= interval
}

/// Conditional-GET cache for a single feed. Mirrors the etag/last-modified
/// fields persisted on `Podcast` in the legacy schema, lifted into a small
/// value so callers can pass it around without dragging the whole podcast.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EtagCache {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub etag: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_modified: Option<String>,
    pub last_refreshed: DateTime<Utc>,
}

impl EtagCache {
    pub fn new(last_refreshed: DateTime<Utc>) -> Self {
        Self {
            etag: None,
            last_modified: None,
            last_refreshed,
        }
    }

    pub fn with_headers(
        last_refreshed: DateTime<Utc>,
        etag: Option<String>,
        last_modified: Option<String>,
    ) -> Self {
        Self {
            etag,
            last_modified,
            last_refreshed,
        }
    }
}

#[cfg(test)]
#[path = "policy_tests.rs"]
mod tests;
