---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - push-path
  - ios-bridge
  - android-bridge
  - nmp-v0.3.0-regression
supersedes:
  - 2026-06-12-2-push-pipeline-dead-on-both-shells
related_claims: []
source_lines:
  - 4606-4626
  - 4794-4806
  - 4833-4838
captured_at: 2026-06-12T14:47:13Z
---

# Episode: Push path was dead on both shells since v0.3.0

## Prior State

The reactive push projection was assumed to be functional on both platforms. iOS logged 'snapshot frame missing podcast.snapshot projection' on every frame and fell back to 100% pull-driven operation. Android's `decodeEnvelope` decoded the slim `v` as a full `PodcastSnapshot`, wiping the library on every emit (the empty-clobber bug).

## Trigger

Implementing the iOS per-domain consumption revealed that `PodcastHandle.decode(pointer:)` required `v.projections["podcast.snapshot"]`, which NMP v0.3.0 stopped encoding (#396 deleted the registration). The Android twin revealed that every kernel emit was blanking the UI.

## Decision

Rebuild the push consumption path on both platforms: iOS now consumes `PodcastDomainFrames` with per-domain observables + composite merge + rev-monotonic drop guards (#403); Android now uses `decodeDomainFrames` + `mergeFrames` with per-domain `@SerialName` mapping, keeping the cold-start pull as fallback (#404).

## Consequences

- The 'performance optimization' was actually a critical reactivity fix — both shells were running entirely in pull mode
- Android empty-clobber bug (every kernel emit blanking the UI) is fully removed
- Both shells now receive real-time domain deltas instead of polling

## Open Tail

*(none)*

## Evidence

- transcript lines 4606-4626
- transcript lines 4794-4806
- transcript lines 4833-4838

