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

## 2026-06-06 Agent Slice

The Agent tab now behaves as a sectioned workspace:

- Chat: compose/clear against `podcast.agent`.
- Picks: select, play, queue, or play-next projected agent picks.
- Tasks: create, run-now, enable/disable, and delete via `podcast.tasks`.
- Notes: fetch inbound agent notes and publish public kind:1 notes via
  `PublishAgentNote` when an identity is available.
- Memory: remember `key=value`, forget selected facts, and clear the bag via
  `podcast.memory`.

Headless TUI integration now asserts agent chat projection, memory CRUD, and
agent task create/enable/disable/run/delete round trips through the kernel.

## 2026-06-06 Downloads Slice

The TUI now has a dedicated Downloads tab backed by the kernel download-queue
projection:

- Active, queued, paused, and failed rows render with progress, state, type,
  total byte count when available, URL, and error detail.
- Keyboard actions dispatch existing kernel download controls: pause, resume,
  cancel selected, cancel all, and delete a completed local episode file.
- Library, queue, inbox, and bookmarks rows now show active download state;
  episode-backed rows also show completed local files through `download_path`.
- Headless integration smoke-tests the runtime action routing for pause,
  resume, cancel, cancel-all, and delete without requiring a platform
  background-download executor.

The kernel does not currently project a centralized completed-download history,
so completed downloads are surfaced through episode rows rather than as a
standalone completed list.

## Parity Matrix

| Surface | TUI status | Notes |
|---|---|---|
| Subscribe/search/library/show episodes | Partial | Core flow works; needs OPML, feed refresh controls, empty/error polish, and terminal validation. |
| Playback/player controls | Partial | Play/pause/seek/speed exist; sleep timer, chapters controls, route/platform surfaces remain absent or read-only. |
| Queue | Partial | Selection, play, remove, clear, add-last, and play-next are wired; reorder/persistence validation remains. |
| Bookmarks | Partial | Starred episodes now have a tab and unstar/play/queue actions; filtering/search is still absent. |
| Downloads | TUI wired / executor-dependent | Active queue rows, progress, pause/resume/cancel/cancel-all, delete-file routing, and per-episode badges are wired. A completed-download history needs a richer kernel projection. |
| Settings | Partial | Common playback/AI/Nostr toggles render and dispatch; provider credential editing and relay editing are not exposed. |
| Clips | Partial | Clip projection, AutoSnip, play-from-start, and delete are wired; composer/export/share flows are absent. |
| Agent chat | TUI wired / kernel scaffold | TUI send/clear is wired and tested; real LLM loop remains governed by the existing NMP backlog. |
| Agent tasks/picks/memory/notes | Partial | TUI task CRUD/run, pick play/queue, memory CRUD, note fetch/publish are wired; note trust workflows and the real scheduler/responder loop remain kernel backlog work. |
| Wiki/RAG | Read-only/Scaffold | Articles and search results render; generate/search controls and real RAG synthesis remain. |
| Inbox triage | Partial | Triage rows and in-progress state render; dismiss/retriage controls need wiring. |
| Nostr/social/relays/comments | Read-only/Scaffold | Account, contacts, relays, and comments project; identity, relay editing, comments publish, and social graph completion remain. |
| Voice/transcripts/chapters/ad-skip | Not started/Read-only | Some episode metadata is visible; terminal controls for these flows need dedicated slices. |

## Next Slices

1. Add episode-detail parity controls for transcripts, chapters, summaries,
   comments fetch, ad-skip metadata, reset progress, and sleep timer.
2. Add full settings editors for relays, provider metadata, playback intervals,
   STT/TTS selections, local models, and notifications.
3. Add wiki generation/search plus richer agent note trust/conversation flows
   once the corresponding kernel behavior is real.
4. Add a completed-download history once the kernel projects durable completed
   download rows beyond per-episode `download_path`.
5. Add focused TUI integration scenarios for queue, bookmarks, clips, settings,
   and agent actions, then broaden to network-backed subscribe/search smoke.
