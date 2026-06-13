---
type: research-record
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
source_lines: 6479-6525
agent_attribution: a6765bd27bba84659
has_preregistered_criteria: true
has_method: true
has_structured_report: true
characterization: "Structured investigation of social graph trust-gate PR #419; verdict REQUEST-CHANGES — trusted field frozen at receipt-time instead of live-at-projection, account-switch leak leaves stale social_slot/agent_notes, behavioral trust test missing"
captured_at: 2026-06-12T22:53:55Z
---

Structured investigation of social graph trust-gate PR #419; verdict REQUEST-CHANGES — trusted field frozen at receipt-time instead of live-at-projection, account-switch leak leaves stale social_slot/agent_notes, behavioral trust test missing

---

User: [Agent task result: Agent "Opus review: social graph trust gate #419" completed]
I now have full confirmation. Note the dedup at the bottom: `if !cache.iter().any(|n| n.id == note.id)` — a note already in cache is NOT re-inserted, so even a re-delivered kind:1 won't refresh a stale `trusted`. This cements the frozen-stamp semantics: once a note is in the cache with `trusted=false`, it stays false forever for that note id, regardless of subsequent follows.

I have everything needed for a decisive verdict.

---

## VERDICT: REQUEST-CHANGES

The reactive plumbing is well-built, but the trust-gate semantics are wrong for a trust-gate's purpose, and the one test that would have caught it was deliberately stubbed to structural-only. This PR is the prerequisite for the agent-responder + conversations work, so the trust semantics must be right before it lands.

### 1. THE TRUST-GATE TIMING NUANCE (the crux) — `trusted` is FROZEN-AT-RECEIPT, and that is incorrect

Definitive answer: **`trusted` is a frozen receipt-time stamp, not re-evaluated at projection.**

- It is computed once in the kind:1 receipt handler: `agent_note_handler.rs:240-244` — `let trusted = self.follow_set.as_ref().map(|fs| fs.predicate()(&event.author)).unwrap_or(false);` — and baked into the `AgentNoteSummary` written to the cache (`:254`).
- The projection reads it back verbatim: `state/social.rs:75-81` `agent_notes_snapshot()` just `.clone()`s the cached `Vec<AgentNoteSummary>`; `ffi/snapshot_domain_projections.rs:178` emits `"agent_notes": update.agent_notes` unchanged. No recomputation against the live `ActiveFollowSet` anywhere on the projection path.
- Worse, the receipt handler dedups by id (`agent_note_handler.rs:258` `if !cache.iter().any(|n| n.id == note.id)`), so a re-delivered kind:1 will NOT refresh the stamp either. A note that arrived `trusted=false` stays false for the life of the process.

Consequence (exactly the sequence the brief posited): note from X arrives at T1 (X not followed → `trusted=false`) → user follows X at T2 → X's existing note stays `trusted=false` forever (until X authors a brand-new note). The follow set is the source of truth, but notes carry stale trust. For a gate feeding an agent-responder/approval surface, this is the wrong default — it should be live-at-projection.

Note also the registration-ordering argument (`ActiveFollowSet` before `AgentNotesObserver`, register.rs:309/335) only guarantees correctness for kind:3-then-kind:1 *within the same delivery batch*. It does nothing for the follow-after-note case, which is the common one. If trust were re-evaluated at projection, the ordering wouldn't matter at all — which tells you the ordering is a band-aid over the wrong seam.

**Minimal fix:** stop stamping `trusted` at receipt. Store the note untrusted/neutral, and compute `trusted` in the social projection builder (`agent_notes_snapshot()` / the snapshot assembly) by applying `ActiveFollowSet::predicate()` to each note's author hex at build time. The `ActiveFollowSet` Arc is already shared and live; the projection just needs a clone of it. That makes follow/unfollow immediately reflect on all existing notes and removes the registration-order dependency. (Keep the npub on the row, but also retain author hex — currently only `author_npub` is stored, so the projection builder would need the hex to feed the predicate; either store `author_hex` on the summary or decode the npub back.)

### 2. Reactive population — correct; account-switch reset — INCOMPLETE (gap)

