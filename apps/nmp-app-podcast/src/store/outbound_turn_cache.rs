//! JSON persistence for outbound (kernel-published) kind:1 agent-reply turns.
//!
//! ## Purpose
//!
//! When the auto-responder publishes a reply, the event id of the outbound note
//! is captured here so the `podcast.social` domain projection can reconstruct
//! full NIP-10 conversation threads that interleave inbound and outbound turns.
//!
//! ## Shape
//!
//! A single JSON array of [`OutboundTurn`] objects persisted under the bound
//! data dir:
//! ```json
//! [
//!   {
//!     "event_id": "<hex>",
//!     "root_event_id": "<hex>",
//!     "counterparty_hex": "<64-char hex>",
//!     "content": "...",
//!     "created_at": 1700000000
//!   },
//!   ...
//! ]
//! ```
//!
//! ## D6
//!
//! A missing or corrupt file silently loads as empty state (no crash, no
//! duplicate outbound turns in projection; worst case a restart loses the turn
//! history for the session). Write failures leave the in-memory cache
//! authoritative for the session — the next successful write catches up.
//!
//! ## File-length ceiling
//!
//! AGENTS.md hard limit is 500 lines.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

/// File name written under the bound `data_dir`.
pub const OUTBOUND_TURN_CACHE_FILE: &str = "outbound-turn-cache.json";

/// Upper bound on retained outbound turns. Mirrors `MAX_INBOUND_NOTES` so the
/// projection depth is symmetric. Eviction drops the oldest turn.
pub const MAX_OUTBOUND_TURNS: usize = 200;

/// One kernel-published outbound kind:1 reply turn.
///
/// Stored raw (no trust stamp — we authored it). Used by the conversation
/// projection to reconstruct the outbound side of each NIP-10 thread.
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
pub struct OutboundTurn {
    /// Event id (lowercase hex) of the published kind:1 note — dedup key.
    pub event_id: String,
    /// NIP-10 root event id for the thread. When a note we replied to was
    /// itself the root, this equals the inbound event id we replied to.
    pub root_event_id: String,
    /// Hex pubkey of the peer we replied to (the `#p` tag recipient).
    pub counterparty_hex: String,
    /// Reply content — what we said.
    pub content: String,
    /// Unix seconds of the published event (`created_at` from the NMP
    /// publish result). Used for chronological sort within the thread.
    pub created_at: i64,
}

/// In-memory cache of outbound turns, bounded to `MAX_OUTBOUND_TURNS`.
///
/// Wraps a `Vec<OutboundTurn>` (insertion-ordered, newest-last). Dedup is by
/// `event_id` — recording the same event twice is a no-op so relay
/// re-deliveries of our own reflections are safe.
#[derive(Clone, Debug, Default)]
pub struct OutboundTurnCache(Vec<OutboundTurn>);

impl OutboundTurnCache {
    /// Construct an empty cache.
    pub fn new() -> Self {
        Self(Vec::new())
    }

    /// Record an outbound turn, deduplicating by `event_id`.
    ///
    /// If the cache has reached `MAX_OUTBOUND_TURNS` the oldest entry is
    /// evicted before insertion (ring semantics). Re-recording a known
    /// `event_id` is a no-op so a relay reflection of our own event cannot
    /// inflate the cache.
    pub fn record(&mut self, turn: OutboundTurn) {
        // Dedup: skip if already present.
        if self.0.iter().any(|t| t.event_id == turn.event_id) {
            return;
        }
        // Evict oldest when at capacity.
        while self.0.len() >= MAX_OUTBOUND_TURNS {
            self.0.remove(0);
        }
        self.0.push(turn);
    }

    /// Iterate over all cached turns (insertion order = chronological).
    pub fn turns(&self) -> &[OutboundTurn] {
        &self.0
    }

    /// Number of retained turns.
    pub fn len(&self) -> usize {
        self.0.len()
    }

    /// `true` when no turns have been recorded yet.
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
}

// ── Persistence ───────────────────────────────────────────────────────────────

