---
type: episode-card
date: 2026-05-14
session: 1eb0c519-6723-489e-b777-71997fd7e216
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/1eb0c519-6723-489e-b777-71997fd7e216.jsonl
salience: product
status: active
subjects:
  - sidebar-animation
  - root-view-layout
supersedes: []
related_claims: []
source_lines:
  - 1494-1537
captured_at: 2026-06-12T12:23:41Z
---

# Episode: Sidebar animation changed from overlay to push-style

## Prior State

Sidebar overlayed content with a simple fade-in dark backdrop; main content stayed in place underneath.

## Trigger

Design intent for Twitter-style push effect where main content slides right; `.clipped()` on the ZStack caused white strips at safe-area edges.

## Decision

Adopted push-style animation: main content offsets by `sidebarWidth` (300pt) to the right, sidebar slides in from left simultaneously. Removed `.clipped()` to fix white-strip rendering bug. Reverted to conditional rendering of sidebar (not always-rendered off-screen) to avoid unnecessary overhead.

## Consequences

- Sidebar pushes content right rather than overlaying it
- No `.clipped()` needed — avoids safe-area clipping artifacts
- Sidebar only in view hierarchy when open (conditional rendering)
- Dim overlay taps dismiss sidebar with spring animation

## Open Tail

*(none)*

## Evidence

- transcript lines 1494-1537