- Reactive population is correct: `FollowListObserver::on_kernel_event` (social_handler.rs) delegates to upstream `FollowListProjection`, then materializes `SocialSnapshot` into `social_slot` on every kind:3. The scenario empirically proves kind:3 arrives via the standing `account_profile_interest` sub with NO `FetchContacts` dispatch (social.rs reactivity assertion, 20s wait). Upstream confirms `account_profile_interest` = kind:0+3+10002 (nmp-nip02 projection.rs:21; chirp register.rs:377; NmpCore.h:562). No separate subscription needed — confirmed.
- Account-switch reset is only HALF done. The identity-change hook (register.rs:309-312) calls `active_follow_set.notify_account_changed()`, which resets the follow set and re-seeds self (verified in upstream active_follow_set.rs:223-246). But nothing resets `social_slot` or `agent_notes` on account change:
  - `social_slot` is a `Slot<_, Session>` (state/social.rs:41) and `Session` = process-lifetime, NOT cleared on switch. So after switching A→B, the Social tab keeps showing **A's `following` list** until B's first kind:3 push arrives (a stale-follows window). The upstream `FollowListProjection::snapshot()` is itself account-correct (keys by live `active_pubkey`), but the app-level `social_slot` is a materialized copy that no one invalidates.
  - `agent_notes` likewise is never cleared on switch (grep for clear/reset on identity change returns nothing) — so A's notes, carrying A's frozen trust stamps, bleed into B's session. Combined with #1, B could see a note stamped `trusted=true` from A's follow graph.

**Fix:** in the same identity-change hook, also clear `social_slot` (set to `None`) and `agent_notes` (clear the Vec) so no cross-account state survives a switch.

### 3. Deleted pull-path cleanliness — clean, one newly-orphaned module

- `fetch_relay_events_async`, `RELAY_URL`, and the `runtime`/`identity` params are removed; the sole call site (`podcast_action_dispatch.rs:135-141`) is updated; `handle_fetch_contacts` is now a sensible refresh trigger returning `refreshed`/`pending`. Good.
- One side effect: on `main`, social_handler.rs:154 was the **only** app-side caller of `crate::relay::subscribe_until_eose`. This PR removes it, leaving `pub(crate) mod relay` (lib.rs:74) fully orphaned in the app crate (the remaining `subscribe_until_eose` hits are the separate headless test harness `relay_client.rs`/`capability_host.rs`). It compiles clean because the fns are `pub`, but it's now dead code. Minor — delete `relay.rs` + the `mod relay` line, or note as follow-up.

### 4. Tests + hygiene

- Reactivity is genuinely proven (following populates with no FetchContacts; asserts both fiatjaf+jb55 npubs present; asserts `FetchContacts`→`refreshed`/`pending`). Good.
- The trust test is **structural only** and self-admittedly so (social.rs: "this assertion is currently structural: after follow list lands, we verify the trust-gate wiring compiled and the `trusted` field exists"). It only does `let _ = note.trusted;`. There is NO test where following an author flips an existing note's `trusted`, and none asserting `trusted==true` for a followed author. This is exactly the test that would have caught the #1 frozen-stamp bug. A unit test driving the observers directly (no relay) can prove the correct live semantics: inject kind:1 from X (assert trusted=false), inject active-account kind:3 following X, rebuild the projection, assert X's existing note is now trusted=true. With the current frozen design that test fails — which is the point.
- Hygiene otherwise fine: `nmp-nip02` explicit dep at the same `4fdcb52d` rev (D11 single-door), no nmp-core change, the diff is well under the 500-LOC ceiling, no polling/timeout pull remains, BACKLOG updated. whats-new.json touched (+6) but no golden 3789 file is in this diff (social was None in the golden handle, so byte-identity is plausible — but it isn't exercised/asserted by this PR's diff, so I can't positively confirm the golden claim from the diff alone; worth a CI check).

### Bottom line
Re-point `trusted` from receipt-time to projection-time against the live `ActiveFollowSet` (#1), clear `social_slot` + `agent_notes` on account switch (#2), and add the behavioral trust test that flips an existing note on follow (#4). The reactive FollowList wiring, pull-path deletion, and dep hygiene are solid and can stay as-is. Until #1 is fixed, the trust gate reports stale trust, which is unsafe for the downstream agent-responder/approval surface this PR is meant to unblock.