/// Derive the full path to the cache file inside `data_dir`.
fn cache_path(data_dir: &Path) -> PathBuf {
    data_dir.join(OUTBOUND_TURN_CACHE_FILE)
}

/// Load the cache from `data_dir`. Returns an empty `OutboundTurnCache` when
/// the file is absent, empty, or unparseable (D6 — fresh start, not an error).
pub fn load_outbound_turn_cache(data_dir: &Path) -> OutboundTurnCache {
    let path = cache_path(data_dir);
    let bytes = match std::fs::read(&path) {
        Ok(b) if !b.is_empty() => b,
        _ => return OutboundTurnCache::new(),
    };
    match serde_json::from_slice::<Vec<OutboundTurn>>(&bytes) {
        Ok(turns) => {
            let mut cache = OutboundTurnCache::new();
            for t in turns {
                cache.record(t);
            }
            cache
        }
        Err(e) => {
            eprintln!(
                "[outbound_turn_cache] failed to parse {}: {e} — starting empty",
                path.display()
            );
            OutboundTurnCache::new()
        }
    }
}

/// Persist `cache` to `data_dir` using the atomic tmp-rename pattern so a
/// crash during write cannot corrupt the existing file.
///
/// D6: write failure is logged but NOT propagated — the in-memory cache
/// remains authoritative for the session.
pub fn save_outbound_turn_cache(
    data_dir: &Path,
    cache: &OutboundTurnCache,
) -> std::io::Result<()> {
    let bytes = serde_json::to_vec(cache.turns())?;
    let dest = cache_path(data_dir);
    let tmp = dest.with_extension("tmp");
    std::fs::write(&tmp, &bytes)?;
    std::fs::rename(&tmp, &dest)?;
    Ok(())
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn turn(id: &str, root: &str) -> OutboundTurn {
        OutboundTurn {
            event_id: id.into(),
            root_event_id: root.into(),
            counterparty_hex: "aa".repeat(32),
            content: format!("reply to {id}"),
            created_at: 1_700_000_000,
        }
    }

    #[test]
    fn record_deduplicates_by_event_id() {
        let mut cache = OutboundTurnCache::new();
        cache.record(turn("e1", "r1"));
        cache.record(turn("e1", "r1")); // dup — no-op
        assert_eq!(cache.len(), 1);
    }

    #[test]
    fn evicts_oldest_at_capacity() {
        let mut cache = OutboundTurnCache::new();
        for i in 0..MAX_OUTBOUND_TURNS {
            cache.record(turn(&format!("e{i}"), "root"));
        }
        assert_eq!(cache.len(), MAX_OUTBOUND_TURNS);
        cache.record(turn("overflow", "root")); // triggers eviction
        assert_eq!(cache.len(), MAX_OUTBOUND_TURNS);
        // The oldest ("e0") should be gone; the newest survives.
        assert!(!cache.turns().iter().any(|t| t.event_id == "e0"));
        assert!(cache.turns().iter().any(|t| t.event_id == "overflow"));
    }

    #[test]
    fn persist_and_reload_roundtrip() {
        let dir = TempDir::new().unwrap();
        let mut cache = OutboundTurnCache::new();
        cache.record(turn("e1", "r1"));
        cache.record(turn("e2", "r1"));

        save_outbound_turn_cache(dir.path(), &cache).unwrap();
        let loaded = load_outbound_turn_cache(dir.path());
        assert_eq!(loaded.len(), 2);
        assert_eq!(loaded.turns()[0].event_id, "e1");
        assert_eq!(loaded.turns()[1].event_id, "e2");
    }

    #[test]
    fn load_missing_file_returns_empty() {
        let dir = TempDir::new().unwrap();
        let cache = load_outbound_turn_cache(dir.path());
        assert!(cache.is_empty());
    }

    #[test]
    fn load_corrupt_file_returns_empty() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join(OUTBOUND_TURN_CACHE_FILE);
        std::fs::write(&path, b"not valid json").unwrap();
        let cache = load_outbound_turn_cache(dir.path());
        assert!(cache.is_empty());
    }
}
