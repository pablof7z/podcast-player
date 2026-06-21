//! Social substate — Step 10 of the god-root consolidation.
//!
//! Owns the three slots that were previously mirrored between
//! `PodcastHandle` and `PodcastHostOpHandler`, plus the new outbound-turn
//! cache for Nostr conversation projection:
//!
//! * `social` — `Option<SocialSnapshot>` from the reactive NIP-02 follow list.
//!   **Session** durability (cleared on account switch).
//! * `agent_notes` — `Vec<CachedAgentNote>` from inbound kind:1 agent notes.
//!   **Session** durability (cleared on account switch).
//! * `outbound_turns` — `Vec<OutboundTurn>` of kernel-published auto-reply
//!   turns, loaded from disk at init and appended in-session.
//!   **Session** durability (cleared on account switch).
//! * `approved` — `Arc<Mutex<ApprovedPeerStore>>` of explicit user
//!   approve/block decisions. **Durable** (NOT cleared on account switch;
//!   reloaded from the account-scoped data dir so decisions survive restarts).
//!
//! ## Observer wiring (dead-duplicate removal)
//!
//! `AgentNotesObserver` (in `crate::agent_note_handler`) writes `agent_notes`
//! off the actor thread.  It obtains its Arc via `state.social.agent_notes.share()`
//! at registration time in `register.rs`.
//!
//! `social` is written by the reactive `FollowListObserver` (in
//! `crate::social_handler`) on every kind:3 push frame, which obtains its Arc
//! via `state.social.social_slot.share()`.
//!
//! ## Trust gate — composed predicate (follow OR approve, AND NOT block)
//!
//! `trust(pubkey) = (followed(pubkey) || approved(pubkey)) && !blocked(pubkey)`
//!
//! * `followed` is the live `ActiveFollowSet` predicate (reactive, NIP-02).
//! * `approved` is an explicit per-peer user decision persisted in
//!   `ApprovedPeerStore`. An approved-but-unfollowed sender IS auto-replied to.
//! * `blocked` is an absolute override: a followed+blocked pubkey is untrusted.
//!
//! The `nostr_conversations_snapshot` projection uses [`SocialState::trust_predicate`] which
//! builds the composed closure once per projection call.
//!
//! The `ActiveFollowSet` Arc is injected via [`SocialState::with_follow_set`]
//! at registration; the `ApprovedPeerStore` Arc is injected via
//! [`SocialState::with_approved_peers`]. Both are the SAME Arcs held in
//! `register.rs`, so the predicate always reflects the latest kind:3 AND
//! the latest approve/block action.
//!
//! ## File-length ceiling
//!
//! AGENTS.md hard limit is 500 lines.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use nmp_nip02::ActiveFollowSet;

use crate::agent_note_handler::CachedAgentNote;
use crate::ffi::projections::{NostrConversationDTO, NostrConversationTurnDTO, SocialSnapshot};
use crate::state::slot::Session;
use crate::state::{Infra, Slot};
use crate::store::approved_peer_store::ApprovedPeerStore;
use crate::store::outbound_turn_cache::OutboundTurn;

/// A one-shot snapshot of the `ApprovedPeerStore`'s approved + blocked sets,
/// captured under a single lock acquisition. Shared by `trust_predicate` and
/// `peer_flags_predicate` so the composed verdict and the explicit per-peer
/// flags are always derived from identical state.
struct ApprovedBlockedSnapshot {
    /// `true` when the store mutex was poisoned and could not be read. Callers
    /// fail CLOSED (deny trust / report no explicit verdict), never fail-OPEN.
    fail_closed: bool,
    /// Explicitly approved hex pubkeys at snapshot time.
    approved: std::collections::BTreeSet<String>,
    /// Explicitly blocked hex pubkeys at snapshot time.
    blocked: std::collections::BTreeSet<String>,
}

