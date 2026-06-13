//! JSON persistence for the agent-note-responder state:
//! - responded event IDs (dedup gate — never reply twice to the same event)
//! - per-root outgoing turn counts (turn-cap gate — suppress after 10 turns)
//!
//! ## Shape
//!
//! Free functions over a `&Path`, following the `inbox_triage_cache` pattern.
//! The stored value is a single JSON object:
//! ```json
//! {
//!   "responded_event_ids": ["<event-id-hex>", ...],
//!   "outgoing_turns":      {"<root-event-id-hex>": 3, ...}
//! }
//! ```
//!
//! ## D6
//!
//! Both directions degrade silently. A missing file is a fresh start (cold
//! install / first run), not an error. A corrupt or unparseable file loads as
//! empty state — the worst outcome is a duplicate reply on first post-crash
//! launch, which is acceptable for a v1 responder. A write failure leaves the
//! in-memory state authoritative for the session.

use std::collections::{HashMap, HashSet, VecDeque};
use std::path::Path;

use serde::{Deserialize, Serialize};

/// File name written under the bound `data_dir`.
pub const RESPONDER_CACHE_FILE: &str = "agent-note-responder-cache.json";

/// Upper bound on the number of responded event IDs retained for the dedup
/// gate. The set is an insertion-ordered ring: once it reaches this cap, the
/// oldest ID is evicted when a new one is recorded. This keeps both the memory
/// footprint and the per-save serialization cost constant for a long-lived
/// agent that may respond indefinitely.
///
/// Eviction can only *re-admit* the oldest event for a duplicate reply (a
/// re-delivery of a note older than the last `MAX_RESPONDED_IDS` responses),
/// which is benign — the same fail-safe tolerated for a post-crash restart.
pub const MAX_RESPONDED_IDS: usize = 4096;

/// Insertion-ordered, capacity-bounded set of responded event IDs.
///
/// Backs the dedup gate. `order` preserves insertion order so the oldest ID can
/// be evicted in O(1); `set` provides O(1) membership tests. Both structures are
/// kept in lock-step — an eviction removes from BOTH.
#[derive(Debug, Default, Clone)]
pub struct RespondedIds {
    order: VecDeque<String>,
    set: HashSet<String>,
}

impl RespondedIds {
    /// Returns `true` if `event_id` is currently retained.
    pub fn contains(&self, event_id: &str) -> bool {
        self.set.contains(event_id)
    }

    /// Returns `true` if no event IDs are retained.
    pub fn is_empty(&self) -> bool {
        self.order.is_empty()
    }

    /// Number of retained IDs (≤ `MAX_RESPONDED_IDS`).
    pub fn len(&self) -> usize {
        self.order.len()
    }

    /// Insert an event ID, evicting the oldest if the cap is exceeded.
    /// Re-inserting an already-present ID is a no-op (does not reorder), so a
    /// genuine duplicate never displaces a distinct recent entry.
    pub fn insert(&mut self, event_id: &str) {
        if self.set.contains(event_id) {
            return;
        }
        self.set.insert(event_id.to_string());
        self.order.push_back(event_id.to_string());
        while self.order.len() > MAX_RESPONDED_IDS {
            if let Some(oldest) = self.order.pop_front() {
                self.set.remove(&oldest);
            }
        }
    }

    /// Snapshot the IDs in insertion order (oldest first), for serialization.
    fn to_ordered_vec(&self) -> Vec<String> {
        self.order.iter().cloned().collect()
    }

    /// Rebuild from a persisted, insertion-ordered list (oldest first).
    /// Applies the same cap on load so a previously-unbounded file is trimmed.
    fn from_ordered_vec(ids: Vec<String>) -> Self {
        let mut out = Self::default();
        for id in ids {
            out.insert(&id);
        }
        out
    }
}

/// On-disk shape for the responder state sidecar.
#[derive(Debug, Default, Deserialize, Serialize)]
struct ResponderCacheFile {
    #[serde(default)]
    responded_event_ids: Vec<String>,
    #[serde(default)]
    outgoing_turns: HashMap<String, u32>,
}

