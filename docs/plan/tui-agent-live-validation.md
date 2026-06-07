# TUI Agent Live Validation

**Goal:** validate agentic podcast workflows by driving the real
`podcast-tui` inside tmux, with real kernel state and Ollama Cloud model
settings. No fake action dispatch, stubbed agent calls, or headless-only
substitutes count for this pass.

## Preconditions

- The TUI must run from a dedicated data directory so test state is isolated.
- The terminal process must have `OLLAMA_API_KEY` set before launch.
- The TUI Settings `providers` section must load provider keys from env.
- All LLM role rows should be set to Ollama Cloud-compatible model IDs:
  agent initial, agent thinking, memory compilation, wiki, categorization,
  chapter compilation, embeddings, and image generation where the kernel can
  honor the role.
- Test evidence should come from tmux pane captures and persisted app state,
  not from direct kernel test calls.

## Exhaustive Agentic Scenario Inventory

### Discovery And Library Work

- Find podcasts by topic, host, title, publisher, or guest.
- Subscribe to a discovered podcast.
- Explain why a selected show is relevant to the user's interests.
- Compare two or more search results and recommend one.
- Find recent unplayed episodes matching a theme.
- Find older saved episodes matching a theme.
- Identify episodes from a specific guest, creator, feed, or publication.
- Build a listening shortlist from the current library.
- Detect stale subscriptions that have not published recently.
- Suggest unsubscribing, archiving, or deprioritizing inactive feeds.

### Queue And Playback Work

- Add the best episode for a requested topic to the queue.
- Add multiple related episodes in a useful order.
- Play the selected episode.
- Pause, resume, seek, skip forward, or skip backward on request.
- Move from a general request to concrete queue actions.
- Clear the queue after confirmation.
- Remove a bad or already-heard item from the queue.
- Add an episode next instead of at the end.
- Explain what is currently playing.
- Recommend playback speed or skip behavior for a show.

### Inbox And Listening Triage

- Triage new inbox episodes by interest.
- Mark low-priority episodes played/listened.
- Keep high-priority episodes unread for later.
- Explain why an episode was kept or dismissed.
- Find inbox episodes related to active memory facts.
- Build a morning commute playlist from the inbox.
- Build a long-form weekend playlist from the inbox.
- Identify duplicate or near-duplicate news coverage.
- Surface episodes likely to include ads or filler.

### Memory And Preference Work

- Remember a durable user preference.
- Update an existing preference.
- Forget a stale preference.
- Use saved preferences to recommend episodes.
- Explain which memory facts influenced a recommendation.
- Store topic interests, avoided topics, favorite hosts, disliked shows,
  commute length, preferred episode length, and listening goals.
- Avoid over-writing unrelated memory facts.
- Clear all memory after explicit confirmation.

### Episode Understanding Work

- Summarize an episode.
- Answer questions about an episode transcript.
- Explain the key claims in an episode.
- Extract action items from an episode.
- Find a quote or segment by topic.
- Identify named people, companies, books, papers, or tools.
- Generate chapter titles from transcript content.
- Compare an episode to another episode or saved memory.
- Categorize an episode into user-facing topics.
- Explain whether an episode is worth finishing.

### Clips And Bookmarks Work

- Star/bookmark the current episode.
- Unstar a selected episode.
- Create a clip around the current playback position.
- Create a clip for a named topic if transcript/time data is available.
- Delete an unwanted clip.
- Explain the context of a saved clip.
- Build a list of notable clips from recent listening.
- Turn a clip into a social/share draft when identity support exists.

### Downloads And Offline Work

- Download an episode for offline listening.
- Pause, resume, cancel, or delete a download.
- Queue downloads for travel.
- Identify episodes already available offline.
- Explain failed downloads and retry options.
- Keep downloads below a practical number for storage.

### Agent Chat Work

- Hold a conversational turn that references the current library.
- Ask follow-up questions when the request is ambiguous.
- Report inability clearly when a tool, key, identity, or transcript is absent.
- Avoid hallucinating actions that the kernel did not perform.
- Surface provider/model errors in the chat or status.
- Continue after a provider failure when possible.
- Preserve conversation context over several turns.
- Clear the chat when requested.

### Agent Picks Work

- Generate or render agent picks.
- Play a selected pick.
- Queue a selected pick.
- Add a selected pick next.
- Explain why each pick was chosen.
- Avoid picks that conflict with saved memory.
- Refresh picks after new subscriptions or new memory.

### Scheduled Agent Task Work

- Create a recurring task from natural language.
- Create one-shot tasks with a concrete schedule.
- Enable and disable an existing task.
- Run a task immediately.
- Delete a task.
- Explain what a task will do before saving.
- Reject malformed schedules or unsafe action JSON.
- Keep task list projection in sync after changes.

### Agent Notes And Social Work

- Fetch inbound public agent notes.
- Publish an outbound note to a specified public key.
- Refuse note publishing when no identity is configured.
- Explain trust state for inbound notes.
- Avoid auto-responding to untrusted senders.
- Thread future conversation-style notes under a root when the kernel supports it.

### Wiki And Knowledge Work

- Search existing wiki articles.
- Generate a wiki article from a transcript or library topic when supported.
- Delete an obsolete wiki article.
- Explain which episodes support a wiki claim.
- Refresh a stale article when new evidence appears.
- Distinguish scaffolded wiki content from real RAG output.

### Settings And Provider Work

