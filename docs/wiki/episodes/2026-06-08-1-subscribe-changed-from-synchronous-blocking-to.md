---
type: episode-card
date: 2026-06-08
session: 8eb3f00f-b245-4f03-80f0-15151d9aba28
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/8eb3f00f-b245-4f03-80f0-15151d9aba28.jsonl
salience: product
status: active
subjects:
  - subscribe-flow
  - optimistic-insert
  - async-http-capability
  - feed-fetch-coordinator
supersedes:
  - 2026-05-28-4-subscribe-from-search-view-only-to
related_claims: []
source_lines:
  - 1-1
  - 141-141
  - 2123-2126
  - 2747-2806
  - 2814-2834
captured_at: 2026-06-12T13:29:22Z
---

# Episode: Subscribe changed from synchronous-blocking to optimistic-instant with async hydration

## Prior State

handle_subscribe ran on the kernel actor thread and synchronously downloaded + parsed the entire RSS feed before inserting the podcast row into the store. The UI polled (up to 30s timeout, 300ms intervals) waiting for the podcast to appear. Perceived latency = full feed fetch time (multiple seconds) with no feedback until completion.

## Trigger

User complaint: 'why does it take so damn long subscribe to a podcast? it always takes multiple seconds -- what is it doing? I would expect subscribing to be basically immediate and for whatever needs to happen to happen in the background (across all platforms, obviously)'

## Decision

Subscribe is now optimistic + asynchronous in the shared Rust kernel (fixes all platforms): (1) handle_subscribe inserts the row + marks it followed synchronously (no network), bumps the snapshot rev so the UI shows the podcast instantly; (2) the feed fetch is dispatched fire-and-forget over a new nmp.http.async.capability; (3) platforms run HTTP off-thread and report back via a new nmp_app_podcast_http_report FFI; (4) FeedFetchCoordinator parses + merges episodes off the actor thread and re-projects. The synchronous HTTP path remains untouched for iTunes/transcript/chapters.

## Consequences

- Subscribe now appears instant across all platforms — the row flips to ✓ immediately, then real metadata + episodes hydrate in the background
- A new async capability contract (nmp.http.async.capability) is established; all platform executors (iOS, Android, TUI) must implement the async route alongside the existing sync route
- On feed-fetch error, the optimistic row persists with zero episodes and no error indicator until the user pull-to-refreshs (surfacing that error is a tracked follow-up)
- The existing synchronous HTTP capability (nmp.http.capability) is unchanged and continues to serve iTunes search, transcripts, chapters, etc.
- The Swift kernelSubscribe poll still exists but resolves on the first tick because the podcast row now appears synchronously

## Open Tail

- Error state surfacing for failed async feed fetches (currently the optimistic row just stays empty with no indication)
- Android runtime verification blocked by pre-existing OpenSSL cross-compilation environment gap
- ios/Podcast/ mirror has no build target and was skipped

## Evidence

- transcript lines 1-1
- transcript lines 141-141
- transcript lines 2123-2126
- transcript lines 2747-2806
- transcript lines 2814-2834

