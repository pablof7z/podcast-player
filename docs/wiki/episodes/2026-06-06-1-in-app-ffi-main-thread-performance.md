---
type: episode-card
date: 2026-06-06
session: 57b63f46-0a23-4efc-b087-0a521300d906
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/57b63f46-0a23-4efc-b087-0a521300d906.jsonl
salience: architecture
status: superseded
subjects:
  - ffi-perf-metrics
  - main-thread-watchdog
  - performance-view
supersedes: []
related_claims: []
source_lines:
  - 1-2
  - 278-290
  - 353-362
  - 1229-1252
captured_at: 2026-06-12T13:20:10Z
---

# Episode: In-app FFI/main-thread performance HUD replaces Instruments-only observability

## Prior State

Performance debugging required Instruments tethered to a Mac. Per-frame timing data (decodeMicros, payloadBytes, callbackReceivedAt) was computed in the C callback but discarded — consumed nowhere. No on-device way existed to identify what was locking the UI.

## Trigger

User reported the iOS app felt sluggish and suspected main-thread blocking via the FFI bridge. Discovery that existing os_signpost intervals only help with a tethered profiler, and that per-frame timing was already being calculated and thrown away.

## Decision

Built Settings → Debug → Performance as an always-available on-device HUD with two complementary instruments: (1) a main-thread stall watchdog (background probe pings main queue ~20×/s; latency IS the stall, catching every UI block regardless of source), and (2) per-operation FFI/main cost stats (count, avg, max, payload bytes) for push-frame decode, main·apply, main·projection, FFI dispatch, and snapshot pull. All off by default; one clock read + defer per site when disabled.

## Consequences

- On-device observability no longer requires Instruments or a Mac tether
- Watchdog already caught a real 267ms launch hang and identified snapshot pull peaking at 14.3ms on the main thread
- Confirmed the merged fast-path guard is holding (main·apply avg 24µs)
- Creates a reusable measurement tool for the concurrent peer effort to move snapshot-pull decode off-main
- FFI traffic quantified at device level: 1.3 MB across 40 frames in 44s idle baseline

## Open Tail

- Empty-library baseline numbers only; real profile at ~3,600-episode scale still needed
- In-app toggle off→on path not visually confirmed under UI automation (1Hz live-refresh drops simulated taps); defaults-init path verified live with 5,500+ samples
- spotlight.indexLibrary running on every accepted frame remains unmeasured as a separate segment

## Evidence

- transcript lines 1-2
- transcript lines 278-290
- transcript lines 353-362
- transcript lines 1229-1252

