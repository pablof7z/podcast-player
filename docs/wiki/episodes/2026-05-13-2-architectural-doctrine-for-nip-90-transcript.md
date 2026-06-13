---
type: episode-card
date: 2026-05-13
session: 9f2d26f1-3e71-46b0-83d8-cc9895be3a8e
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/9f2d26f1-3e71-46b0-83d8-cc9895be3a8e.jsonl
salience: architecture
status: active
subjects:
  - nip-90-transcription
  - transcription-pipeline
  - nostr-integration
supersedes:
  - 2026-05-13-1-nip-90-transcription-publishing-is-entirely
related_claims: []
source_lines:
  - 47-69
captured_at: 2026-06-12T12:09:31Z
---

# Episode: Architectural Doctrine for NIP-90 Transcript Publish/Consume Hooks

## Prior State

No architectural plan existed for where NIP-90 transcript publishing and consuming would integrate into the existing transcription pipeline.

## Trigger

Opus scoping exercise mapped the codebase to identify exact insertion points and reusable patterns.

## Decision

Publish hook: TranscriptIngestService.swift:325-329, right after store.save(transcript), using the existing fire-and-forget Task pattern (mirroring AIChapterCompiler/WikiTriggers). Consume hook: TranscriptIngestService.swift:194-197, inserted as Path A.5 between publisher RSS fetch fall-through and STT fallback. Sign+publish: copy NostrCommentService.publish pattern (reads Settings.nostrRelayURL, handles NIP-42 AUTH). Do NOT use FeedbackRelayClient (hardcoded to tenex.chat). Stable cross-instance ID: reuse CommentTarget.nip73Identifier pattern. Subscription: copy NostrCommentService session model, not NostrRelayService.

## Consequences

- Publishing must gate on UserIdentityStore.hasIdentity to avoid cold-launch disposable-key race
- Settings.nostrRelayURL is single-relay only — V1 publishes to one relay
- Synthetic GUIDs (synth::...) must be filtered from nip73Identifier just as comments do

## Open Tail

- Combined vs separate blocklist (nostrBlockedPubkeys reused vs new nostrBlockedTranscriptPublishers)
- Inline event vs Blossom upload for payload strategy

## Evidence

- transcript lines 47-69

