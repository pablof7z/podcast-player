---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - social-graph
  - follow-list-projection
  - reactive-push-model
supersedes: []
related_claims: []
source_lines:
  - 6079-6086
  - 6291-6364
  - 6479-6525
captured_at: 2026-06-12T22:28:01Z
---

# Episode: Social graph: one-shot pull fetch replaced by reactive FollowListProjection

## Prior State

Social graph used a one-shot, 8s-timeout, hardcoded wss://relay.primal.net pull fetch (fetch_relay_events_async) that subscribed-then-parsed p-tags and batch-fetched kind:0 profiles — a polling model with no reactivity

## Trigger

NMP v0.6.0 shipped nmp-nip02 with FollowListProjection (a KernelEventObserver riding the standing account_profile_interest kind:0+3+10002 subscription) and ActiveFollowSet (a live Arc<dyn Fn(&str)->bool> membership predicate)

## Decision

Replace the entire pull path with the reactive model: register FollowListProjection via the push seam (nmp_app_register_snapshot_projection), hydrate kind:0 profiles from the same store, and wire ActiveFollowSet as the trust predicate; delete fetch_relay_events_async, the hardcoded RELAY_URL constant, the runtime/identity parameters, and the entire relay-subscribe-then-parse body; FetchContacts becomes a refresh trigger returning refreshed/pending

## Consequences

- No polling, no timeout, no hardcoded relay — follows populate reactively via standing subscription
- relay.rs module in the app crate is now orphaned (only callers were the deleted pull path)
- Account-switch resets the follow set (notify_account_changed) but does NOT yet clear social_slot or agent_notes — a stale-cross-account bleed identified in review
- Reactivity proven in headless scenario: following populates without any FetchContacts dispatch

## Open Tail

- Clear social_slot and agent_notes on account switch (identified in #419 review)
- Delete orphaned relay.rs module from app crate
- Conversations projection (grouping agent_notes by root_event_id into NostrConversation) deferred to next cycle as a separate PR

## Evidence

- transcript lines 6079-6086
- transcript lines 6291-6364
- transcript lines 6479-6525

