# BDD Catalog 03 - Agent, LLM, Knowledge, Voice

## Agent Chat And Tools

| ID | Scenario | Evidence |
|---|---|---|
| AG-001 | Given the agent toolbar button is visible, when tapped, then Agent Chat opens with composer, history affordance, and empty state. | SS: chat surface; Perf: open under 500 ms; Deps: UITestAgentStub ok; Boundary: native render,D5. |
| AG-002 | Given `--UITestAgentStub` is active, when the user sends a simple prompt, then a canned assistant reply appears and history stores the turn. | SS: prompt and reply; Perf: reply under 1 sec; Deps: UITestAgentStub; Boundary: D4,D5. |
| AG-003 | Given a transcript segment has Ask Agent action, when invoked, then chat opens with episode and segment context attached. | SS: context chip and composer; Perf: open under 500 ms; Deps: transcript seed; Boundary: D5. |
| AG-004 | Given audio is playing, when Agent Chat opens, then now-playing context is attached by default and removable by the user. | SS: now-playing chip; Perf: none; Deps: seeded player; Boundary: D4,D5. |
| AG-005 | Given an episode card is attached, when the user asks for a summary, then tool calls include that episode scope only. | SS: attachment and tool inspector; Perf: none; Deps: agent tool cassette; Boundary: D5,D7. |
| AG-006 | Given the agent lists episodes, when tool results return, then episode cards render title, show, date, and play affordance. | SS: cards; Perf: tool result render under 500 ms; Deps: tool result replay; Boundary: D5. |
| AG-007 | Given the agent asks to play a timestamp, when user accepts the action chip, then playback seeks through kernel player action. | SS: action chip and player; Perf: action under 500 ms; Deps: tool result replay; Boundary: D4,D7. |
| AG-008 | Given the agent proposes a highlight, when user accepts, then clip composer opens with suggested bounds and provenance. | SS: tool proposal and composer; Perf: under 1 sec; Deps: clip suggestion cassette; Boundary: D4,D7. |
| AG-009 | Given a tool fails, when the reply renders, then failure is visible in state and inspector without throwing UI exceptions. | SS: failed tool inspector; Perf: none; Deps: failed tool replay; Boundary: D6. |
| AG-010 | Given agent thinking exceeds 8 sec, when still running, then progress and cancel affordance are visible. | SS: progress state; Perf: timing from injected clock; Deps: slow LLM cassette; Boundary: D6,D8,D9. |
| AG-011 | Given cancel is tapped mid-run, when provider later replies, then stale reply is ignored or marked canceled consistently. | SS: cancel and final state; Perf: no stale mutation; Deps: delayed cassette; Boundary: D4,D8,D9. |
| AG-012 | Given a new conversation is created, when the user asks a follow-up, then prior conversation context does not bleed in. | SS: conversation list and reply; Perf: none; Deps: stub/replay; Boundary: D4,D5. |
| AG-013 | Given conversation history is exported, when export completes, then messages and tool summaries are included without provider keys. | SS: export preview; Perf: export time; Deps: chat seed; Boundary: D10. |
| AG-014 | Given markdown answer contains code, links, and lists, when rendered, then layout is readable and links are tappable. | SS: rendered answer; Perf: render time; Deps: markdown reply cassette; Boundary: native render. |
| AG-015 | Given friend-agent DMs are visible in the thread list, when one opens, then relay glyph and trust status are shown. | SS: thread list and detail; Perf: none; Deps: social fixture; Boundary: D4,D10. |
| AG-016 | Given agent memory is created from chat, when Settings Memories opens, then memory appears with source and can be deleted. | SS: chat memory and settings; Perf: projection update; Deps: memory tool replay; Boundary: D4,D5. |
| AG-017 | Given scheduled agent task is created from UI, when saved, then task intent label appears without raw dispatch JSON in normal UI. | SS: task form and row; Perf: none; Deps: task intent fixture; Boundary: D4,D7. |
| AG-018 | Given a due scheduled prompt exists, when app foregrounds, then Rust run-due policy triggers a task run and projects result. | SS: task history; Perf: foreground-to-run timing; Deps: replay clock and LLM cassette; Boundary: D7,D9. |

## LLM Provider And Replay