/// Social feature substate.
///
/// Constructed once in `PodcastAppState::new` and referenced via
/// `state.social` on both seams.  All methods are `&self`.
pub struct SocialState {
    /// NIP-02 social graph snapshot.  `None` until the first kind:3 arrives
    /// reactively.  Written by `FollowListObserver` via `.share()`; read by
    /// the snapshot projection. Cleared on account switch.
    pub social_slot: Slot<Option<SocialSnapshot>, Session>,
    /// Inbound kind:1 agent-to-agent notes (raw cache, author hex retained,
    /// NO trust stamp).  Written by `AgentNotesObserver` off the actor thread
    /// via `.share()`; consumed by `nostr_conversations_snapshot` which applies
    /// the live trust verdict at projection time. Cleared on account switch.
    pub agent_notes: Slot<Vec<CachedAgentNote>, Session>,
    /// Kernel-published outbound auto-reply turns, loaded from disk at init
    /// and appended in-session via [`Self::record_outbound_turn`].
    /// Cleared on account switch so cross-account turns don't leak.
    pub outbound_turns: Slot<Vec<OutboundTurn>, Session>,
    /// Live NIP-02 follow set, shared with the kernel observer registry.
    /// `None` in unit-test / legacy paths → every note projects `trusted:
    /// false` (fail-closed, D6).  Set via [`Self::with_follow_set`] at
    /// registration.
    follow_set: Option<Arc<ActiveFollowSet>>,
    /// Kernel-owned approve/block allow-list. `None` in unit-test / legacy
    /// paths → only follow-set trust applies.  Set via
    /// [`Self::with_approved_peers`] at registration.  Durable: NOT cleared
    /// on account switch; reloaded from disk in `data_dir.rs`.
    pub approved: Option<Arc<Mutex<ApprovedPeerStore>>>,
    /// Rev + signal + runtime (cloned from `PodcastAppState::infra`).
    pub(crate) infra: Infra,
}

impl SocialState {
    /// Production constructor — called from `PodcastAppState::new`.
    pub fn new(infra: Infra) -> Self {
        Self {
            social_slot: Slot::new(None),
            agent_notes: Slot::new(Vec::new()),
            outbound_turns: Slot::new(Vec::new()),
            follow_set: None,
            approved: None,
            infra,
        }
    }

    /// Inject the shared live [`ActiveFollowSet`] so the trust verdict is
    /// recomputed at every projection build. Called from `register.rs` with
    /// the same Arc registered as a `KernelEventObserver`.
    pub fn with_follow_set(mut self, follow_set: Arc<ActiveFollowSet>) -> Self {
        self.follow_set = Some(follow_set);
        self
    }

    /// Inject the shared [`ApprovedPeerStore`] so the composed trust predicate
    /// (`follow || approve`) AND NOT `block` is applied at every projection
    /// build. Called from `register.rs` after constructing the store Arc;
    /// the same Arc is stored on `PodcastHandle` for persistence by
    /// `data_dir.rs`.
    pub fn with_approved_peers(mut self, store: Arc<Mutex<ApprovedPeerStore>>) -> Self {
        self.approved = Some(store);
        self
    }

    // ── Trust predicate ───────────────────────────────────────────────────

    /// Build the composed trust predicate for one projection call.
    ///
    /// `trust(pubkey) = (followed(pubkey) || approved(pubkey)) && !blocked(pubkey)`
    ///
    /// The predicate captures a snapshot of the follow-set predicate and a
    /// snapshot of the approved/blocked sets at the instant of the call,
    /// then closes over them. Fail-closed (D6): with no follow set AND no
    /// approved store wired (test paths), the predicate returns `false`.
    ///
    /// POISONED-LOCK FAIL-CLOSED: if the `approved` mutex is poisoned we CANNOT
    /// read the blocklist. Clearing it (treating both sets as empty) would be
    /// fail-OPEN — a blocked-but-followed peer would silently become trusted,
    /// violating "block is absolute". Instead we set `fail_closed` so the
    /// predicate returns `false` for EVERY pubkey: nobody is trusted while we
    /// cannot prove they are not blocked.
    fn trust_predicate(&self) -> impl Fn(&str) -> bool + '_ {
        // Capture follow-set predicate (itself a closure over an Arc<RwLock>).
        let follow_pred = self.follow_set.as_ref().map(|fs| fs.predicate());

