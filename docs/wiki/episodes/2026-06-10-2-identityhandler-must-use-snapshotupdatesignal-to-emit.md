---
type: episode-card
date: 2026-06-10
session: 4243e533-7577-4916-afae-773f1c45b9f2
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/4243e533-7577-4916-afae-773f1c45b9f2.jsonl
salience: architecture
status: active
subjects:
  - identity-handler-signal
  - snapshot-update-signal
  - mark-changed-since-emit
supersedes: []
related_claims: []
source_lines:
  - 5296-5323
  - 6129-6158
  - 6160-6169
captured_at: 2026-06-12T13:43:48Z
---

# Episode: IdentityHandler must use SnapshotUpdateSignal to emit fresh push frame after mutations

## Prior State

IdentityHandler used `self.rev.fetch_add(1, Ordering::Relaxed)` directly, which only incremented the shared rev counter but did NOT send `ActorCommand::MarkChangedSinceEmit` to NMP-core. This meant identity mutations (Generate, ImportNsec, SignOut) bumped the rev number but never caused NMP-core to re-run the snapshot projection and emit a fresh push frame to the UI.

## Trigger

After calling Generate, the explicit snapshot pull returned null identity despite rev incrementing (rev 2→3), confirming the actor had not yet processed the action; and even after it did, no push frame with updated identity was emitted because `MarkChangedSinceEmit` was never sent.

## Decision

IdentityHandler now holds an optional `SnapshotUpdateSignal` and delegates all rev bumps to `signal.bump()`, which atomically increments the rev counter AND sends `MarkChangedSinceEmit` to the NMP-core actor. The signal is wired through PodcastHostOpHandler construction.

## Consequences

- All identity mutations now trigger a fresh NMP-core push frame with updated identity data
- The `onSnapshotPull` explicit-pull mechanism in IdentityScreen is still needed as a synchronous fallback for immediate UI response after Generate
- Other handlers that mutate shared state should use the same SnapshotUpdateSignal pattern instead of raw rev bumps

## Open Tail

*(none)*

## Evidence

- transcript lines 5296-5323
- transcript lines 6129-6158
- transcript lines 6160-6169

