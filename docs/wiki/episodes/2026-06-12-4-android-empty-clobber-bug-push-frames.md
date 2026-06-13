---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - android-bridge
  - decode-envelope
  - clobber-bug
supersedes: []
related_claims: []
source_lines:
  - 4833-4837
  - 4873-4888
captured_at: 2026-06-12T15:07:20Z
---

# Episode: Android empty-clobber bug — push frames wiping UI state

## Prior State

Android's `decodeEnvelope` was assumed to correctly parse push frames and update UI state incrementally.

## Trigger

The #404 review revealed that `decodeEnvelope` was decoding the slim `v` (which only contains `rev` + per-domain projections) as a full `PodcastSnapshot`, overwriting the entire UI state with empty/null fields on every kernel emit. This was a real user-visible bug: every push frame blanked the library.

## Decision

Delete the entire `decodeEnvelope` + `SnapshotEnvelope` block from `PodcastSnapshot.kt` and replace it with `decodeDomainFrames` → `mergeFrames` which only overwrites present domain slices, leaving absent domains untouched. `snapshot = merged` only assigned when `anyAccepted == true`.

## Consequences

- The clobber bug is fully removed — there is no remaining path where a push frame blanks the library without an explicit library tombstone
- Cold-start pull remains intact as the full-snapshot decoder path
- The old `decodeEnvelope` code is deleted (not narrowed), preventing any future regression

## Open Tail

*(none)*

## Evidence

- transcript lines 4833-4837
- transcript lines 4873-4888

