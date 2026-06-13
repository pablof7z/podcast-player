---
type: episode-card
date: 2026-05-26
session: 14943b9b-5bf3-4317-bc44-298a773bc75e
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/14943b9b-5bf3-4317-bc44-298a773bc75e.jsonl
salience: reversal
status: active
subjects:
  - performance-methodology
  - empirical-baseline
supersedes: []
related_claims: []
source_lines:
  - 69335-69378
captured_at: 2026-06-12T12:50:20Z
---

# Episode: Empirical measurement mandate reverses static-analysis optimization approach

## Prior State

Seven performance PRs (#218-#224, #225-#227) were implemented based on static code analysis. Measurements were taken on an empty library (0 episodes, 0 downloads), yielding 0ms numbers, then used to justify optimizations.

## Trigger

User explicitly caught that all measurements were on a useless empty dataset and demanded: 'didn't I say that all improvements had to be done based on empirical measurements? then what the fuck did you do? how do you know you optimized anything?'

## Decision

All performance optimization work must be based on empirical measurements from a populated library (3,615 episodes, real playback scenarios) before implementing fixes. A pre-fix branch must be measured against real data before any optimization PR is merged.

## Consequences

- Discovered that libraryMetaHash fires at 0.58Hz (not assumed 4Hz) and runs off-main — less urgent than assumed
- Discovered triageCounts never fires on any tested flow — already cached effectively
- Discovered the real remaining bottleneck: 15-18ms wasted on no-op applyKernelState ticks
- All future perf work requires signposted measurements against real data, not code-reading claims

## Open Tail

- Real-world Instruments trace on a physical device with populated library still not captured

## Evidence

- transcript lines 69335-69378