- Switch all LLM roles to Ollama Cloud models.
- Load provider credentials from environment without displaying secrets.
- Set OpenRouter, Ollama, and ElevenLabs metadata without raw keys.
- Set STT provider and key-presence values.
- Set ElevenLabs STT/TTS and voice choices.
- Set or clear local model hints.
- Explain effective provider fallback when required keys are missing.
- Keep model IDs and display names coherent after edits.

### Error, Recovery, And Trust Work

- Handle missing `OLLAMA_API_KEY`.
- Handle a provider rejecting credentials.
- Handle no library content.
- Handle no selected episode.
- Handle no transcript.
- Handle no identity for notes/comments/social.
- Handle network failures during search, RSS ingest, or relay access.
- Avoid claiming success before the projection reflects the action.
- Recover from Esc/cancel during input.
- Preserve keyboard navigation after errors.

## Minimum Live Tmux Scenarios For This Pass

1. Configure Ollama Cloud across all model rows through the TUI Settings tab,
   load env credentials, and verify the visible projection reflects the edits.
2. Subscribe to a real RSS feed through the TUI, open the Agent tab, ask the
   agent to recommend an episode from the new library, and inspect the response.
3. Ask the agent to remember a preference, verify Memory projection updates,
   then ask for a recommendation that should use that preference.
4. Create, enable/disable, run-now, and delete an agent task from the Agent tab.
5. Ask the agent to queue or play a selected recommendation, then verify Queue
   or Player projection changes.
6. Exercise a missing-prerequisite path, such as publishing an agent note
   without identity or summarizing an episode without a transcript, and verify
   the TUI reports the limitation clearly.

## Evidence Log

### 2026-06-07T09:34Z-10:12Z

- Worktree: `/Users/customer/podcast-player-tui-agent-validation`
- Branch: `feat/tui-agent-live-validation`
- Tmux session: `podcast-tui-agent-live`
- Data directories:
  - `/tmp/podcast-tui-agent-live`
  - `/tmp/podcast-tui-agent-live-feed`
- Environment:
  - `OLLAMA_API_KEY` was not set.
  - `OPENROUTER_API_KEY` was not set.
  - Full live Ollama Cloud completion scenarios are blocked until a real
    `OLLAMA_API_KEY` is present in the terminal environment before launching
    the TUI.

### Scenarios Executed

- Settings > Providers > Load provider keys from env:
  - Before fix, the action could claim env credentials loaded even when no
    provider env keys existed.
  - After fix, the TUI reports:
    `no provider env keys set; set OLLAMA_API_KEY, OPENROUTER_API_KEY, ELEVENLABS_API_KEY, or ASSEMBLYAI_API_KEY`.
- Settings > Providers model rows:
  - Used only TUI keystrokes to set all visible role rows to
    `ollama:gpt-oss:120b-cloud | GPT-OSS 120B Cloud`.
  - Verified the Settings projection displayed the Ollama Cloud selection for
    agent initial/thinking, memory, wiki, categorization, chapter compilation,
    embeddings, and image generation.
- Agent chat, empty library:
  - Sent: `Recommend one podcast episode for me from my current library and explain why.`
  - Before fix, the TUI stayed pinned at `Agent Chat busy` for more than a
    minute.
  - After fix, the assistant row reported the missing Ollama Cloud credential
    in about four seconds.
- Agent memory:
  - Entered `preferred_duration=short episodes under 30 minutes` from the
    Agent > Memory section.
  - Verified the Memory projection showed
    `preferred_duration = short episodes under 30 minutes (user)`.
- Agent tasks:
  - Created `Refresh inbox now | manual | podcast.inbox | {"op":"triage"} | manual validation task`.
  - Disabled it through `e`, verified row changed to `off`.
  - Pressed `r` while disabled; before fix it still reported `task dispatched`.
  - After fix it reports `task run error: task disabled`.
  - Re-enabled, ran, and deleted the task; projection returned to the built-in
    Inbox Triage row.
- Real RSS subscription:
  - Subscribed to `https://feeds.npr.org/510289/podcast.xml` through the TUI.
  - Verified `Planet Money` loaded with 355 episodes.
  - Before fix, background picks/categorization LLM calls wrote repeated 401
    unauthorized logs into the terminal UI.
  - After fix, the subscription completed cleanly with no 401 log flood and
    the TUI remained readable.
- Agent chat, populated library:
  - Sent: `From my current library, recommend one episode to start with and give a one-sentence reason.`
  - Verified the assistant row reported the missing `OLLAMA_API_KEY` instead
    of fabricating a recommendation.

### Fixes From Live TUI Use

- Provider env load now errors when no relevant env keys are set.
- `Ctrl+U` clears settings and relay input fields, making model replacement
  practical in the terminal.
- Provider-prefixed `ollama:` and `openrouter:` role selections are now honored
  by the shared LLM factory instead of falling back to hardcoded defaults.
- Ollama backend strips the `ollama:` provider prefix before calling the model.
- Ollama Cloud and OpenRouter paths preflight required in-memory keys before
  starting model calls.
- Agent model turns have a 45-second wall-clock budget.
- Production agent chat writes concrete provider errors into the assistant row
  instead of falling back to the scaffold placeholder.
- Picks now shares the visible Categorization model row; episode summaries
  share the visible Wiki model row, avoiding hidden hardcoded model choices.
- Background missing-credential failures fall back quietly instead of dumping
  per-episode logs into the TUI.
- TUI task run checks the selected task's enabled state before dispatching, so
  disabled tasks cannot claim they were dispatched.
- TUI dispatch parsing now recognizes nested `{ok:false}` result envelopes when
  they are present.
