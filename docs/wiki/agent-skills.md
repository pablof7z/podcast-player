---
title: Agent Skills
slug: agent-skills
topic: agent-system
summary: The agent has an opt-in skills system that provides built-in skills, each bundling niche tools and knowledge behind a skill activation gate.
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-12
updated: 2026-06-12
verified: 2026-05-12
compiled-from: conversation
sources:
  - session:9d55e84d-b4cf-4c53-80c2-3cbdd80e54a1
  - session:4be65570-62ca-4bde-8089-764e01ac9804
  - session:0f3f24f7-54de-49f8-b160-a92f735f6a00
  - session:9692d124-a1a0-411c-91f9-9d6ebc0b29b1
  - session:rollout-2026-05-09T14-56-23-019e0c98-8803-7ef0-b7a2-bf0b605a2360
---

# Agent Skills

## Agent Skills System

The agent has an opt-in skills system that provides built-in skills, each bundling niche tools and knowledge behind a skill activation gate. <!-- [^9d55e-1] -->

A `use_skill` meta-tool is always-on and allows the agent to activate a specific skill, appending that skill's manual and tool schemas to the LLM context. Agent prompt skill inventory/filter/cap policy is now managed by the Rust kernel as an AgentContextSnapshot projection, with Swift rendering pre-chosen filtered lists into prompt strings rather than appending a catalog of every registered skill. (Previously: The system prompt ends with a `## Skills` catalog that lists each registered skill, superseded — see nostr-rust-ffi.) Both turn loops (`AgentChatSession+Turns.swift`, `AgentRelayBridge.swift`) intercept the `use_skill` meta-tool in-band to activate skills and append per-skill schemas to the LLM tool list. Tool dispatch defensively rejects a skill-gated tool when the owning skill is not enabled in the session. `enabledSkills: Set<String>` is persisted on the session and in `ChatConversation`, using `decodeIfPresent` fallback so legacy snapshots decode cleanly. Re-activating an already-enabled skill skips re-sending the manual to save context tokens. <!-- [^9d55e-2] -->

## Built-in Skills

The `podcast_generation` skill is a built-in skill providing the agent with knowledge on how to generate podcast chapters associated with an episode and available voices. Its manual covers turn structure → chapter mapping, voice selection, emotion cues, snippet sourcing, and a quality gate. The skill includes the `list_available_voices` tool.

The `youtube_ingestion` skill is skill-gated: the agent must call `use_skill(skill_id: "youtube_ingestion")` to unlock its tools. It uses a BYOK (user-configured) endpoint approach where the user self-hosts a cobalt instance or yt-dlp wrapper and configures the URL in Settings.

<!-- citations: [^9d55e-3] [^4be65-1] [^9692d-2] -->
## Skill Inheritance Scope

Settings UI for skills is out of scope for the current skill inheritance plan. Only TTS/voice tools migrate to skills in this phase; wiki and briefing skill migration is deferred. <!-- [^0f3f2-10] -->

## Agent Capabilities & Access

The embedded agent has access to non-archived episode information, generated wikis, and RAG access using OpenRouter for embedding generation, but archived episodes are excluded from agent prompt context, unplayed counts, and search results. (Previously: The embedded agent has access to all episode information, generated wikis, and RAG access, using OpenRouter for embedding generation, superseded — see inbox-triage.) It uses Perplexity for online research and has tools to manage the UI (e.g., opening an episode at a specific timestamp). OPML import/export is not available as an agent tool (though it may exist as an app UI feature). The agent does not have generate_quiz, generate_flashcards, draft_* social tools, show_creator_funding, or any V4F/value tools. It also does not have export_diagnostics, clear_episode_cache, export_user_data, or test_provider_key tools. <!-- [^rollo-7] -->
