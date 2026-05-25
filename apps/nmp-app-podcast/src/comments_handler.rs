//! NIP-22 (kind 1111) episode-comments host-op handlers.
//!
//! Extracted from [`crate::host_op_handler`] so the per-file line budget
//! stays under the 500-line hard ceiling and so the comments feature
//! has a single canonical home (D2 — one durable concept, one
//! representation).
//!
//! Both entry points are intentionally stubs for the initial landing of
//! feature #29 (episode comments):
//!
//! * [`handle_fetch_comments`] is a no-op that returns `{"ok":true}`.
//!   The projection layer in [`crate::ffi::snapshot::build_snapshot_payload`]
//!   surfaces an empty `comments` vec so iOS renders the empty-state
//!   copy. The real relay subscription wiring lands in a follow-up —
//!   tracked in `docs/BACKLOG.md` (`pr-episode-comments-relay-wiring`).
//!
//! * [`handle_post_comment`] returns
//!   `{"ok":true,"status":"nostr_relay_pending"}` so the iOS shell can
//!   render an optimistic confirmation toast while the actual relay
//!   publish remains pending the same follow-up.
//!
//! ## NIP-22 wire shape (for the follow-up)
//!
//! The follow-up handler will build a kind-1111 event whose tags include
//! an `["A", "10154:<podcast-pubkey>"]` reference to the show's NIP-F4
//! publisher record and an `["E", "<episode-event-id>"]` reference to
//! the episode's Nostr event id. The local `EpisodeId` (a UUID) is **not**
//! directly the `E` tag — the follow-up needs an `EpisodeId` → episode
//! event-id mapping (or the Podcasting 2.0 `<podcast:guid>` via NIP-73,
//! mirroring the legacy `App/Sources/Services/NostrCommentService.swift`
//! that anchors via `podcast:item:guid:<guid>`). The action variant
//! preserves the task's `episode_id` framing verbatim; the projection
//! layer owns the mapping policy.

/// Stub handler for `podcast.fetch_comments`. Always returns
/// `{"ok":true}` — the comments list on the snapshot stays empty until
/// the relay subscription wiring lands.
///
/// `_episode_id` is the local `EpisodeId` (UUID string) the iOS shell
/// dispatches. It is intentionally unused for now; documented so the
/// follow-up knows the action carries it.
pub fn handle_fetch_comments(_episode_id: &str) -> serde_json::Value {
    serde_json::json!({"ok": true})
}

/// Stub handler for `podcast.post_comment`. Returns
/// `{"ok":true,"status":"nostr_relay_pending"}` so iOS can render an
/// optimistic confirmation while the relay-publish path is wired in a
/// follow-up.
///
/// Empty `content` is rejected so the iOS shell doesn't accidentally
/// publish whitespace-only events (the iOS composer also gates on
/// non-empty input, but a defence-in-depth check here costs nothing).
pub fn handle_post_comment(_episode_id: &str, content: &str) -> serde_json::Value {
    if content.trim().is_empty() {
        return serde_json::json!({"ok": false, "error": "empty comment"});
    }
    serde_json::json!({"ok": true, "status": "nostr_relay_pending"})
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fetch_comments_returns_ok_envelope() {
        let v = handle_fetch_comments("00000000-0000-0000-0000-000000000001");
        assert_eq!(v["ok"], true);
    }

    #[test]
    fn post_comment_returns_pending_status() {
        let v = handle_post_comment("ep-1", "great episode");
        assert_eq!(v["ok"], true);
        assert_eq!(v["status"], "nostr_relay_pending");
    }

    #[test]
    fn post_comment_rejects_empty_content() {
        let v = handle_post_comment("ep-1", "");
        assert_eq!(v["ok"], false);
        let v = handle_post_comment("ep-1", "   ");
        assert_eq!(v["ok"], false);
    }
}
