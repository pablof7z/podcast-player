---
type: episode-card
date: 2026-06-10
session: 4243e533-7577-4916-afae-773f1c45b9f2
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/4243e533-7577-4916-afae-773f1c45b9f2.jsonl
salience: root-cause
status: active
subjects:
  - push-loop-staleness-guard
  - snapshot-rev-watermark
  - nmp-core-relay-frames
supersedes: []
related_claims: []
source_lines:
  - 5814-5827
  - 5995-5998
  - 6199-6224
  - 6267-6289
captured_at: 2026-06-12T13:43:48Z
---

# Episode: Stale NMP-core push frames clobber fresh identity snapshots

## Prior State

Push frames from NMP-core were treated as authoritative; any incoming frame unconditionally replaced the current snapshot, including frames built during relay-connect before identity was loaded (carrying null activeAccount and low rev numbers)

## Trigger

Debug logging revealed that stale push frames (rev 1-4, null identity) arrived after a good first-pull (rev 4, non-null identity) and overwrote it. Further diagnosis showed the initial staleness guard had a critical bug: `next.copy(activeAccount = cur.activeAccount)` preserved `next.rev` (stale), so the NEXT stale frame with a higher rev bypassed the guard entirely.

## Decision

A rev-based staleness guard was adopted in the Kotlin push loop: when `cur.activeAccount != null && next.activeAccount == null && next.rev <= cur.rev`, the stale frame's null identity is rejected and `cur.activeAccount` (and critically `cur.rev`) is preserved. The guard must copy BOTH `cur.activeAccount` AND `cur.rev` to prevent subsequent stale frames from bypassing the condition.

## Consequences

- Push frames are no longer blindly authoritative; the snapshot's rev field acts as a monotonically-increasing watermark that stale frames cannot regress
- Any NMP-core frame that nulls out a previously-populated identity at the same or lower rev is silently rejected
- Future push-frame producers must ensure their rev is strictly greater than the current snapshot rev to be accepted

## Open Tail

- Guard only protects activeAccount; other snapshot fields may still be clobbered by stale frames if the same pattern exists

## Evidence

- transcript lines 5814-5827
- transcript lines 5995-5998
- transcript lines 6199-6224
- transcript lines 6267-6289