| ID | Scenario | Evidence |
|---|---|---|
| LLM-001 | Given Ollama endpoint is configured, when Check Models is tapped, then model list appears from shared provider catalog. | SS: provider screen; Perf: catalog latency; Deps: `cassettes/llm/ollama-models.json`; Boundary: D7. |
| LLM-002 | Given `deepseek-v4-flash:cloud` is selected for Agent, when settings reload, then role-to-model selection persists. | SS: model selector after relaunch; Perf: none; Deps: settings fixture; Boundary: D4,D7. |
| LLM-003 | Given OpenRouter key is configured, when key validation runs, then Rust validator owns status and message. | SS: validation result; Perf: validation latency; Deps: `cassettes/llm/openrouter-key-valid.json`; Boundary: D6,D7. |
| LLM-004 | Given OpenRouter key is invalid, when validation runs, then provider-specific failure is shown without exposing the key. | SS: validation error; Perf: none; Deps: `cassettes/llm/openrouter-key-invalid.json`; Boundary: D6,D7,D10. |
| LLM-005 | Given ElevenLabs key is configured, when validation runs, then voice account status is replayable from cassette. | SS: validation result; Perf: latency; Deps: `cassettes/tts/elevenlabs-key-valid.json`; Boundary: D7. |
| LLM-006 | Given AssemblyAI key is missing, when AssemblyAI transcription is requested, then missing credential state comes from Rust provider policy. | SS: missing key error; Perf: none; Deps: no-key fixture; Boundary: D6,D7. |
| LLM-007 | Given Perplexity is configured, when open-web search runs, then citations and fallback provider choice are captured in replay. | SS: search answer and citations; Perf: latency and cost; Deps: `cassettes/search/perplexity-citations.json`; Boundary: D7. |
| LLM-008 | Given Perplexity fails and OpenRouter fallback is enabled, when search runs, then fallback is visible in tool inspector. | SS: inspector; Perf: retry timing; Deps: `cassettes/search/perplexity-fail-openrouter-fallback.json`; Boundary: D6,D7. |
| LLM-009 | Given a local model catalog contains installed and missing models, when Local Models opens, then state renders without live network. | SS: local catalog; Perf: catalog load time; Deps: local catalog fixture; Boundary: D4,D7. |
| LLM-010 | Given provider completion returns malformed JSON, when agent expects structured tool data, then the app shows structured failure and preserves chat. | SS: error reply and inspector; Perf: none; Deps: malformed completion cassette; Boundary: D6. |
| LLM-011 | Given a completion is replayed, when test uses the same prompt and clock, then normalized answer and tool calls match snapshot. | SS: replay pass log; Perf: deterministic diff time; Deps: frozen cassette and clock; Boundary: D9. |
| LLM-012 | Given a cassette was recorded live, when sanitized, then it contains no API keys, nsec, bearer tokens, or raw private audio. | SS: cassette lint output; Perf: none; Deps: cassette sanitizer; Boundary: D10. |
| LLM-013 | Given model selection points to a deleted model, when agent run starts, then Rust reports missing model and UI offers settings recovery. | SS: recovery banner; Perf: none; Deps: stale settings fixture; Boundary: D6,D7. |
| LLM-014 | Given provider rate limit occurs, when agent run starts, then rate limit copy and retry timing are projected from Rust. | SS: rate limit state; Perf: retry-after clock; Deps: rate-limit cassette; Boundary: D6,D9. |
| LLM-015 | Given BYOK OAuth starts, when browser callback returns, then Rust validates state/verifier and platform stores only returned secrets. | SS: browser return and connected state; Perf: auth timing; Deps: BYOK callback cassette; Boundary: D7,D10. |
| LLM-016 | Given BYOK callback state mismatches, when handled, then connection fails closed and no credential is stored. | SS: auth error; Perf: none; Deps: BYOK bad-state cassette; Boundary: D6,D7,D10. |
| LLM-017 | Given image generation is requested by an agent skill, when provider returns an image URL, then result is displayed and replay stores only metadata. | SS: image result; Perf: generation latency; Deps: `cassettes/image/openrouter-image-result.json`; Boundary: D7,D10. |
| LLM-018 | Given reranking is enabled for search results, when reranker returns scores, then UI ordering follows Rust-ranked output, not native heuristics. | SS: ordered results and inspector; Perf: rerank latency; Deps: rerank cassette; Boundary: D4,D7. |

## Wiki, RAG, Knowledge, And Briefings

