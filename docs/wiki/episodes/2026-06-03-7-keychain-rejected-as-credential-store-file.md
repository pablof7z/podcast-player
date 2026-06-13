---
type: episode-card
date: 2026-06-03
session: 55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1.jsonl
salience: architecture
status: active
subjects:
  - keychain
  - credential-store
  - podcast-keys
supersedes: []
related_claims: []
source_lines:
  - 725-740
captured_at: 2026-06-12T13:11:23Z
---

# Episode: Keychain rejected as credential store; file-based keys adopted

## Prior State

PodcastKeysKeychainMigration synced the Rust kernel's podcast-keys.json (written every session) into the iOS Keychain. A peer agent had recently built the Rust feeder for this (WIP-62).

## Trigger

Agent deleting legacy migration infrastructure identified PodcastKeysKeychainMigration as active code, not dead, and asked for confirmation. User's directive: 'no Keychain, keys stay in the file.'

## Decision

Deleted PodcastKeysKeychainMigration.swift, its KernelBridge call site, and its test file. podcast-keys.json is now the sole source of truth; no Keychain sync.

## Consequences

- Credential storage is file-only — no Keychain dependency for podcast keys
- Simplifies the credential path: one store, one write path, no sync layer
- Breaks any iCloud Keychain propagation that relied on this bridge

## Open Tail

*(none)*

## Evidence

- transcript lines 725-740

