---
type: episode-card
date: 2026-06-04
session: e1ab0629-64bc-4383-bd22-c0843ca16a99
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/e1ab0629-64bc-4383-bd22-c0843ca16a99.jsonl
salience: product
status: active
subjects:
  - strip-html-cache
  - snapshot-rebuild-hotpath
supersedes: []
related_claims: []
source_lines:
  - 6133-6135
captured_at: 2026-06-12T13:15:22Z
---

# Episode: Per-episode strip_html memoization in snapshot rebuild

## Prior State

build_podcast_update re-stripped HTML from all ~3,600 episode descriptions on every snapshot rebuild (every rev bump, including per-tick during playback). Descriptions are immutable; the work was pure waste repeated thousands of times per second.

## Trigger

Same performance investigation that identified the rev-bump hotpath; HTML stripping appeared in the per-tick rebuild profile.

## Decision

Content-hash keyed bounded cache on the kernel handle (clean_html). Immutable descriptions are stripped once and reused across rebuilds.

## Consequences

- Per-episode HTML cleaning cost drops from O(N) per rebuild to O(1) cache hit after first strip
- Behaviorally identical output — same cleaned text, just memoized
- Cache is bounded to prevent unbounded memory growth

## Open Tail

*(none)*

## Evidence

- transcript lines 6133-6135