| ID | Scenario | Evidence |
|---|---|---|
| WIKI-001 | Given transcripts are indexed, when the user asks a concrete episode question, then the answer cites matching transcript spans. | SS: answer and citations; Perf: answer latency; Deps: `cassettes/llm/episode-grounded-qa.json`; Boundary: D5,D7. |
| WIKI-002 | Given a question is not covered by the episode, when asked, then the agent declines or says not in transcript without fabrication. | SS: negative control answer; Perf: none; Deps: grounded QA cassette; Boundary: D6,D7. |
| WIKI-003 | Given local transcript search has a snippet, when agent answer cites it, then the cited timestamp opens playback at the same span. | SS: citation tap and player; Perf: route under 500 ms; Deps: transcript seed and QA cassette; Boundary: D4,D5. |
| WIKI-004 | Given a wiki topic exists, when opened, then summary, source count, citations, and related topics render. | SS: wiki page; Perf: render under 1 sec; Deps: wiki projection fixture; Boundary: D5. |
| WIKI-005 | Given a wiki claim has one source, when rendered, then single-source confidence styling is visible. | SS: confidence mark; Perf: none; Deps: wiki fixture; Boundary: D4. |
| WIKI-006 | Given a wiki claim has zero usable sources, when regeneration completes, then the claim is omitted or clearly marked general knowledge. | SS: regenerated page; Perf: regen time; Deps: `cassettes/wiki/claim-zero-source.json`; Boundary: D6,D7. |
| WIKI-007 | Given a topic has contradictions across episodes, when Threading detail opens, then contradiction rows include cited quote pairs. | SS: contradiction sheet; Perf: open under 1 sec; Deps: threading fixture; Boundary: D5,D7. |
| WIKI-008 | Given threading confidence is below threshold, when a topic appears, then it uses low-confidence styling and caveat copy. | SS: low-confidence row; Perf: none; Deps: threading fixture; Boundary: D4. |
| WIKI-009 | Given no wiki page exists for a query, when Compile is tapped, then generation progress is replayable and citations resolve incrementally. | SS: progress states; Perf: first block latency; Deps: `cassettes/wiki/compile-topic.json`; Boundary: D7,D9. |
| WIKI-010 | Given a wiki sentence is marked wrong, when feedback is submitted, then contested state persists until next regeneration. | SS: feedback and contested mark; Perf: none; Deps: wiki fixture; Boundary: D4. |
| WIKI-011 | Given a library-wide query spans multiple shows, when Ask runs, then answer includes cross-show evidence and avoids ungrounded broad claims. | SS: cross-show answer; Perf: latency and token count; Deps: `cassettes/llm/cross-show-synthesis.json`; Boundary: D5,D7. |
| WIKI-012 | Given a personalized briefing is requested, when composition starts, then outline/tool plan is visible and replayable. | SS: briefing progress; Perf: first audio chunk and total compose time; Deps: `cassettes/briefing/daily-outline.json`; Boundary: D7,D9. |
| WIKI-013 | Given briefing segment TTS fails, when fallback runs, then the segment is labeled paraphrased or failed, not silently omitted. | SS: failed segment state; Perf: none; Deps: TTS failure cassette; Boundary: D6,D7. |
| WIKI-014 | Given a briefing contains source quotes, when a quote chip is tapped, then source episode opens at timestamp. | SS: briefing chip and player; Perf: route under 500 ms; Deps: briefing fixture; Boundary: D5. |
| WIKI-015 | Given the user asks "what was that podcast about stamps", when semantic search runs, then fuzzy result cards include why-match snippets. | SS: semantic results; Perf: local vector search latency; Deps: embeddings fixture; Boundary: D5,D8. |
| WIKI-016 | Given embeddings are stale after model change, when search runs, then stale-index banner appears and background reindex begins. | SS: banner and results; Perf: reindex progress; Deps: stale index fixture; Boundary: D4,D8. |
| WIKI-017 | Given a topic profile opens, when source data is incomplete, then partial profile renders with missing data marked explicitly. | SS: topic/person profile; Perf: none; Deps: profile fixture; Boundary: D6. |
| WIKI-018 | Given a podcast has no transcript but has show notes, when Ask tries to answer, then it states limited grounding and cites show notes only. | SS: limited-grounding answer; Perf: none; Deps: no-transcript QA cassette; Boundary: D6,D7. |

## Voice And Generated Audio

