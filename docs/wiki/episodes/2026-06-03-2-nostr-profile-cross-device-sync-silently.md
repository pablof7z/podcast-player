---
type: episode-card
date: 2026-06-03
session: 55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1.jsonl
salience: root-cause
status: active
subjects:
  - nostr-profile
  - icloud-sync
  - settings-dispatch
supersedes: []
related_claims: []
source_lines:
  - 971-1013
captured_at: 2026-06-12T13:11:23Z
---

# Episode: Nostr profile cross-device sync silently broken

## Prior State

Nostr profile changes (name, about, picture) were assumed to sync across devices via iCloud KV store. The Swift side dispatched three separate ops: set_nostr_profile_name, set_nostr_profile_about, set_nostr_profile_picture.

## Trigger

M3 settings audit found that Rust's SettingsAction enum only defines the atomic SetNostrProfile { name, about, picture }. With #[serde(tag="op")] and no #[serde(other)], the three split ops failed deserialization and were silently dropped.

## Decision

Replaced the three broken dispatches with a single atomic set_nostr_profile dispatch, gated on any of the three fields changing.

## Consequences

- Nostr profile changes now reach the kernel and propagate via iCloud sync
- Eliminates a deserialization-silent-failure class: any future op-name mismatch will also be invisible unless the Rust enum is checked
- Two orphaned ops flagged in BACKLOG: set_streaming_only (dead plumbing) and set_provider_api_keys (credential-routing gap)

## Open Tail

- set_provider_api_keys credential gap needs separate resolution

## Evidence

- transcript lines 971-1013

