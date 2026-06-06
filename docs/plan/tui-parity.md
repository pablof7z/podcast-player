# TUI Feature Parity

**Goal:** bring `apps/podcast-tui` to parity with the iOS and Android shells
where the terminal can reasonably expose the same Rust-kernel features. The
TUI remains a thin renderer/dispatcher: podcast policy and durable state stay
in `apps/nmp-app-podcast`.

## Current Baseline

The TUI already boots the real NMP podcast kernel, subscribes/searches through
the shared HTTP capability path, renders the library/search/inbox/queue/player
projections, and dispatches Rust actions for playback, downloads, queue,
bookmarks, and basic settings.

## 2026-06-06 Foundation PR

This PR expands the TUI from the original core-player surface to a parity
foundation:

- Adds tabs for Bookmarks, Clips, Agent, Wiki, Social, and richer Settings.
- Projects kernel clips, agent chat/messages, agent picks/tasks/notes, memory,
  wiki articles, comments, categories, active account, social contacts,
  configured relays, inbox triage state, and settings into `AppState`.
- Wires working kernel actions for queue selection/removal/clear, play-next,
  bookmark removal, AutoSnip/delete clips, agent send/clear/fetch notes, social
  contact refresh, wiki delete, and settings toggles.
- Splits TUI state, row mapping, runtime actions, and input handlers so all
  touched files stay under the repository line limits.

## Parity Matrix

| Surface | TUI status | Notes |
|---|---|---|
| Subscribe/search/library/show episodes | Partial | Core flow works; needs OPML, feed refresh controls, empty/error polish, and terminal validation. |
| Playback/player controls | Partial | Play/pause/seek/speed exist; sleep timer, chapters controls, route/platform surfaces remain absent or read-only. |
| Queue | Partial | Selection, play, remove, clear, add-last, and play-next are wired; reorder/persistence validation remains. |
| Bookmarks | Partial | Starred episodes now have a tab and unstar/play/queue actions; filtering/search is still absent. |
| Downloads | Partial | Active download status is shown; manager actions for pause/resume/cancel/delete are not yet exposed. |
| Settings | Partial | Common playback/AI/Nostr toggles render and dispatch; provider credential editing and relay editing are not exposed. |
| Clips | Partial | Clip projection, AutoSnip, play-from-start, and delete are wired; composer/export/share flows are absent. |
| Agent chat | Scaffold/Partial | Send/clear renders the kernel agent surface; real LLM loop remains governed by the existing NMP backlog. |
| Agent tasks/picks/memory/notes | Read-only/Partial | Projections render; task CRUD, memory CRUD, note publishing/trust workflows remain. |
| Wiki/RAG | Read-only/Scaffold | Articles and search results render; generate/search controls and real RAG synthesis remain. |
| Inbox triage | Partial | Triage rows and in-progress state render; dismiss/retriage controls need wiring. |
| Nostr/social/relays/comments | Read-only/Scaffold | Account, contacts, relays, and comments project; identity, relay editing, comments publish, and social graph completion remain. |
| Voice/transcripts/chapters/ad-skip | Not started/Read-only | Some episode metadata is visible; terminal controls for these flows need dedicated slices. |

## Next Slices

1. Add a downloads manager surface: pause/resume/cancel/delete, completed rows,
   and per-episode download state in every episode list.
2. Add episode-detail parity controls for transcripts, chapters, summaries,
   comments fetch, ad-skip metadata, reset progress, and sleep timer.
3. Add full settings editors for relays, provider metadata, playback intervals,
   STT/TTS selections, local models, and notifications.
4. Add CRUD flows for memory, agent tasks, wiki generation/search, and agent
   note publishing once the corresponding kernel behavior is real.
5. Add focused TUI integration scenarios for queue, bookmarks, clips, settings,
   and agent actions, then broaden to network-backed subscribe/search smoke.