        // Snapshot approved/blocked sets from the mutex. A poisoned lock means
        // we cannot read the blocklist → fail CLOSED (trust nobody) rather than
        // dropping blocks.
        let ApprovedBlockedSnapshot {
            fail_closed,
            approved: approved_snap,
            blocked: blocked_snap,
        } = self.approved_blocked_snapshot();

        move |pubkey: &str| {
            // Poisoned approved-store lock: cannot prove the peer is not
            // blocked → deny everyone (block stays absolute).
            if fail_closed {
                return false;
            }
            // Block is an absolute override.
            if blocked_snap.contains(pubkey) {
                return false;
            }
            let followed = follow_pred.as_ref().map(|p| p(pubkey)).unwrap_or(false);
            let approved = approved_snap.contains(pubkey);
            followed || approved
        }
    }

    /// Snapshot the approved + blocked sets under a single lock acquisition.
    ///
    /// Shared by [`Self::trust_predicate`] (composed verdict) and
    /// [`Self::peer_flags_predicate`] (explicit per-peer flags) so both read
    /// from the SAME `ApprovedPeerStore` state via the SAME accessor — neither
    /// reimplements the block/approve lookup independently.
    ///
    /// A poisoned lock sets `fail_closed`: `trust_predicate` denies everyone
    /// (block stays absolute) and `peer_flags_predicate` reports no explicit
    /// verdict — never fail-OPEN.
    fn approved_blocked_snapshot(&self) -> ApprovedBlockedSnapshot {
        if let Some(ref arc) = self.approved {
            if let Ok(store) = arc.lock() {
                return ApprovedBlockedSnapshot {
                    fail_closed: false,
                    approved: store.approved.clone(),
                    blocked: store.blocked.clone(),
                };
            }
            return ApprovedBlockedSnapshot {
                fail_closed: true,
                approved: Default::default(),
                blocked: Default::default(),
            };
        }
        ApprovedBlockedSnapshot {
            fail_closed: false,
            approved: Default::default(),
            blocked: Default::default(),
        }
    }

    /// Build a predicate returning EXPLICIT per-peer trust flags
    /// `(peer_blocked, peer_approved)` for the conversation projection.
    ///
    /// `peer_blocked` = the pubkey is in the `ApprovedPeerStore` blocklist.
    /// `peer_approved` = the pubkey has an EXPLICIT approval (NOT follow-derived,
    /// so a pure-follow trusted peer reports `false`).
    ///
    /// Reads the same `approved_blocked_snapshot` as the composed
    /// `trust_predicate`. On a poisoned lock (fail-closed) reports `(false,
    /// false)` — no explicit verdict — while `trust_predicate` independently
    /// denies trust, so the shell falls back to the safe untrusted UI.
    fn peer_flags_predicate(&self) -> impl Fn(&str) -> (bool, bool) + '_ {
        let ApprovedBlockedSnapshot {
            fail_closed,
            approved: approved_snap,
            blocked: blocked_snap,
        } = self.approved_blocked_snapshot();

        move |pubkey: &str| {
            if fail_closed {
                return (false, false);
            }
            (blocked_snap.contains(pubkey), approved_snap.contains(pubkey))
        }
    }

    // ── Approve / block mutating methods ─────────────────────────────────

    /// Approve `pubkey_hex` — clears any block. Caller MUST persist the store
    /// to disk and call `self.infra.bump()` after this returns.
    pub fn approve_peer(&self, pubkey_hex: &str) {
        if let Some(ref arc) = self.approved {
            if let Ok(mut store) = arc.lock() {
                store.approve(pubkey_hex);
            }
        }
    }

    /// Block `pubkey_hex` — clears any approval. Caller MUST persist the store
    /// to disk and call `self.infra.bump()` after this returns.
    pub fn block_peer(&self, pubkey_hex: &str) {
        if let Some(ref arc) = self.approved {
            if let Ok(mut store) = arc.lock() {
                store.block(pubkey_hex);
            }
        }
    }

    /// Remove an explicit approval for `pubkey_hex`. Caller MUST persist and bump.
    pub fn remove_peer_approval(&self, pubkey_hex: &str) {
        if let Some(ref arc) = self.approved {
            if let Ok(mut store) = arc.lock() {
                store.remove_approval(pubkey_hex);
            }
        }
    }

    /// Remove an explicit block for `pubkey_hex`. Caller MUST persist and bump.
    pub fn remove_peer_block(&self, pubkey_hex: &str) {
        if let Some(ref arc) = self.approved {
            if let Ok(mut store) = arc.lock() {
                store.remove_block(pubkey_hex);
            }
        }
    }

    /// Test constructor.
    #[cfg(test)]
    pub fn for_test() -> Self {
        Self::new(Infra::for_test())
    }

    /// Test constructor with a shared approved-peer store for trust-predicate
    /// tests that exercise the approve/block path.
    #[cfg(test)]
    pub fn for_test_with_approved(store: Arc<Mutex<ApprovedPeerStore>>) -> Self {
        Self::new(Infra::for_test()).with_approved_peers(store)
    }

    /// Seed the outbound-turn slot from a persisted cache loaded at init.
    ///
    /// Called once from `register.rs` after loading the on-disk cache so the
    /// very first projection already includes turns from prior sessions.
    pub fn seed_outbound_turns(&self, turns: Vec<OutboundTurn>) {
        if let Ok(mut slot) = self.outbound_turns.lock() {
            *slot = turns;
        }
    }

    // ── Account switch ────────────────────────────────────────────────────

    /// Clear all per-account social state — the follow-list snapshot, the
    /// cached agent notes, and the outbound turns.  Called from the
    /// identity-change hook in `register.rs` so no cross-account state
    /// survives an A→B switch.
    pub fn clear_for_account_switch(&self) {
        if let Ok(mut s) = self.social_slot.lock() {
            *s = None;
        }
        if let Ok(mut n) = self.agent_notes.lock() {
            n.clear();
        }
        if let Ok(mut o) = self.outbound_turns.lock() {
            o.clear();
        }
    }

    /// Append an outbound turn to the in-memory slot.
    ///
    /// Deduplication (by `event_id`) is the caller's responsibility — the
    /// auto-responder already gates on the responder cache before publishing,
    /// so duplicates should never arrive. This method simply appends without
    /// an additional dedup check to avoid O(N) scans on the hot responder path.
    ///
    /// The caller is responsible for persisting the corresponding
    /// `OutboundTurnCache` to disk. This method ONLY mutates the in-memory
    /// projection slot.
    pub fn record_outbound_turn(&self, turn: OutboundTurn) {
        if let Ok(mut slot) = self.outbound_turns.lock() {
            slot.push(turn);
        }
    }

    // ── Snapshot projections ──────────────────────────────────────────────

    /// Clone the current social snapshot for projection.
    pub fn social_snapshot(&self) -> Option<SocialSnapshot> {
        let ApprovedBlockedSnapshot { approved, blocked, .. } = self.approved_blocked_snapshot();
        let approved_pubkeys: Vec<String> = approved.into_iter().collect();
        let blocked_pubkeys: Vec<String> = blocked.into_iter().collect();
        match self.social_slot.lock().ok().and_then(|s| s.clone()) {
            Some(mut snapshot) => {
                snapshot.approved_pubkeys = approved_pubkeys;
                snapshot.blocked_pubkeys = blocked_pubkeys;
                Some(snapshot)
            }
            None if approved_pubkeys.is_empty() && blocked_pubkeys.is_empty() => None,
            None => Some(SocialSnapshot {
                following: Vec::new(),
                following_count: 0,
                approved_pubkeys,
                blocked_pubkeys,
            }),
        }
    }

    /// Project inbound agent notes + outbound turns into NIP-10-threaded
    /// [`NostrConversationDTO`]s for the `podcast.social` push sidecar.
    ///
    /// ## Grouping algorithm
    ///
    /// Each inbound [`CachedAgentNote`] with a `root_event_id` is bucketed
    /// under that root. Notes without a root are themselves the root (they open
    /// a new thread — `root_event_id = note.id`). Outbound turns carry an
    /// explicit `root_event_id` set by the auto-responder.
    ///
    /// Both sides are merged into `turns`, sorted ascending by `created_at`.
    ///
    /// ## Trust
    ///
    /// The `trusted` field on each conversation is computed live (same
    /// `ActiveFollowSet` predicate as `nostr_conversations_snapshot`), keyed on the
    /// primary counterparty's hex. Fail-closed (D6).
    pub fn nostr_conversations_snapshot(&self) -> Vec<NostrConversationDTO> {
        let notes = match self.agent_notes.lock() {
            Ok(n) => n.clone(),
            Err(_) => return Vec::new(),
        };
        let outbound = match self.outbound_turns.lock() {
            Ok(o) => o.clone(),
            Err(_) => return Vec::new(),
        };

        // Build composed trust predicate + explicit per-peer flag predicate
        // once per projection. Both read the same approved/blocked snapshot.
        let predicate = self.trust_predicate();
        let flags = self.peer_flags_predicate();

        // Keyed by root_event_id. Value: (counterparty_hex, participants, turns).
        let mut threads: HashMap<String, (String, Vec<String>, Vec<NostrConversationTurnDTO>)> =
            HashMap::new();

        // ── Fold inbound notes ────────────────────────────────────────────────
        for note in &notes {
            let root = note
                .root_event_id
                .clone()
                .unwrap_or_else(|| note.id.clone());
            let entry = threads
                .entry(root)
                .or_insert_with(|| (note.author_hex.clone(), Vec::new(), Vec::new()));
            // Participants: accumulate unique hex pubkeys.
            if !entry.1.contains(&note.author_hex) {
                entry.1.push(note.author_hex.clone());
            }
            entry.2.push(NostrConversationTurnDTO {
                event_id: note.id.clone(),
                direction: "inbound".to_string(),
                pubkey_hex: note.author_hex.clone(),
                created_at: note.created_at,
                content: note.content.clone(),
            });
        }

        // ── Fold outbound turns ───────────────────────────────────────────────
        for turn in &outbound {
            let entry = threads
                .entry(turn.root_event_id.clone())
                .or_insert_with(|| (turn.counterparty_hex.clone(), Vec::new(), Vec::new()));
            // Add the counterparty to participants if missing.
            if !entry.1.contains(&turn.counterparty_hex) {
                entry.1.push(turn.counterparty_hex.clone());
            }
            entry.2.push(NostrConversationTurnDTO {
                event_id: turn.event_id.clone(),
                direction: "outbound".to_string(),
                pubkey_hex: turn.counterparty_hex.clone(), // our reply targets them
                created_at: turn.created_at,
                content: turn.content.clone(),
            });
        }

        // ── Assemble DTOs ─────────────────────────────────────────────────────
        let mut conversations: Vec<NostrConversationDTO> = threads
            .into_iter()
            .map(|(root_event_id, (counterparty_hex, participants, mut turns))| {
                // Sort turns chronologically.
                turns.sort_by_key(|t| t.created_at);
                let first_seen = turns.first().map(|t| t.created_at).unwrap_or(0);
                let last_activity = turns.last().map(|t| t.created_at).unwrap_or(0);
                let trusted = predicate(&counterparty_hex);
                let (peer_blocked, peer_approved) = flags(&counterparty_hex);
                NostrConversationDTO {
                    root_event_id,
                    counterparty_hex,
                    participants,
                    turns,
                    trusted,
                    peer_blocked,
                    peer_approved,
                    first_seen,
                    last_activity,
                }
            })
            .collect();

        // Sort conversations newest-first by last_activity.
        conversations.sort_by(|a, b| b.last_activity.cmp(&a.last_activity));
        conversations
    }
}

#[cfg(test)]
#[path = "social_tests_conversations.rs"]
mod tests_conversations;

#[cfg(test)]
#[path = "social_tests_trust.rs"]
mod tests_trust;