/// Loaded, in-memory representation of the responder persistence state.
///
/// This cache is intentionally **GLOBAL / account-agnostic**: a single shared
/// sidecar file, not partitioned per signing identity. Dedup is keyed by the
/// globally-unique Nostr event id and the turn-cap by the global root event id,
/// so any cross-account carryover (e.g. switching the active identity without
/// clearing this) can only ever *suppress* a reply, never cause an over-reply —
/// a fail-safe direction. Do NOT confuse this with account-scoped social state
/// (the follow set / agent notes cleared on identity change in `register.rs`);
/// this one must deliberately persist across identity switches.
#[derive(Debug, Default, Clone)]
pub struct ResponderCache {
    /// Event IDs we have already replied to. Never reply twice to the same
    /// event (dedup gate). Capacity-bounded ring — see `MAX_RESPONDED_IDS`.
    pub responded_event_ids: RespondedIds,
    /// Number of outgoing turns we have published in each root thread.
    /// Key = root_event_id (hex), value = count. Keyed by *active* roots, so
    /// this grows only with concurrent live threads — left unbounded by design.
    pub outgoing_turns: HashMap<String, u32>,
}

impl ResponderCache {
    /// Record a response: add the event to responded IDs and increment the
    /// turn counter for the root thread.
    pub fn record_response(&mut self, event_id: &str, root_event_id: &str) {
        self.responded_event_ids.insert(event_id);
        *self
            .outgoing_turns
            .entry(root_event_id.to_string())
            .or_insert(0) += 1;
    }

    /// Returns `true` if we have already replied to `event_id`.
    pub fn already_responded(&self, event_id: &str) -> bool {
        self.responded_event_ids.contains(event_id)
    }

    /// Returns the outgoing turn count for the given root thread.
    pub fn turns_for_root(&self, root_event_id: &str) -> u32 {
        self.outgoing_turns
            .get(root_event_id)
            .copied()
            .unwrap_or(0)
    }
}

/// Write the responder cache to `<data_dir>/agent-note-responder-cache.json`.
///
/// Atomic: serialize → `.tmp` → `rename`, matching the `inbox_triage_cache`
/// discipline so a torn write never corrupts the file.
pub fn save_responder_cache(dir: &Path, cache: &ResponderCache) -> Result<(), String> {
    std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let on_disk = ResponderCacheFile {
        responded_event_ids: cache.responded_event_ids.to_ordered_vec(),
        outgoing_turns: cache.outgoing_turns.clone(),
    };
    let json = serde_json::to_vec_pretty(&on_disk).map_err(|e| e.to_string())?;
    let final_path = dir.join(RESPONDER_CACHE_FILE);
    let tmp_path = dir.join(format!("{RESPONDER_CACHE_FILE}.tmp"));
    std::fs::write(&tmp_path, &json).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp_path, &final_path).map_err(|e| e.to_string())
}

