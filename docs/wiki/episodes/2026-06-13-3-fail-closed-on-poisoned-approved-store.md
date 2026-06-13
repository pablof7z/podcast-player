---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - trust-predicate
  - fail-closed-security
supersedes: []
related_claims: []
source_lines:
  - 8313-8322
  - 8348-8358
captured_at: 2026-06-13T03:49:37Z
---

# Episode: Fail-closed on poisoned approved-store mutex

## Prior State

The trust predicate and responder gate failed open on a poisoned approved-store mutex — lock().unwrap_or_default() returned empty sets, which dropped the blocklist, making a blocked+followed peer become trusted.

## Trigger

Opus review identified the fail-open behavior as a security gap: a poisoned lock should deny trust, not grant it.

## Decision

Fail closed: on lock().is_err(), set fail_closed = true. The returned predicate returns false for every pubkey (cannot prove a peer is not blocked → deny everyone). The responder gate also folds this fail_closed flag, so a poisoned lock never auto-replies.

## Consequences

- Poisoned mutex is now a denial-of-safety (auto-reply stops, conversations show untrusted) rather than a safety bypass
- New test trust_predicate_fails_closed_on_poisoned_approved_lock proves a followed peer becomes untrusted when the lock is poisoned

## Open Tail

*(none)*

## Evidence

- transcript lines 8313-8322
- transcript lines 8348-8358

