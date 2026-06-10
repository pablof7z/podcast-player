//! Kernel-side feedback-thread reduction (#354).
//!
//! Ports the Nostr reduction that used to run in the iOS shell
//! (`FeedbackStore.buildThreads` + `SignedNostrEvent` / `FeedbackModels` tag
//! parsing) into the kernel, so the shell renders a typed, already-resolved
//! projection instead of re-deriving Nostr semantics. Per NMP doctrine
//! (D0/D5): event-kind branching, NIP-10 thread reconstruction, tag parsing,
//! and kind:513 replaceable supersession belong in the kernel, not the shell.
//!
//! Input: the raw `SignedNostrEvent`-shaped JSON values cached by the feedback
//! observer (kind:1 notes + kind:513 metadata for the project coordinate).
//! Output: roots (newest-first) with their replies (oldest-first) and the
//! resolved (newest-wins) metadata.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// kind:1 text note (feedback message / reply).
const KIND_TEXT_NOTE: u32 = 1;
/// kind:513 feedback metadata (title / summary / status).
const KIND_METADATA: u32 = 513;

/// A resolved feedback reply (kind:1 under a root), screen-shaped.
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
pub struct FeedbackReplyDto {
    pub event_id: String,
    pub author_pubkey: String,
    pub content: String,
    pub created_at: i64,
}

/// A resolved feedback thread (kind:1 root + replies + kind:513 metadata),
/// screen-shaped. `category` is the canonical tag value (`bug`,
/// `feature-request`, `question`, `praise`); the shell maps it to its enum.
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
pub struct FeedbackThreadDto {
    pub event_id: String,
    pub author_pubkey: String,
    pub category: String,
    pub content: String,
    pub created_at: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub summary: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub status_label: Option<String>,
    pub replies: Vec<FeedbackReplyDto>,
}

/// Minimal decode of a `SignedNostrEvent`-shaped cache value. `sig` is ignored
/// (display-only reduction); missing fields default rather than fail so a
/// malformed cache entry is skipped, not fatal.
#[derive(Clone, Debug, Default, Deserialize)]
struct RawEvent {
    #[serde(default)]
    id: String,
    #[serde(default)]
    pubkey: String,
    #[serde(default)]
    created_at: i64,
    #[serde(default)]
    kind: u32,
    #[serde(default)]
    tags: Vec<Vec<String>>,
    #[serde(default)]
    content: String,
}

impl RawEvent {
    /// `a`-tag coordinates (e.g. the project addressable reference).
    fn a_tags(&self) -> impl Iterator<Item = &str> {
        self.tags
            .iter()
            .filter(|t| t.len() >= 2 && t[0] == "a")
            .map(|t| t[1].as_str())
    }

    /// First `e`-tag event id, if any.
    fn first_e_tag(&self) -> Option<&str> {
        self.tags
            .iter()
            .find(|t| t.len() >= 2 && t[0] == "e")
            .map(|t| t[1].as_str())
    }

    /// NIP-10 root event id: prefer an explicit `["e", id, relay, "root"]`
    /// marker, else fall back to the first `e` tag.
    fn root_event_id(&self) -> Option<&str> {
        if let Some(marked) = self
            .tags
            .iter()
            .find(|t| t.len() >= 4 && t[0] == "e" && t[3] == "root")
        {
            return Some(marked[1].as_str());
        }
        self.first_e_tag()
    }

    /// Canonical feedback category from a `t` / `category` tag, defaulting to
    /// `bug` (mirrors `FeedbackCategory.from(tags:)`).
    fn category(&self) -> String {
        let tagged = self
            .tags
            .iter()
            .find(|t| t.len() >= 2 && (t[0] == "t" || t[0] == "category"))
            .map(|t| t[1].to_lowercase());
        match tagged.as_deref() {
            Some("bug") => "bug",
            Some("feature-request") | Some("feature request") => "feature-request",
            Some("question") => "question",
            Some("praise") => "praise",
            _ => "bug",
        }
        .to_string()
    }
}

/// Resolved kind:513 metadata for a thread.
#[derive(Clone, Debug, Default)]
struct MetaParsed {
    created_at: i64,
    title: Option<String>,
    summary: Option<String>,
    status_label: Option<String>,
}

