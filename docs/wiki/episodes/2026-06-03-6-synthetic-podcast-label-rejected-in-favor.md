---
type: episode-card
date: 2026-06-03
session: 55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1.jsonl
salience: reversal
status: active
subjects:
  - podcast-store
  - feed-url
  - podcast-kind
  - kernel-model
supersedes: []
related_claims: []
source_lines:
  []
captured_at: 2026-06-12T13:11:23Z
---

# Episode: Synthetic podcast label rejected in favor of uniform podcast store

## Prior State

Agent-generated and Nostr-native podcasts were labeled 'synthetic' with a PodcastKind enum. They used a separate Swift-side workaround (upsertPodcast, SyntheticBackfill) that got wiped on snapshot push because the kernel only knew how to ingest RSS podcasts. The backlog items were framed as 'synthetic-podcast-row-kernel-seed' and 'synthetic-podcast-episodes-kernel-seed'.

## Trigger

User explicitly rejected the 'synthetic' framing: 'it shouldn't be synthetic, just because its not coming from rss it should be real anyway.'

## Decision

Collapsed the synthetic workaround into uniform first-class podcast support. Deleted PodcastKind from Rust and Swift. Renamed create_synthetic_podcast → create_podcast and register_synthetic_episode → add_episode, moving both from podcast.publish to podcast namespace. Deleted Podcast.Kind, SyntheticBackfill, and upsertEpisode. Migrated four Swift call-sites to transient in-memory + kernel dispatch.

## Consequences

- A podcast is a podcast — feed_url is just an optional field, not what makes something real
- No more snapshot-push wipe of agent-generated content because it's now in the kernel store
- SubscriptionService.ensurePodcast retained as the one synchronous-read-back caller that can't be satisfied by fire-and-forget dispatch — flagged as a separate follow-up
- 53 files changed, 12 new tests covering serde wire round-trip and file-vs-http store branches

## Open Tail

- ensurePodcast synchronous-read-back migration is a separate follow-up
- NMP v0.2.4 peer work may conflict on host_op_publish.rs and Cargo.toml

## Evidence

*(no verified line ranges)*