| ID | Scenario | Evidence |
|---|---|---|
| VOICE-001 | Given the toolbar voice button exists, when tapped, then canonical VoiceView opens and not the voice-note sheet. | SS: VoiceView root; Perf: open under 500 ms; Deps: UITestSeed; Boundary: D4,D5. |
| VOICE-002 | Given mic permission is undetermined, when voice mode starts, then permission prompt appears in context. | SS: permission prompt; Perf: none; Deps: simulator permission reset; Boundary: D7. |
| VOICE-003 | Given mic permission is denied, when voice mode starts, then denied state offers settings recovery and text fallback. | SS: denied state; Perf: none; Deps: simulator permission denied; Boundary: D6,D7. |
| VOICE-004 | Given voice mode is listening, when speech is detected, then orb state changes to transcribing and transcript partials appear. | SS: orb states; Perf: VAD-to-state latency; Deps: audio input fixture; Boundary: D7,D8. |
| VOICE-005 | Given voice text is finalized, when agent run starts, then text is attached to chat and LLM cassette replays answer. | SS: text and answer; Perf: final speech to answer; Deps: `cassettes/voice/basic-agent-turn.json`; Boundary: D7. |
| VOICE-006 | Given agent is speaking, when user barges in, then TTS ducks/stops and listening state starts within latency budget. | SS: state transition; Perf: barge-in under 250 ms target; Deps: TTS plus input replay; Boundary: D7,D8. |
| VOICE-007 | Given barge-in is a cough false positive, when STT rejects speech, then TTS resumes without committing a user turn. | SS: resumed speaking; Perf: false positive recovery; Deps: VAD replay; Boundary: D7,D8. |
| VOICE-008 | Given ElevenLabs voice preview is requested, when provider returns audio, then preview plays and cassette captures voice/model metadata. | SS: preview control; Perf: time to first audio; Deps: `cassettes/tts/elevenlabs-preview.json`; Boundary: D7. |
| VOICE-009 | Given ElevenLabs TTS is unavailable, when voice answer is needed, then AVSpeech fallback is labeled and no provider loop starts. | SS: fallback state; Perf: fallback start latency; Deps: TTS failure cassette; Boundary: D6,D7,D8. |
| VOICE-010 | Given a voice note is recorded from Now Playing, when saved, then it creates a timestamped note rather than starting canonical VoiceView. | SS: voice note sheet and saved note; Perf: none; Deps: audio input fixture; Boundary: D4,D7. |
| VOICE-011 | Given in-episode agent receives "rewind to where this topic started", when tool resolves a timestamp, then playback seeks and stays in player. | SS: voice prompt and seek; Perf: end-to-end latency; Deps: `cassettes/voice/seek-topic-start.json`; Boundary: D4,D7. |
| VOICE-012 | Given in-episode agent receives "clip that", when transcript context exists, then semantic clip composer opens with proposed bounds. | SS: voice turn and composer; Perf: latency; Deps: `cassettes/voice/clip-that.json`; Boundary: D4,D7. |
| VOICE-013 | Given voice mode is offline, when the user speaks, then online tools are disabled and local transcript scope is explicit. | SS: offline voice state; Perf: local processing latency; Deps: network offline and local STT fixture; Boundary: D6,D7. |
| VOICE-014 | Given a voice interaction completes, when chat history is inspected, then only final text persists, not raw audio buffers. | SS: chat history and file scan log; Perf: none; Deps: voice fixture; Boundary: D10. |
| VOICE-015 | Given CarPlay voice button starts voice mode, when command completes, then app state and CarPlay UI remain synchronized. | SS: CarPlay state and app player; Perf: command latency; Deps: CarPlay harness; Boundary: D7. |
| VOICE-016 | Given Siri intent starts voice mode with a phrase, when app receives intent, then phrase is routed as user intent through Rust. | SS: intent result and chat; Perf: intent-to-run latency; Deps: App Intent fixture; Boundary: D7. |
| VOICE-017 | Given voice mode is stopped repeatedly, when start/stop is called three times, then capability lifecycle is idempotent. | SS: stable stopped state; Perf: no leaked tasks; Deps: voice capability mock; Boundary: D7,D8. |
| VOICE-018 | Given voice response includes citations, when spoken answer finishes, then visible transcript answer includes tap-to-play citations. | SS: answer with citations; Perf: TTS total duration; Deps: voice QA cassette; Boundary: D5,D7. |