/// Parse title / summary / status from a kind:513 event: tag values first
/// (first-wins), then a content-JSON fallback (mirrors `FeedbackMetadata`).
fn parse_meta(ev: &RawEvent) -> MetaParsed {
    let mut title: Option<String> = None;
    let mut summary: Option<String> = None;
    let mut status: Option<String> = None;
    for t in &ev.tags {
        if t.len() < 2 {
            continue;
        }
        match t[0].as_str() {
            "title" => title.get_or_insert_with(|| t[1].clone()),
            "summary" => summary.get_or_insert_with(|| t[1].clone()),
            "status-label" | "status_label" | "status" => {
                status.get_or_insert_with(|| t[1].clone())
            }
            _ => continue,
        };
    }
    if (title.is_none() || summary.is_none() || status.is_none()) && !ev.content.is_empty() {
        if let Ok(Value::Object(map)) = serde_json::from_str::<Value>(&ev.content) {
            let s = |k: &str| map.get(k).and_then(|v| v.as_str()).map(str::to_string);
            if title.is_none() {
                title = s("title");
            }
            if summary.is_none() {
                summary = s("summary");
            }
            if status.is_none() {
                status = s("status_label").or_else(|| s("status"));
            }
        }
    }
    MetaParsed {
        created_at: ev.created_at,
        title,
        summary,
        status_label: status,
    }
}

/// Reduce the flat feedback-event cache into resolved threads. Replicates the
/// former Swift `buildThreads`: newest-wins kind:513 metadata per root, kind:1
/// replies grouped by their NIP-10 root, and kind:1 roots (no root tag,
/// carrying the project `a` coordinate) sorted newest-first with replies
/// oldest-first.
pub fn reduce_feedback_threads(events: &[Value], project_coordinate: &str) -> Vec<FeedbackThreadDto> {
    let parsed: Vec<RawEvent> = events
        .iter()
        .filter_map(|v| serde_json::from_value(v.clone()).ok())
        .collect();

    // Newest-wins kind:513 metadata, keyed by the root it annotates.
    let mut meta_by_root: HashMap<String, MetaParsed> = HashMap::new();
    for ev in parsed.iter().filter(|e| e.kind == KIND_METADATA) {
        let Some(root) = ev.root_event_id() else {
            continue;
        };
        match meta_by_root.get(root) {
            Some(existing) if existing.created_at >= ev.created_at => continue,
            _ => {
                meta_by_root.insert(root.to_string(), parse_meta(ev));
            }
        }
    }

    // kind:1 replies grouped by root.
    let mut replies_by_root: HashMap<String, Vec<&RawEvent>> = HashMap::new();
    for ev in parsed
        .iter()
        .filter(|e| e.kind == KIND_TEXT_NOTE && e.root_event_id().is_some())
    {
        let root = ev.root_event_id().unwrap().to_string();
        replies_by_root.entry(root).or_default().push(ev);
    }

    // kind:1 roots: no root tag + carry the project coordinate.
    let mut roots: Vec<&RawEvent> = parsed
        .iter()
        .filter(|e| {
            e.kind == KIND_TEXT_NOTE
                && e.root_event_id().is_none()
                && e.a_tags().any(|a| a == project_coordinate)
        })
        .collect();
    roots.sort_by(|a, b| b.created_at.cmp(&a.created_at));

    roots
        .into_iter()
        .map(|root| {
            let mut replies = replies_by_root.get(&root.id).cloned().unwrap_or_default();
            replies.sort_by(|a, b| a.created_at.cmp(&b.created_at));
            let meta = meta_by_root.get(&root.id);
            FeedbackThreadDto {
                event_id: root.id.clone(),
                author_pubkey: root.pubkey.clone(),
                category: root.category(),
                content: root.content.clone(),
                created_at: root.created_at,
                title: meta.and_then(|m| m.title.clone()),
                summary: meta.and_then(|m| m.summary.clone()),
                status_label: meta.and_then(|m| m.status_label.clone()),
                replies: replies
                    .into_iter()
                    .map(|r| FeedbackReplyDto {
                        event_id: r.id.clone(),
                        author_pubkey: r.pubkey.clone(),
                        content: r.content.clone(),
                        created_at: r.created_at,
                    })
                    .collect(),
            }
        })
        .collect()
}

#[cfg(test)]
#[path = "feedback_threads_tests.rs"]
mod tests;
