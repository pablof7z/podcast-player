//! Podcast-local notification capability contract — `nmp.notification.capability`.
//!
//! This is the schema the iOS executor (`Capabilities/NotificationCapability.swift`)
//! implements. Rust serializes a [`NotificationCommand`]; iOS executes it against
//! `UNUserNotificationCenter`. There is no back-channel report: this capability is
//! purely fire-and-forget — Rust tells iOS what to schedule, iOS schedules it.
//!
//! ## Doctrine
//!
//! * **D0 — Rust decides.** Whether to *notify* the user about a particular new
//!   episode is a Rust-side policy decision (today: every newly-discovered episode
//!   on every refresh). iOS never inspects payload content to decide whether to
//!   raise a notification — it just schedules whatever Rust hands it.
//! * **D7 — capabilities execute, never decide.** The iOS half builds a
//!   `UNMutableNotificationContent` from the fields below and calls
//!   `UNUserNotificationCenter.current().add(_:)`. It does not throttle, dedupe,
//!   or batch — Rust owns those decisions if/when they're added.
//! * **D6 — no errors across the boundary.** Authorization failures, scheduling
//!   errors, and malformed payloads degrade silently on the iOS side; the
//!   capability never throws.
//!
//! ## Namespace
//!
//! The namespace string is `nmp.notification.capability`, matching the
//! `HttpCapability::namespace` / `KeychainCapability` / `DownloadCapability`
//! convention.

use serde::{Deserialize, Serialize};

/// Capability namespace string. Mirrors the other capability namespaces so the
/// iOS-side router in `PodcastCapabilities.handleJSON` can dispatch by the same
/// string the broader capability plan uses.
pub const NOTIFICATION_CAPABILITY_NAMESPACE: &str = "nmp.notification.capability";

// ---------------------------------------------------------------------------
// Rust → iOS: NotificationCommand
// ---------------------------------------------------------------------------

/// Commands Rust dispatches to the iOS notification capability.
///
/// Wire form is `serde`-tagged on `"type"` (`snake_case`):
///
/// ```text
/// {"type":"schedule_new_episode","episode_title":"…","podcast_title":"…","episode_id":"…"}
/// ```
///
/// **D7:** the variant is *imperative* — the executor turns it into a
/// `UNMutableNotificationContent` + `UNUserNotificationCenter.add(_:)` call.
/// There is no `decide_*` flavoured command; Rust does the deciding before
/// dispatching.
#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum NotificationCommand {
    /// Schedule a local notification announcing a newly-discovered episode.
    /// The executor builds a `UNNotificationRequest` whose `title` is the
    /// podcast title and whose `body` is `"New episode: <episode_title>"`.
    /// `episode_id` lands in `userInfo` so a future deep-link / tap handler
    /// can navigate straight to the episode.
    ScheduleNewEpisode {
        /// Display title of the new episode (`Episode::title`).
        episode_title: String,
        /// Display title of the parent podcast (`Podcast::title`).
        podcast_title: String,
        /// Stable episode identifier the executor stamps into the
        /// notification's `userInfo` under the key `"episodeId"`.
        episode_id: String,
    },
}

impl NotificationCommand {
    /// Convenience: construct a `ScheduleNewEpisode` command from owned strings.
    #[must_use]
    pub fn schedule_new_episode(
        episode_title: impl Into<String>,
        podcast_title: impl Into<String>,
        episode_id: impl Into<String>,
    ) -> Self {
        Self::ScheduleNewEpisode {
            episode_title: episode_title.into(),
            podcast_title: podcast_title.into(),
            episode_id: episode_id.into(),
        }
    }
}

/// Encode a [`NotificationCommand`] to its canonical JSON wire form.
///
/// Mirrors `encode_audio_command` in [`crate::capability::dispatch`] but returns
/// a `String` rather than `Option<String>` because `serde_json::to_string` on a
/// well-typed enum with `String` fields cannot fail. We unwrap here so the
/// dispatch site doesn't have to thread a `None` case it can never observe.
#[must_use]
pub fn notification_command_json(cmd: &NotificationCommand) -> String {
    serde_json::to_string(cmd).expect("NotificationCommand serialization is infallible")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn namespace_matches_canonical_capability_plan() {
        assert_eq!(
            NOTIFICATION_CAPABILITY_NAMESPACE,
            "nmp.notification.capability"
        );
    }

    #[test]
    fn schedule_new_episode_serde_roundtrips() {
        let cmd = NotificationCommand::schedule_new_episode(
            "The Big Reveal",
            "Mystery Hour",
            "ep-42",
        );
        let json = serde_json::to_string(&cmd).expect("encode");
        assert!(json.contains("\"type\":\"schedule_new_episode\""));
        assert!(json.contains("\"episode_title\":\"The Big Reveal\""));
        assert!(json.contains("\"podcast_title\":\"Mystery Hour\""));
        assert!(json.contains("\"episode_id\":\"ep-42\""));
        let decoded: NotificationCommand = serde_json::from_str(&json).expect("decode");
        assert_eq!(decoded, cmd);
    }

    #[test]
    fn notification_command_json_helper_round_trips() {
        let cmd = NotificationCommand::schedule_new_episode(
            "Episode Two",
            "Podcast One",
            "ep-2",
        );
        let json = notification_command_json(&cmd);
        let decoded: NotificationCommand = serde_json::from_str(&json).expect("decode");
        assert_eq!(decoded, cmd);
    }

    #[test]
    fn wire_keys_are_snake_case() {
        // The Swift `Codable` decoder uses snake_case keys to match the Rust
        // `#[serde(rename_all = "snake_case")]` on the variant fields. Lock
        // that contract here so renaming a field on either side trips the test.
        let cmd = NotificationCommand::schedule_new_episode("t", "p", "id");
        let json = serde_json::to_string(&cmd).expect("encode");
        assert!(!json.contains("episodeTitle"));
        assert!(!json.contains("podcastTitle"));
        assert!(!json.contains("episodeId"));
    }
}
