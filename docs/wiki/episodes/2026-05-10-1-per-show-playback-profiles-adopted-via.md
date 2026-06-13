---
type: episode-card
date: 2026-05-10
session: c6722edd-ee95-4534-9e81-9bb6b5dc60d6
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c6722edd-ee95-4534-9e81-9bb6b5dc60d6.jsonl
salience: architecture
status: active
subjects:
  - show-playback-profile
  - podcast-subscription
  - default-playback-rate-orphanship
supersedes: []
related_claims: []
source_lines:
  - 3214-3297
captured_at: 2026-06-12T11:50:37Z
---

# Episode: Per-show playback profiles adopted via orphan field migration

## Prior State

`PodcastSubscription.defaultPlaybackRate: Double?` existed in user data but was never read by any code — a dead/orphan field with no effect on playback

## Trigger

User directive to create per-show playback settings; planning agent discovered the orphan field and proposed migrating it into a new nested struct

## Decision

Create `ShowPlaybackProfile` as a nested optional struct on `PodcastSubscription`, migrating the orphan `defaultPlaybackRate` into `profile.speed` via `init(from:)` Codable migration. All fields optional with `Settings` fallbacks. Persistence is free (same JSON-on-disk path).

## Consequences

- Legacy users with `defaultPlaybackRate` set will suddenly have it apply on episode load — a behavior change surfaced as a whats-new entry
- Profile starts at 2 fields (`speed`, `autoPlayNext`) in commit 1, grows to 4 fields in commit 5 — additive optionals ensure forward-compat Codable migration
- `SubscriptionRefreshService` wholesale-replaces subscriptions on feed poll — must verify it preserves `playbackProfile` via read-modify-write or the user's saved profile dies on refresh

## Open Tail

- iCloud sync of per-show profiles is out of scope — separate design exercise if desired

## Evidence

- transcript lines 3214-3297

