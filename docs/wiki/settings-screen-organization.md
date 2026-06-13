---
title: Settings Screen Organization
slug: settings-screen-organization
topic: ui-components
summary: Settings root groups sections as Account (with Identity), Library (with Subscriptions, Categories), Listening (with Playback, Downloads), Intelligence (with Age
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-10
updated: 2026-06-12
verified: 2026-05-10
compiled-from: conversation
sources:
  - session:rollout-2026-05-10T20-50-50-019e1303-6619-7020-b335-29bdce14a986
  - session:rollout-2026-05-17T17-57-58-019e3671-a863-7ab1-a96d-6ceb8b541971
  - session:rollout-2026-06-10T23-25-38-019eb336-424e-7cf2-a351-7654f7a0b9af
---

# Settings Screen Organization

## Settings Root Organization

Settings root groups sections as Account (with Identity), Library (with Subscriptions, Categories), Listening (with Playback, Downloads), Intelligence (with Agent, Models & Providers, Transcripts, Wiki), and System (with Notifications, Data & Storage). The Settings footer displays the Pod0 version and build number. (Previously: The Settings footer displays the Podcastr version and build number. <!--  -->, superseded — see podcast-app-state.)

## Intelligence Section Details

Under Intelligence, Providers configures connection setup for OpenRouter, ElevenLabs, and Ollama, while Models assigns roles (Agent, Memory Compilation, Wiki, Embeddings, Speech) to models available from those providers. Speech model and voice selection live in SpeechModelsSettingsView under Intelligence > Models, not scattered in provider or transcript screens. On the Settings > Models list, each model role row must show the role name on the left and the model name with the provider name underneath in smaller font on the right. The badge/chip row (showing labels like 'variable', 'tools') must be removed from each role row. Model selectors must not duplicate across multiple screens; either model roles live only in Models, or Wiki/Transcript screens deep-link to the relevant role picker.

<!-- citations: [^rollo-63] [^rollo-168] [^rollo-266] -->
## Agent Settings Sub-sections

Agent settings are reorganized into sub-sections: Identity & Connection, Friends & Access, Memories & Notes, and Run History & Activity, instead of one long mixed list plus a separate Nostr toggle. <!-- [^rollo-64] -->

## Categories Screen

Recompute Categories is a category maintenance action and lives inside the Categories screen, not on root Settings. <!-- [^rollo-65] -->

## Data & Storage Consolidation

Storage, Data & Export, and root-level Clear All Data are consolidated into a single Data & Storage screen to avoid noisy root-level destructive actions. <!-- [^rollo-66] -->
