---
type: episode-card
date: 2026-05-15
session: 8c3708b9-22f2-404d-8534-c476e0cfcf75
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/8c3708b9-22f2-404d-8534-c476e0cfcf75.jsonl
salience: architecture
status: active
subjects:
  - nostr-comment-service
  - ndk-subscribe
  - polling-elimination
supersedes: []
related_claims: []
source_lines:
  - 3355-3398
captured_at: 2026-06-12T12:37:22Z
---

# Episode: Last raw-WebSocket subscribe path replaced by NDK subscription

## Prior State

NostrCommentService.subscribe used raw WebSocket (Task.sleep reconnect loop) for NIP-22 comment subscriptions — the only remaining polling pattern after the read-path agent migrated the other services.

## Trigger

Post-merge cleanup identified NostrCommentService.swift:168 as the only true polling loop left in the Nostr codebase. The write-path agent had intentionally deferred it (out-of-scope for write-path migration).

## Decision

Migrated NostrCommentService.subscribe to ndk.subscribe with closeOnEose, eliminating the last raw WebSocket path. Removed dead sendJSON helper and unthrown PublishError cases (.encodingFailed, .relayAckTimeout).

## Consequences

- Zero URLSessionWebSocketTask references remain in Nostr service code
- All subscription/reconnect logic is now NDK's responsibility
- NostrCommentService is a mixed file (NDK subscribe, NDK publish) — fully migrated
- Final polling audit confirms all remaining Task.sleep calls are legitimate withTaskGroup deadline races in one-shot fetchers

## Open Tail

*(none)*

## Evidence

- transcript lines 3355-3398

