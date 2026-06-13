---
type: episode-card
date: 2026-06-09
session: 04b5f843-fdbe-4aa1-ae41-6770eac82957
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/04b5f843-fdbe-4aa1-ae41-6770eac82957.jsonl
salience: architecture
status: active
subjects:
  - feedback-subsystem
  - nip-10
  - kernel-projection
  - d0-d5-doctrine
supersedes: []
related_claims: []
source_lines:
  - 2379-2884
captured_at: 2026-06-12T13:40:38Z
---

# Episode: Feedback thread Nostr reduction moved from Swift shell to kernel projection

## Prior State

Kernel emitted raw SignedNostrEvent JSON as `feedback_events`; Swift's FeedbackStore.buildThreads performed all Nostr reduction: kind:513/kind:1 filtering, newest-wins kind:513 supersession, NIP-10 root/reply grouping, project-coordinate filtering, and FeedbackMetadata tag parsing

## Trigger

Issue #354 — NMP-conformance scan found that raw Nostr event reduction in the shell violates D0/D5 doctrine; the kernel should emit a typed, screen-shaped projection (as it already does for podcast.snapshot)

## Decision

New Rust `feedback_threads` module reduces raw events into typed FeedbackThreadProjection/FeedbackReplyProjection/FeedbackMetadataProjection structs; kernel projects `feedback_threads` alongside the existing `feedback_events`; Swift FeedbackStore renders the projection and the buildThreads reducer is deleted; SignedNostrEvent's feedback tag-parsing extension is removed

## Consequences

- Shell no longer parses NIP-10 tags, does kind branching, or performs event-kind supersession
- FeedbackThread and FeedbackReply models now init from typed DTOs instead of raw Nostr events
- FeedbackCategory.from(tags:) replaced with init(tagValue:) — Nostr tag structure removed from Swift
- feedback_events projection is now only used for the loading-check (candidate for future removal)
- 8 Rust unit tests port the exact Swift reduction scenarios, making NIP-10 behavior spec-verifiable

## Open Tail

- E2E feedback thread rendering cannot be verified in sim (no relay feedback data); requires real relay events to confirm correctness
- feedback_events could be dropped once loading-check uses a dedicated projection field
- FeedbackRelayClient constants may now be dead

## Evidence

- transcript lines 2379-2884

