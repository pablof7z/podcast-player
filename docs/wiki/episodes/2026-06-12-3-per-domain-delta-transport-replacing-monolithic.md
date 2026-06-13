---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - domain-projections
  - snapshot-transport
  - kernel-shell-contract
supersedes:
  - 2026-06-12-3-monolithic-full-library-serialization-replaced-by
related_claims: []
source_lines:
  - 30-57
  - 4640-4650
  - 4875-4881
captured_at: 2026-06-12T15:07:20Z
---

# Episode: Per-domain delta transport replacing monolithic snapshot

## Prior State

Every kernel command dispatch triggered `emit_now` → `make_update` → `build_snapshot_payload`, re-serializing the entire library (all podcasts × all episodes) to JSON on the actor thread. A playback tick applied ~3.9MB of JSON through a full pull decode (~35ms).

## Trigger

The profiling root cause (57% CPU in full-library serialization) plus the discovery that the push path was dead on both shells.

## Decision

Per-domain typed sidecars: the kernel emits 7 domain envelopes (library, playback, downloads, settings, identity, widget, misc) each with its own rev counter. Only the mutated domain(s) are serialized per tick. Shells merge only present domains into a composite, preserving absent domains unchanged. Tombstone envelopes (`{"rev":N,"library":null}`) signal domain-empty.

## Consequences

- A playback tick now applies ~1KB instead of ~3.9MB (10x improvement)
- Per-domain rev tracking enables independent drop-guard monotonicity per domain
- Tombstone contract (#402) allows the kernel to signal 'all podcasts unsubscribed' or 'signed out' without ambiguity
- The composite-merge model (only replace present domains, never clear absent ones) prevents partial-push blanking
- Both shells (iOS #403, Android #404) now consume the same kernel contract

## Open Tail

*(none)*

## Evidence

- transcript lines 30-57
- transcript lines 4640-4650
- transcript lines 4875-4881

