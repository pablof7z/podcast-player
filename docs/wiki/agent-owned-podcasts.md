---
title: Agent Owned Podcasts
slug: agent-owned-podcasts
topic: agent-system
summary: Agents can create, update, delete, and list their own named podcasts via dedicated tools (create_podcast, update_podcast, delete_my_podcast, list_my_podcasts, g
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-14
updated: 2026-06-12
verified: 2026-05-14
compiled-from: conversation
sources:
  - session:84c4d49c-d034-4d2e-8e1e-dfd5a4453b2d
  - session:d0447a6c-e8a4-4913-a5bd-cd462c96487a
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
  - session:55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1
  - session:rollout-2026-05-10T10-27-27-019e10c8-ab1d-7523-8825-9bb1a52e6aac
  - session:rollout-2026-05-10T20-45-04-019e12fe-1fe8-7d93-a41f-0cebfa991f0a
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
  - session:rollout-2026-05-25T12-50-00-019e5e8a-9307-7903-9302-dbc867f91c61
  - session:rollout-2026-05-25T12-53-39-019e5e8d-ec64-74f1-a1b1-91055dcab442
---

# Agent Owned Podcasts

## Agent-Owned Podcasts

The podcast create/update/delete lifecycle lives in the Rust kernel via create_podcast, update_podcast, and delete_podcast ops (previously CreateSyntheticPodcast/UpdateOwnedPodcast/DeleteOwnedPodcast). add_episode registers episodes (previously register_synthetic_episode). Both create_podcast and add_episode live in the podcast namespace, not podcast.publish. A podcast is a podcast regardless of source; there is no 'synthetic' distinction, and the PodcastKind enum is deleted from both Rust and Swift. Mutating podcast agent tools require a safety layer with approval, audit, and undo before execution. Each agent-owned podcast has a per-show visibility setting (NostrVisibility: .private or .public) controlling whether NIP-F4 events are published to Nostr. The Podcast model includes an ownerPubkeyHex field identifying agent-owned shows; this field is set to the podcast's own pubkey, not the agent pubkey. The publish_episode tool accepts an episode_id and publishes the episode as a NIP-F4 kind:54 Nostr event, returning the episode's naddr on success. It must surface clear descriptive errors—rather than silently succeed—for conditions including podcast not owned, visibility private, Nostr disabled, or no relay configured. Author claim events must be signed with the agent key after create/update and after delete/private visibility changes. When update_podcast flips visibility from private to public, the owned-podcast kind:54 backfill (PR #397) moved the per-episode publish loop from Swift into the kernel's update_owned handler using per-episode self-enqueue via nmp_app_dispatch_action (D8-compliant, non-blocking) so each episode publishes in its own actor tick and the actor yields between, avoiding a D8 actor-stall from N sequential blocking Blossom uploads (Previously: it serially published all existing episodes as kind:54 events and returned an episodes_published_to_nostr count). Private owned podcasts currently rely on ownerPubkeyHex != nil as the ownership marker; since keys are generated only on first publish, private podcasts may disappear from owned lists or fail update/delete guards unless this is accounted for. create_podcast and update_podcast return nostr_event_id (32-byte hex) and naddr (NIP-19 bech32 addressable event identifier) whenever a show event is published. AgentOwnedPodcastInfo includes nostrEventID: String?, nostrAddr: String?, and episodesPublishedToNostr: Int? fields. The app provides agent tools named list_categories and change_podcast_category wired through AppStateStore.

<!-- citations: [^84c4d-1] [^84c4d-2] [^84c4d-3] [^84c4d-4] [^d0447-2] [^d0447-1] [^14943-2] [^55bed-1] [^rollo-33] [^rollo-38] [^c1691-35] [^rollo-179] [^c1691-85] -->
## NIP-74 Event Structure

Agent-owned podcasts publish via NIP-F4 (kind:10154 for show events and kind:54 for episode events), not NIP-74.

New helper files are added for per-podcast keys and wire constants instead of adding logic to large existing files like `LiveAgentOwnedPodcastManager` and discovery. <!-- [^rollo-169] -->

<!-- citations: [^84c4d-5] [^14943-1] -->
## Blossom Uploads

Audio (mp3), chapter JSON, and transcripts must all be uploaded to Blossom (not just artwork). The default Blossom server is blossom.primal.net (Previously: blossom.band). Settings.swift includes a configurable blossomServerURL field defaulting to 'https://blossom.primal.net'. BlossomUploader uses context-aware auth content based on MIME type (e.g., 'Upload podcast audio', 'Upload transcript') instead of hardcoded 'Upload profile photo'. <!-- [^84c4d-6] -->

## Content Serialization

Agent-generated chapter data is serialized from inline Episode.Chapter arrays to Podcasting 2.0 chapters JSON format (version 1.2.0) for Blossom upload. Agent-generated transcripts are serialized to WebVTT format from TranscriptStore segments for Blossom upload. <!-- [^84c4d-7] -->

## Image Generation

Image generation uses OpenRouter's /v1/images/generations endpoint with the existing OpenRouter key, defaulting to openai/dall-e-3. Settings.swift includes configurable fields: imageGenerationModel (default 'openai/dall-e-3') and imageGenerationModelName. <!-- [^84c4d-8] -->

## UI Implementation Details

AgentPodcastsView uses CachedAsyncImage (not PodcastArtworkView which doesn't exist) and AppTheme.Typography.caption (not .footnote which doesn't exist). Color.accentColor is used instead of AppTheme.Tint.accent (which does not exist). <!-- [^84c4d-9] -->