/// Load the persisted responder cache from disk.
///
/// Returns `ResponderCache::default()` (empty) when the file is missing or
/// unparseable — a fresh start, not an error (D6).
#[must_use]
pub fn load_responder_cache(dir: &Path) -> ResponderCache {
    let path = dir.join(RESPONDER_CACHE_FILE);
    let Ok(bytes) = std::fs::read(&path) else {
        return ResponderCache::default();
    };
    match serde_json::from_slice::<ResponderCacheFile>(&bytes) {
        Ok(f) => ResponderCache {
            responded_event_ids: RespondedIds::from_ordered_vec(f.responded_event_ids),
            outgoing_turns: f.outgoing_turns,
        },
        Err(_) => ResponderCache::default(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(tag: &str) -> std::path::PathBuf {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir =
            std::env::temp_dir().join(format!("responder-cache-{tag}-{nanos}"));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn round_trip_preserves_responded_ids_and_turns() {
        let dir = temp_dir("roundtrip");
        let mut cache = ResponderCache::default();
        cache.record_response("event_aaa", "root_111");
        cache.record_response("event_bbb", "root_111");
        cache.record_response("event_ccc", "root_222");

        save_responder_cache(&dir, &cache).expect("save");
        let loaded = load_responder_cache(&dir);

        assert!(loaded.already_responded("event_aaa"));
        assert!(loaded.already_responded("event_bbb"));
        assert!(loaded.already_responded("event_ccc"));
        assert!(!loaded.already_responded("event_zzz"));

        assert_eq!(loaded.turns_for_root("root_111"), 2);
        assert_eq!(loaded.turns_for_root("root_222"), 1);
        assert_eq!(loaded.turns_for_root("root_999"), 0);

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn missing_file_returns_empty() {
        let dir = temp_dir("missing");
        let loaded = load_responder_cache(&dir);
        assert!(loaded.responded_event_ids.is_empty());
        assert!(loaded.outgoing_turns.is_empty());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn corrupt_file_returns_empty() {
        let dir = temp_dir("corrupt");
        std::fs::write(dir.join(RESPONDER_CACHE_FILE), b"{ not valid json").unwrap();
        let loaded = load_responder_cache(&dir);
        assert!(loaded.responded_event_ids.is_empty());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn responded_ids_ring_evicts_oldest_at_cap() {
        let mut ids = RespondedIds::default();
        // Fill exactly to the cap.
        for i in 0..MAX_RESPONDED_IDS {
            ids.insert(&format!("event_{i}"));
        }
        assert_eq!(ids.len(), MAX_RESPONDED_IDS);
        assert!(ids.contains("event_0"), "oldest still present at the cap");
        assert!(ids.contains(&format!("event_{}", MAX_RESPONDED_IDS - 1)));

        // One past the cap: the oldest (event_0) is evicted, len stays pinned.
        ids.insert("event_overflow");
        assert_eq!(ids.len(), MAX_RESPONDED_IDS, "len pinned at cap");
        assert!(!ids.contains("event_0"), "oldest evicted");
        assert!(ids.contains("event_overflow"), "newest retained");
        // A still-recent id is unaffected and still deduped.
        assert!(ids.contains("event_1"), "recent id survives eviction");
        assert!(ids.contains(&format!("event_{}", MAX_RESPONDED_IDS - 1)));
    }

    #[test]
    fn responded_ids_duplicate_insert_does_not_reorder_or_grow() {
        let mut ids = RespondedIds::default();
        ids.insert("a");
        ids.insert("b");
        // Re-inserting an existing id is a no-op: no growth, no reorder.
        ids.insert("a");
        assert_eq!(ids.len(), 2, "duplicate insert does not grow the ring");
        assert_eq!(ids.to_ordered_vec(), vec!["a".to_string(), "b".to_string()]);
    }

    #[test]
    fn bounded_ring_survives_save_reload_in_order() {
        let dir = temp_dir("ring-reload");
        let mut cache = ResponderCache::default();
        for i in 0..8 {
            cache.record_response(&format!("ev_{i}"), "root_x");
        }
        save_responder_cache(&dir, &cache).expect("save");
        let loaded = load_responder_cache(&dir);
        assert_eq!(loaded.responded_event_ids.len(), 8);
        assert!(loaded.already_responded("ev_0"));
        assert!(loaded.already_responded("ev_7"));
        assert_eq!(loaded.turns_for_root("root_x"), 8);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn save_is_atomic_no_tmp_left() {
        let dir = temp_dir("atomic");
        let cache = ResponderCache::default();
        save_responder_cache(&dir, &cache).expect("save");
        let tmp = dir.join(format!("{RESPONDER_CACHE_FILE}.tmp"));
        assert!(!tmp.exists(), "tmp must be renamed away");
        assert!(dir.join(RESPONDER_CACHE_FILE).exists(), "final file present");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
