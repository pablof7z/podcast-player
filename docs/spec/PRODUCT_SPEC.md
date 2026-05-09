# Podcastr — Product Spec

> Synthesized from the project context, the baseline-feature checklist, fifteen UX briefs, five research notes, the architecture report, and the live skeleton on disk. Where briefs disagreed, this document has chosen a position. Dissent and undecided items are listed in §9.

**Status:** decision-grade. An engineer or executive should be able to read this top-to-bottom in ~30 minutes and come away with no major question unanswered (or, where unanswered, knowing it explicitly).

---

## Table of Contents

- [1. Vision & North Star](#1-vision--north-star)
- [2. Marquee User Stories](#2-marquee-user-stories)
- [3. Information Architecture & Tab Structure](#3-information-architecture--tab-structure-resolved)
- [4. Feature Inventory](#4-feature-inventory)
- [5. Surface-by-Surface UX](#5-surface-by-surface-ux)
- [6. Liquid Glass Design System](#6-liquid-glass-design-system-visual--motion--haptics--sound)
- [7. Technical Architecture](#7-technical-architecture)
- [8. Cross-Cutting Decisions Already Made](#8-cross-cutting-decisions-already-made)
- [9. Open Decisions (need a call before build)](#9-open-decisions-need-a-call-before-build)
- [10. Phased Delivery Plan](#10-phased-delivery-plan)
- [11. Risk Register](#11-risk-register)
- [12. Appendix — Source Briefs Index](#12-appendix--source-briefs-index)

---

## 1. Vision & North Star

> Source: [docs/spec/PROJECT_CONTEXT.md](PROJECT_CONTEXT.md), [docs/spec/briefs/ux-15-liquid-glass-system.md](briefs/ux-15-liquid-glass-system.md)

Podcastr is a next-generation iOS podcast player built around an embedded AI agent that has **perfect knowledge of every podcast the user is subscribed to** — including the episodes they have not listened to yet. The user can talk to all of their podcasts as if they were one continuous conversation, by text or by voice, and the agent answers grounded in transcripts, wikis, and the open web — with citations that are tap-to-play.

The product makes three promises that no other podcast app currently makes together:

1. **The library is searchable as language, not just titles.** Every episode is transcribed, diarized, chunked, embedded, and indexed locally. Vague half-memories (*"that one about stamps"*) become tap-to-play moments.
2. **The agent produces, not just retrieves.** It synthesizes a personalized morning briefing — an entire NPR-quality episode written and narrated for the user, stitched with original quotes — and is **interruptible mid-narration**: the user speaks, the briefing ducks, the agent answers, the briefing resumes from the same word it dropped.
3. **The bar for craft is editorial.** iOS 26 Liquid Glass everywhere; New York serif for content; SF Pro for chrome; cinematic motion that *means something*; haptics and sound design that earn their place. Calm by default, alive on demand. Better than Spotify, Overcast, Pocket Casts, Castro on the floor — and an agent layer no one else can match on top.

**Design north star (single sentence):** *the home screen feels quiet; the player breathes; the agent is electric — and the user can always feel which is which.*

**Foundations we inherit (do not rebuild):** SwiftUI + Tuist, iOS 26 deployment target, Swift 6 strict concurrency, an `@Observable` `AppStateStore`, a working tool-calling agent loop over OpenRouter SSE, a complete Nostr subsystem (relays, keypair, ACLs, agent relay bridge for cross-device DMs), Keychain BYOK stores for OpenRouter and ElevenLabs, shake-to-feedback, Live Activities and widgets via the App Group, App Intents + Siri, GitHub Actions → TestFlight CI. The skeleton is renamed end-to-end to **Podcastr**, builds green, and has stubbed module/feature folders waiting for this spec.

---

## 2. Marquee User Stories

These five moments are the demo reel and the acceptance test for v1. If any one of them does not land, v1 is not done.

| # | Story | Demonstrates |
|---|---|---|
| 1 | *"Play the part of yesterday's Tim Ferriss where he talked about keto."* — agent finds the timestamp, opens the player, presses play. <2 s perceived. | Voice + RAG + `play_episode_at` tool + transcript ingest pipeline working end-to-end. |
| 2 | *"What was that podcast last week about stamps?"* — fuzzy semantic recall surfaces a clip card; tap plays at the right second. | Embeddings + hybrid FTS5/vec search + clip card surface. |
| 3 | *"Give me a TLDR of this week's podcasts in 12 minutes."* — `generate_briefing` produces a TTS-narrated synthesized episode in <90 s, plays it, the user says *"Wait, who was that guest?"* mid-briefing — the briefing ducks, the agent answers from RAG, the briefing resumes at the same syllable. | Briefing composer + barge-in voice mode + audio session coordination + LLM streaming. |
| 4 | *"Send my partner a clip of the part where she's mentioned."* — agent finds the speaker name + timestamp, builds an audio + waveform clip card, shares via Nostr DM (or iMessage) with provenance. | Diarization + clip composer + Nostr send pipeline. |
| 5 | *"What does this podcast say about Ozempic across all their episodes?"* — agent runs cross-episode synthesis from transcripts + wiki, returns a comparison block with two-column pull quotes and contradictions surfaced. | LLM wiki + cross-episode threading + hallucination guardrails (every claim cites a span). |

A sixth story, *"What's a contrarian take on what they just said?"*, exercises `perplexity_search` and is included as the differentiator versus closed-corpus assistants. It ships at v1 if the BYOK path for Perplexity lands; otherwise v1.1.

A seventh story is **in-episode voice drop**: while the episode is playing, the user taps the agent chip and speaks a one-sentence thought. The agent has full context of the current transcript window (what was just said) and the user's speech, then acts: *"rewind to where this topic started"* → seeks to the transcript anchor; *"clip that"* → builds a waveform clip card at semantically correct in/out points; *"I wonder how this applies to X"* → drops a timestamped note and optionally fires off a research thread. The user never leaves the Now Playing screen. See [docs/spec/briefs/ux-16-in-episode-agent.md](briefs/ux-16-in-episode-agent.md).

---

## 3. Information Architecture & Tab Structure (resolved)

> Source: [docs/spec/research/skeleton-bootstrap-report.md](research/skeleton-bootstrap-report.md), [docs/spec/briefs/ux-02-library.md](briefs/ux-02-library.md), [docs/spec/briefs/ux-04-llm-wiki.md](briefs/ux-04-llm-wiki.md), [docs/spec/briefs/ux-14-proactive-agent-notifications.md](briefs/ux-14-proactive-agent-notifications.md)

UX-02 proposed three tabs (Library / Listen / Agent). The skeleton already shipped six (Today, Library, Wiki, Ask, Home, Settings) and UX-04, UX-08, UX-09, UX-13, UX-14 all implicitly assume Today and Wiki as destinations. **Resolution: skeleton wins**, with template Home retired before TestFlight.

### Final tab structure (v1)

```
┌─ Tabs ─────────────────────────────────────────────────────┐
│  Today    Library    Wiki    Ask    Settings              │
└────────────────────────────────────────────────────────────┘
   editorial subscriptions  knowledge  agent + global search   prefs
   "front       + downloads + people   + voice mode entry
    page"        + Discover  + topics
```

- **Today** — the proactive surface (UX-14): one daily briefing card, three to five insight cards (Drops / Threads / Echoes / Friends / Transcript-ready). Editorial cover, finishable in under a minute. Pull-down reveals yesterday's edition (7-day window). Empty days show a *"Quiet day."* cover, not a feed.
- **Library** — subscriptions, downloads, transcription queue, OPML, smart playlists (UX-02). Includes a **Discover** segmented sub-tab for agent-curated recommendation rails (offline-generated; *pull*, not *push*).
- **Wiki** — the LLM-compiled knowledge base (UX-04). Library-wide hub at the root; per-podcast wikis as a chip filter, *not* a separate destination. Topic, person, debate, graph (one level deep, opt-in), and Generate-Page surfaces.
- **Ask** — the agent's home (UX-05 + UX-07). Persistent search field at the top doubles as the chat composer; semantic search results stream beneath, with a single *"Ask the agent instead →"* card surfaced when the query reads as synthesis. Voice mode (UX-06) is reached from the mic button on this tab and from the Action Button / AirPods / Lock Screen.
- **Settings** — preserved verbatim from the template; extended with Voice, Briefing, Notifications, Friends, Identity, Relays, BYOK keys.

### Surfaces reached via navigation, not via the tab bar

- **Now Playing** (UX-01) — persistent mini-bar across all tabs; expands to full-screen via `matchedGeometryEffect`.
- **Episode Detail / Transcript Reader** (UX-03) — pushed from any subscription, search result, agent citation, or Today drop card.
- **Voice Mode** (UX-06) — modal full-screen orb; entered from Ask mic, Action Button, AirPods long-press, Lock Screen control, Siri intent, CarPlay voice button.
- **Briefing Player** (UX-08) — modal; entered from Today hero, Ask briefing card, Library briefings shelf, push notification.
- **Speaker / Topic Profile** (UX-13) — pushed onto the navigation stack of whichever tab summoned it (most often Wiki or transcript long-press).
- **Threading sheet** (UX-09) — bottom sheet at 40 % / 90 % detents; never a destination page.
- **Agent Chat thread list** (UX-05) — a sheet from the Ask tab on iPhone; a sidebar on iPad.

### Boundaries between agent surfaces (this is the contract)

- **Search** shows you the evidence (clips, episodes, transcript moments). It never argues or summarizes; the user picks.
- **Ask Agent** synthesizes prose answers grounded in tools. Editorial serif, unbubbled.
- **Briefings** produce *audio episodes* as artifacts. Agent owns this stage.
- **Wiki** is the long-term, compiled, human-readable knowledge base. Paper-feel; glass is chrome only.
- **Threading** is the contextual whisper across surfaces — never a tab.
- **Today** is the front page; one push a day, max. Surplus pools here.

---

## 4. Feature Inventory

### 4.1 Baseline / Table-Stakes

> Source: [docs/spec/baseline-podcast-features.md](baseline-podcast-features.md)

We commit to category parity, not victory, on the floor. The agent layer is the differentiator. Missing any **must** row at launch is a category-disqualifier.

| Area | v1 must-haves | v1.1 fast-follow | v2 |
|---|---|---|---|
| Playback | Variable speed (0.5×-3×, 0.05× steps, per-show + global default), Smart Speed silence trim, Voice Boost, asymmetric skip (15 / 30 default), sleep timer (incl. end-of-episode / chapter), chapter rendering (ID3, MP4, Podcasting 2.0), AirPlay 2, Bluetooth controls, full Now Playing + Remote Command Center, smart Up Next queue, resume position, mark-played thresholds, bookmarks, AI-generated chapters when none in feed, background audio, interruption handling | Volume normalization, long-press scrub, shake-to-extend sleep timer, Handoff iPhone↔iPad↔Mac↔Watch, episode-update detection, clip creation + share, premium / private feeds (Patreon / Supercast tokens) | Smart playlists, alt-feeds, Apple Podcasts Subscriptions OAuth, Spatial Audio, SharePlay co-listen |
| Subscriptions | RSS URL add, OPML import + export, iTunes Search API directory, Podcast Index integration, manual + scheduled (`BGAppRefreshTask` ~1 h Wi-Fi) refresh | Podcasting 2.0 namespace (chapters / transcripts / persons / soundbite / location / value), premium / private feeds, episode-update detection | — |
| Episode mgmt | Manual download + retry, auto-download policy (off / latest N / all new, Wi-Fi-only), storage UI, auto-delete after played, filter views (Unplayed / In Progress / Downloaded / Starred / Archived), sort, bulk mark-played, played-state viz, star / favorite | Archive, custom playlists, episode size cap, queue / history sync | Smart playlists, translated transcripts |
| Sync | iCloud (CloudKit) for subs + position + played-state, last-writer-wins per field with vector clock for position | Queue, badge, history sync, RTL + CJK + initial localizations (es / pt / ja / de / fr) | — |
| A11y | Dynamic Type to AX5, full VoiceOver coverage, high contrast, reduce motion, reduce transparency, captions / transcripts | RTL layouts, CJK font fallback, language indicator | Translated transcripts, on-device translation |
| Notifications | New-episode push, per-show toggle, agent / proactive notifications scaffolding | Quiet hours, download-complete (off by default) | — |
| Search | In-library keyword, in-show, Apple Podcasts directory, Podcast Index, semantic / agent (UX-07) | Recent / saved searches | — |
| Sharing / social | Share-with-timestamp universal link, App Intents + Siri, Live Activity (Now Playing + Dynamic Island), small + medium widgets | Clip share (audio + waveform card, video w/ subtitle burn-in), large widgets, action button shortcut presets | SharePlay co-listen, V4V Lightning tipping, boostagrams |
| Privacy | Analytics opt-out (default), data delete, per-show cache clear, honest privacy nutrition, ATT default-no | Data export (OPML + JSON), diagnostics export | — |
| Settings | Theme + accent, default speed + skip, auto-download defaults, restore from iCloud, sleep-timer defaults | Reset all, diagnostics export | — |
| Platform | Apple Watch standalone playback + downloads, iPad Stage Manager, PiP, video-podcast playback | Mac Catalyst, external display | Spatial Audio, Family Sharing |

The brief at `docs/spec/baseline-podcast-features.md` governs the *requirement to exist* for everything in this table; the surface briefs (UX-01-15) govern the *experience*.

### 4.2 Differentiating (Agent + Knowledge)

These are what no competitor has stitched together. Each row must work in concert with the surface owning it.

| Capability | Owning surface | New tools / engines |
|---|---|---|
| Timestamped diarized transcripts on every episode | UX-03, UX-01 | `Transcript/` module, `ScribeTranscriptionClient`, `PublisherTranscriptFetcher`, `TranscriptChunker` |
| LLM-compiled per-podcast and library-wide wikis | UX-04 | `Knowledge/WikiPage`, `WikiCompiler` (BG task), agent tool `query_wiki` |
| Hybrid lexical + vector RAG over transcripts | UX-05, UX-07 | `Knowledge/VectorIndex` (sqlite-vec), `RAGQueryService`, agent tool `query_transcripts` |
| Voice conversational mode with sub-second barge-in | UX-06 | `Voice/AudioConversationManager`, `BargeInDetector`, ElevenLabs Flash v2.5 streamer |
| Personalized audio briefings (interruptible) | UX-08 | `Briefing/BriefingComposer`, `BriefingPlayer`, agent tool `generate_briefing` |
| Cross-episode threading (timeline / contradictions / evolution) | UX-09 | Threading inference job (BG), agent tools `find_contradictions`, `find_similar_episodes` |
| Speaker + topic profiles | UX-13 | Speaker resolver (RSS notes → NER → voiceprint), agent tool `summarize_speaker` |
| Proactive editorial Today | UX-14 | Insight ranking job (BG), `IsightCard` taxonomy, push budget (1/day default) |
| Nostr-mediated cross-device + friend agent | UX-12 | Existing `NostrRelayService` + `AgentRelayBridge`, new `PermissionTier`, `toolOverrides` on `Friend` |
| Onboarding to first briefing in <90 s | UX-10 | Trial budget service, OPML detection animation |
| In-episode voice drop — context-aware agent actions while listening | UX-16 | `InEpisodeAgentController`, `TranscriptWindowProvider`, agent tools `seek_to_topic_start`, `create_clip_semantic`, `anchor_note`, `research_inline` |

---

## 5. Surface-by-Surface UX

> Each subsection is ≤500 words and links to the source brief. The brief stays canonical for full microinteraction tables, ASCII wireframes, and prose. This document captures **decisions, contracts, and handoffs**.

### 5.1 Now Playing

> Source: [docs/spec/briefs/ux-01-now-playing.md](briefs/ux-01-now-playing.md)

The hero surface and the user's most-stared-at screen. The transcript is the primary surface; the artwork is the frame. As audio plays, the active sentence rises and lights up, tinted by the speaker's diarized color (extracted from cover art for cross-show memorability). Every line is a doorway: tap to jump, hold to clip, double-tap to ask the agent. The waveform under the scrubber shows the *shape* of the conversation — speaker stripes, ad-break bands, silence — not just amplitude.

**Three modes redistribute weight:** artwork-dominant (default, 42 % artwork / 30 % transcript), transcript-focus (12 % / 60 %, entered by swipe-up), and scrub-mode (waveform expands to 220 pt with speaker stripes; transcript dims to 30 %).

**Three glass tiers, exclusive copper accent.** Hero glass for the transcript card, control glass for the transport row (one `GlassEffectContainer` so play / skip morph as one liquid bead), and a *single* tinted agent chip in the lower right — the only thing on screen that should glow. Copper (`accentPlayer`) appears here and nowhere else outside the player chrome.

**Mini-bar signature.** The persistent mini-bar across tabs uniquely shows the **active transcript line**, not just the title — a 1-line ticker. This is the visual signature that signals "this app understands the audio."

**Handoff contract.** Tap show name → Episode Detail (UX-03). Long-press transcript line → inline agent answer (≤3 turns); fourth turn promotes to Agent Chat (UX-05). Double-tap a noun the agent has linked → Wiki peek sheet (UX-04). Voice button on the agent chip → Voice Mode (UX-06). **Tap the agent chip while an episode plays → In-Episode Agent (UX-16)**: episode ducks, orb rises, user speaks a thought, agent acts (seek / clip / note / research) without leaving the player. Queue chip → Queue sheet (UX-02 owns).

**Microinteraction discipline.** Hold-to-clip is 600 ms with rising haptics (`.light` → `.medium` → `.heavy`); release before commit cancels. Scrub release snaps to the nearest sentence boundary within ±400 ms. The "Return to live" pill (Slack pattern) appears when the user manually scrolls; auto-scroll resumes only on tap. Speed dial appears on long-press of the play button (280 ms hold) — one-thumb operable, no menu dive.

**Edge cases.** Streaming transcript (live Scribe ingest): un-arrived region renders as faint blur + caret; tapping ahead shows *"Transcribing… tap to jump anyway."* Uncertain diarization: speaker chip reads "Speaker 2" with a dotted outline plus a long-press *Name this speaker* sheet. We never silently hide ambiguity. CarPlay handoff: we publish chapter, speaker, and current line through `MPNowPlayingInfoCenter` so CarPlay's surface can render speaker chip + active line.

**Performance budget.** 120 Hz on iPhone 15 Pro+, graceful degrade to 60 Hz on iPhone 13. Live glass + auto-scrolling transcript + waveform redraw is the most demanding surface in the app.

### 5.2 Library & Subscriptions

> Source: [docs/spec/briefs/ux-02-library.md](briefs/ux-02-library.md)

Library is the **calm room** of the app — editorial, still, generous. The agent surfaces are alive; this one is not. A user opens Library to *orient*, not *interrogate*. Querying belongs to Ask (UX-05/07); chatting belongs to Ask too; this surface answers one question with care: *what's here, and what's ready for me?*

**Layout.** Continue Listening rail (≤3 cards with progress arcs) at the top; segmented control [Subscriptions | Downloads | Discover]; below that, view toggle (grid 3-up iPhone / 4-up iPad, or dense list), sort, and filter chips (All / Unplayed / Downloaded / Has transcripts). Smart Playlists collapsed below. Show detail uses a 220 pt artwork hero with extracted-tint gradient bleed.

**Glass discipline.** Liquid Glass is **structural only** — tab bar, mini-player chrome, sticky filter bar, OPML sheet, transcription progress capsule. Cards and rows are matte so artwork breathes. This is the only major surface where T0 (paper) dominates over T1/T2 (glass).

**Discover sub-tab.** Agent-curated recommendation rails (*Because you finished X*, *New from voices you trust*, *One short episode for your commute*) — generated *offline*, not in real time. *Why this?* tap reveals one paragraph of agent rationale with sources. **Discovery is *pull*; Today (UX-14) is *push*.** Same agent, different surface.

**OPML import flow.** Drag-drop or file picker → parses → preview checklist (deselect any) → import. Mass-import shows a real progress bar plus per-show transcription queue indicator and is fully backgroundable via Live Activity. Malformed OPML: first 5 parse errors with line numbers, then *"Import what we could parse (212 of 247)."*

**Transcription status capsule.** Per-row: `Downloaded · Transcribing 64 %` or `Ready` or `Queue #3`. Tappable; expands inline to a 3-row queue preview with cancel-per-item. This is the surface where the transcription pipeline becomes legible.

**Local filter ≠ semantic search.** Library's filter chips operate on structured fields (status, duration, show, date, transcription state). Semantic search lives in Ask. Smart Playlists are local-structured; agent-generated playlists live in Discover with provenance.

**Handoff contract.** Subscription → show detail (Library-owned). Show detail → Episode Detail (UX-03). Episode Detail → Now Playing (UX-01). Discover card → Episode Detail or *Why this?* expansion (Library-owned).

**Edge cases.** Empty library: editorial hero + three stacked affordances (Import OPML / Paste RSS / Browse Discover); the agent does **not** speak here. Offline: subscriptions render from cache with an *Offline* glass chip top-right; downloads remain fully functional. Transcription quota exhausted: non-modal banner *"Transcription paused: monthly quota reached."* Actions: *Use on-device* / *Upgrade*; never blocks playback. Subscription removed by feed: show dimmed with `Feed gone` label; episodes still listenable; *Find replacement* hands off to UX-07.

### 5.3 Episode Detail & Transcript Reader

> Source: [docs/spec/briefs/ux-03-episode-detail.md](briefs/ux-03-episode-detail.md)

Where a podcast becomes a **document**. Three modes share the same content:

- **Episode Detail** — hero (artwork, show, guest, date, duration) + show-notes HTML + chapters list + agent-generated lede summary + "Open transcript" CTA + related-episodes rail. Floating glass mini-player.
- **Reading Mode** — player vanishes; single column; editorial type; subtle progress gutter on the leading edge; pure prose. The ad-free, listening-free reading room.
- **Follow-Along** — audio playing **and** transcript visible. Current sentence tinted; page auto-scrolls to keep it in the upper third (Kindle pattern). Vertical chapter rail on the trailing edge as a Liquid Glass strip with `glassEffectID` morphing to track scroll position. Tap any sentence to scrub audio there.

**Typography is the load-bearing decision.** Body is **New York** (Apple's editorial serif, optical sizing, Dynamic Type-aware). UI chrome and timestamps are SF Pro Text. Speakers are SF Rounded Semibold. The serif is what signals *document, not interface.* Body 19/30 (1.58 leading); 64-character optimum clamp engages from iPad width upward.

**Long-press is the primary interaction.** 300 ms long-press on a sentence lifts it with a 1.02× glass scale and soft haptic; selection handles snap to sentence boundaries; drag to expand to paragraph or contract to phrase. Action bar: *Copy · Share Image · Clip · Ask Agent · Bookmark*. Two-finger vertical drag = span-clip selection with waveform preview.

**Annotation taxonomy.** Highlights = soft yellow tint on the sentence's text background (never on the glass chrome). Notes = sentence-attached, surface as a tiny glass asterisk in the leading margin. Bookmarks = solid dots on the chapter rail at exact positions. All three roll up into a per-episode *Marks* tab and a global view, reachable via VoiceOver rotor.

**RAG citations.** Not chips (too noisy). 2 pt dotted underline + superscript glass dot. Tap → glass popover (*"Contradicted in Episode 142"*). Hand-off to UX-09 threading.

**Wiki links.** Solid 1 pt underline in `tintColor.secondary`. Tap pushes UX-04; long-press peeks a glass card.

**Live transcript UX.** Streaming Scribe ingest: partial transcript renders progressively, animated skeleton paragraphs below the cursor. Reads as `Transcribing… 38 %`; *Notify me when ready* CTA. ETA shown in caption; we never lie about the match.

**Quote-share card.** Generated image with artwork, speaker, timestamp, and a deep-link back. Three output formats: image, audio + subtitle-burned video, link.

**Clip composer.** Drag handles; sentence-snapped (word-snap via second long-press). Subtitle style row: *Editorial / Bold*, speaker-labels toggle. Output to clip-share targets (universal link, iMessage, Twitter/X, Mastodon, Nostr, copy audio).

**Edge cases.** No transcript / no budget: show notes become the readable object; one-tap *"Transcribe this episode (1 credit)."* Low-confidence regions (<0.6 confidence): 1 pt dotted underline; long-press shows top-3 alternates + *report correction*. 5 h Lex Fridman: virtualize the transcript (±2 chapters around scroll laid out); long-press the chapter rail expands a full-height speaker timeline minimap. Live episode: hide *Read transcript* until first chapter finalized; show *Transcribing live* badge.

### 5.4 LLM Wiki Browser

> Source: [docs/spec/briefs/ux-04-llm-wiki.md](briefs/ux-04-llm-wiki.md), [docs/spec/research/llm-wiki-deep-dive.md](research/llm-wiki-deep-dive.md)

The **second brain of the listener's library**. Britannica energy. Whole Earth Catalog density. Tufte respect for evidence. Stripe Press typography. Where the player is hot, the wiki is cool — a quiet, beautifully set reference work the user retreats into to *understand* what they have heard.

**Adapted from nvk/llm-wiki, with three departures.** (1) Generation is **automatic**, not user-invoked: new episode → transcript fetch → diarize → chunk → embed → page-update pass. (2) Citations are first-class — every claim points to `(episode_id, start_ms, end_ms)`, not a URL. Each rendered sentence has a tappable timestamp chip that calls `play_episode_at`. (3) The page taxonomy adds a **library-wide hub** for cross-show synthesis (the killer "*what does the podcast world say about Ozempic?*" feature) on top of per-podcast wikis.

**Confidence semantics shift from llm-wiki's "source quality" to our "extraction confidence"** — transcript right, diarization right, faithful synthesis. Cite the span; let the user tap-to-verify. Single-source claims render with an amber dotted left rule and the inline tag `(1 source)`. Zero-corroboration claims get `(uncorroborated)`. **Provenance-or-it-doesn't-render** — the only exception is *Definition* paragraphs, which may carry `[general knowledge]`.

**The page is paper, not glass.** This is the only major surface where Liquid Glass is reserved for *floating* elements only — the citation peek sheet, the wiki bar, the time-slider, the Generate handle, the contradiction popover. All glass is `.regular.interactive()` in `.rect(cornerRadius: 22)`. Body is New York serif at 17/26, generous measure (~62 ch on phone, two-column at 78 ch + 22 ch margin on iPad).

**Topic Page is the heart.** Definition (1 paragraph, italic, evidence-graded) → Who's discussed it (avatar row, links to UX-13) → Evolution timeline (compact horizontal strip; scrub renders the page *as it would have read* on that date) → Consensus vs Contradictions (split column) → Related (typed chips) → Citations (every episode + timestamp, sortable).

**Citation peek.** Hover/long-press a citation chip → glass sheet rises 1/3 from bottom, autoplays the cited 12 seconds, dismisses on release. Pulling up expands to full transcript at that timestamp (hands to UX-03).

**Generate Page flow.** Search bar that finds nothing reveals *"Compile this →"* glass handle. Pulling it down progressively unlocks the page — paragraph blocks slide up one at a time as the agent finishes each, citations resolving from `[…]` placeholders to amber pips. Expensive per regen — aggressive claim-level caching is required (only re-synthesize claims whose underlying transcripts changed).

**Graph view.** Burying it one level deep ("Wiki home → Graph") is deliberate. The graph is dazzling in demos and shallow in daily use. Reject the temptation to make it the home.

**Wrong-button protocol.** Long-press any sentence → contextual menu (*Cite · Compare · This is wrong · Quote*). *This is wrong* opens a 5-second voice-memo glass card; submission marks the claim as `contested` until next regeneration; the next regen must remove, downgrade, or surface a counter-citation.

**Boundary with UX-09 threading.** Threading is **episodic recall** ("here's every time keto came up"); wiki is **synthesized knowledge** ("what does keto mean in your library?"). Every threading detail sheet has a footer button: *Open the wiki entry →*. Single hand-off, never duplicated content.

**Boundary with UX-13 profiles.** Wiki person cards show only avatar, role, top-3 claims, *Open full profile →*. No bio prose. UX-13 owns the depth.

### 5.5 Agent Chat (Text)

> Source: [docs/spec/briefs/ux-05-agent-chat.md](briefs/ux-05-agent-chat.md)

iMessage's composure crossed with a magazine's voice. Not a chatbot UI — a *reading and listening surface* where you talk to every podcast you've ever subscribed to, and it talks back in artifacts: episode cards that play in place, transcript pull-quotes set in editorial type, wiki peeks, citations that hover like footnotes.

**Three principles.** (1) The answer is the hero, the mechanism is the footnote — tool calls collapse by default. (2) The chat knows where the playhead is — composer carries an ambient *Now Playing* chip the user can tap-attach. (3) Threads are conversations *with podcasts*, not sessions *with a bot* — each subscribed show gets an evergreen thread; cross-podcast questions live in *General*; briefings get their own threads.

**The signature decision: bubbles vs. unbubbled editorial.** User messages live in subtly tinted glass capsules, right-aligned. **Agent messages are unbubbled** — set in editorial serif, left-aligned, generous leading, like a column of *The Atlantic*. This separates us from every other chat app on iOS.

**Embedded media as Liquid Glass cards.** Six card shapes share a common shell (`GlassEffectContainer` spacing 32, cornerRadius 22): episode card (56 pt artwork + show/episode/progress/play glyph), clip card (waveform + scrubber + in/out timestamps), wiki peek (eyebrow + 2-line excerpt + chevron), transcript excerpt (small-caps speaker + italic body + glass leading rule), Perplexity citation (numbered footnote chip + sources row of glass pills), and comparison block (two-column pull-quotes for cross-podcast disagreement).

**Action-chip rail** sits sticky just above composer, contextual to the last agent reply. Max 4 visible, horizontal scroll for more. Primary action is `.glassProminent`; rest are `.glass`.

**Tool-Call Inspector** is the trust surface. Collapsed badge by default (*"▾ used 3 tools"*); two-finger tap on agent message instantly opens it; first-run coachmark explains it. Inspector lists each tool with timing, args (pretty-printed), and *Show evidence* link to the exact transcript chunks used.

**Now-Playing chip in composer.** Default-attached when audio is active; one tap to remove, never silent. Tap-and-hold attaches a *range* (use scrubber to pick).

**Drag-from-Library.** Episode dragged from UX-02 lands as an attachment chip in the composer; user types the question; agent receives episode as grounding context.

**Per-podcast thread proliferation policy.** Lazy-create on first interaction — a user with 60 subs does not start with 60 empty threads. Global search across threads in the thread list.

**Edge cases.** Agent thinking >2 s: replace typing dots with a *progress chip* showing the active tool name (*"searching transcripts… 1.2 s"*). >8 s: append a cancel affordance. Tool failure: inline glass *whisper* in muted red ("Couldn't reach the wiki for *Zone 2* — retrying in 5 s. [Retry now]"); failed tool stays in inspector with a red dot. Rate-limited: top-of-thread banner ("You've used 80 % of today's deep searches. Lighter answers below."), tone matter-of-fact. No internet: composer disables online tools; chip *Offline · using on-device transcripts only*. Streaming interrupted mid-tool: partial answer remains with a *Resume* pill.

**Friend agent DMs (UX-12) live in the same thread list** with a small relay glyph; message-stream UI is identical so users don't have to learn two surfaces.

### 5.6 Voice Conversational Mode

> Source: [docs/spec/briefs/ux-06-voice-mode.md](briefs/ux-06-voice-mode.md), [docs/spec/research/voice-stt-tts-stack.md](research/voice-stt-tts-stack.md)

The feature that should make a stranger gasp on first use. The marquee moment is **barge-in mid-briefing**: the agent is reading a 12-min TLDR, the user says *"Wait — who was that guest?"*, and within ~120 ms three things happen: the agent's voice ducks and dissolves mid-syllable; its glass orb inhales (collapses from speaking bloom to listening lens, pulses with the user's voice); the briefing's now-playing card dims and recedes one z-layer (*"holding your place"*). When the answer is delivered, the orb exhales and the briefing card swims back forward.

**Three principles.** The agent is a guest in your ear — it defers, always. Glass breathes — the orb's state is legible without text. Audio first, screen optional — every voice interaction works blind, one-handed, in a car, with AirPods only.

**Two voice modes, one visual language.** Push-to-talk (PTT) listens *only* during gesture / hot-phrase window. **Ambient (barge-in) listens automatically only while the agent itself holds the audio session** — never an always-on home-screen mic. This is the privacy contract.

**Single state machine drives the orb:** idle → listening → transcribing → thinking (with tool chip morphed from orb perimeter via `glassEffectUnion`) → speaking (96 pt bloom with 2.4 s breath rhythm) → bargeIn (snap to 0.7×, listening-blue tint, halt breath) → listening / idle.

**Latency budget (target 800 ms first audio frame, ceiling 2 s).** End-of-speech VAD ~250 ms + final STT commit 50–150 ms + LLM first token 300–700 ms (prompt-cached) + TTS time-to-first-byte 75–150 ms (ElevenLabs Flash v2.5 WebSocket) + network jitter 50–150 ms. To earn this: stream STT partials into LLM speculatively; pipe LLM response to TTS per sentence; pre-warm TTS WebSocket on VAD start; cache OpenRouter system prompt + tool schema (~200–400 ms saved per repeat turn).

**Stack.** Live STT: **Apple `SpeechAnalyzer` (iOS 26+)** — sub-second partials, ~2× Whisper Turbo, fully on-device. `SFSpeechRecognizer` for iOS-25-and-below fallback (we target iOS 26 so this is rarely hit). WhisperKit only behind a Pro toggle; cloud STT (Scribe) is **for offline transcript ingest only**, never the live loop. Conversational TTS: ElevenLabs Flash v2.5 streaming. Briefing TTS: ElevenLabs Multilingual v2 (or v3 GA) pre-rendered, played via `AVPlayer`. Fallback: `AVSpeechSynthesizer` Premium / Personal Voice for offline / privacy mode.

**Audio-session contract — the load-bearing decision.** State A (briefing only): `.playback + .spokenAudio`. State B (conversation active): `.playAndRecord + .voiceChat + setPrefersEchoCancelledInput(true) + .duckOthers`. **Never `.mixWithOthers`** — disables AEC. Switch is centralized in a single `AudioSessionCoordinator`; pre-warm on the wake gesture before VAD confirms speech.

**Barge-in detection.** AEC always on (~95 % of speaker leak gone). Apple's `SpeechDetector` (iOS 26) co-optimized with `SpeechTranscriber`, or Silero VAD via ONNX as fallback. Cross-correlate against a 500 ms ring buffer of TTS output to eliminate the agent's own voice. Require ~250 ms voiced audio before firing — slower than Alexa (100 ms) but eliminates iPhone-speaker false positives. **Optimistic preview**: orb's edge gets a faint rim-light the instant VAD triggers, *before* STT confirms. False-positive (cough) → rim fades, TTS resumes, no perceived stutter. This is the secret to the magical feel.

**Triggers.** A single `AppIntent` (`StartVoiceModeIntent`) covers Action Button, AirPods squeeze (long-press, user-assigned in Settings → AirPods → Press and Hold), Lock Screen control (`ControlWidget`), Siri ("Hey Siri, ask Podcastr…"), Spotlight, and CarPlay button. Wake-word ("Hey, podcast") deferred to v1.1 — invites parody and false triggers in podcast audio itself.

**Privacy.** Mic prompt fires on first voice-mode invocation, never at launch. On-device STT/TTS by default; one Settings toggle opts into cloud voices for higher quality. Captions always available. Voice queries processed on-device; only final text persists to chat history; audio buffers never written to disk. *Delete voice history* action in Settings.

### 5.7 Semantic Search & Discovery

> Source: [docs/spec/briefs/ux-07-search-discovery.md](briefs/ux-07-search-discovery.md)

**Search is not the agent.** The agent argues, summarizes, generates briefings. Search **shows you the evidence** and gets out of the way. The user often does not want a synthesis; they want the receipt.

The search bar lives at the top of the **Ask** tab — always-on, never collapsed, never hidden behind a magnifying glass. It is a destination, not a utility. It doubles as the agent composer: when the query reads as synthesis (starts with *summarize, compare, explain, what did, why does*), a single card appears at the top of the results: *"Ask the agent instead →"*. Search results still render below. **Never auto-route, always show evidence and offer escalation.**

**Result types — one feed, six card shapes.** Clip (waveform sliver, in-card play, timestamp), Episode (cover art, show name, duration, *Why it matched* snippet), Show (logo, episode count, follow state), Topic (typographic card to UX-04), Person (portrait or initial monogram to UX-13), Transcript moment (pull-quote treatment, speaker attribution).

**Scope chips** (horizontal, scrollable, multi-select with one exclusive group): *This show · This week · This month · Unlistened · By [Person] · On [Topic] · In transcripts · In wikis*. When the user types a name we recognize ("Tim Ferriss"), a `By Tim Ferriss` chip morphs into the rail via `glassEffectID`.

**Typeahead with semantic suggestions.** As the user types `keto`, two sections: *Literal matches* (3 episodes whose titles contain "keto") and *Semantic neighbors* (clips about ketosis, fasting, low-carb), the latter with a small `~` glyph.

**Long-press peek.** Any clip / transcript card → glass sheet rises 2/3 height showing 60 seconds of transcript surrounding the match, with the match line glowing. Release dismisses; drag up commits to the full transcript view.

**Voice search.** Holding the mic dims the rest of the screen to 30 %; the search field becomes a glass capsule that pulses with the audio waveform. Releasing without speaking dismisses; speech commits the query; results stream in beneath while still listening.

**No-results escalation.** *"Not in your library. Search the open web?"* card → fires `perplexity_search`. A tertiary action *Find a podcast that covers this* → fires `find_similar_episodes` against the open-web result's topic.

**Result rendering.** Each result type gets a slightly different glass treatment so the eye learns to scan: clips on capsule glass with waveform watermark, episodes on 16 pt-corner glass with cover-art bleed, shows tinted with the show's dominant color (8 % opacity), topics paper-feel hairline, transcript moments italic with oversized open-quote glyph. **One container, morphing.** All wrapped in `GlassEffectContainer(spacing: 12)` so cards near each other blend on scroll bounce — the library feels physically continuous.

**Recents privacy.** Recents persist in App Group store. Per-tab clear; *Incognito search* toggle (no logging, no embedding cache) surfaced in chip rail when active so users don't forget.

**Edge cases.** Transcription backlog: card with hairline progress shimmer (*"Transcript indexing — 73 %. We'll re-rank when ready."*); never hide the episode, never lie. Stale embeddings after model upgrade: background re-index; search still works on old index. Offline: search runs locally against the cached vector index with banner.

### 5.8 AI Briefings / TLDR Player

> Source: [docs/spec/briefs/ux-08-briefings-tldr.md](briefs/ux-08-briefings-tldr.md)

A briefing should not feel like a podcast you happened to receive. It should feel like a podcast that was **made for you, this morning, by someone who has been listening on your behalf.** Visceral target: *NPR's All Things Considered crossed with The Atlantic's print layout.* This surface is the agent's **stage** — the only place it is the producer, not the assistant.

**Object model.**
```
Briefing
 ├─ intro sting
 ├─ Segment[] (title · TTS body · original-audio quotes? · sources[])
 │    └─ Branch[] (forks; Briefing-shaped sub-objects with breadcrumb back)
 ├─ outro sting
 └─ metadata: scope, length_target, generated_at, sources[]
```

**Branch contract: pause-and-resume**, not fork-and-replace. The main thread freezes at the sample the user spoke over; the branch plays as a parenthetical; on completion or *back*, main resumes from that sample. Branches persist and resurface on re-listen as optional side-paths in the rail.

**Compose surface.** Preset row (Daily / Weekly / Catch-up on… / Topic deep-dive), freeform *"Brief me on…"* field, length puck (3 / 8 / 15 / 25 min), scope chips (*My subs · This show · This topic · This week*), pinned recents.

**Player surface.** **Transcript, chapter list, and segment rail are the same surface in three densities**, not three UIs. Collapsed: horizontal glass strip. Up: chapter list with attribution chips. Up again: full live-transcript auto-scrolling with playback. Active pill morphs into the next via `glassEffectID` while a thin gradient ribbon sweeps under the title (250 ms).

**Material.** Now-Playing uses neutral glass over episode artwork; briefings use a **warm-tinted variant** — `glassEffect(.regular.tint(brassAmber.opacity(0.18)).interactive(), in: .rect(cornerRadius: 28))` — over a slow-drifting generative gradient (warm ink, brass, parchment). **Brass-amber glass = the agent owns this audio.** Briefings titles in *New York Large* 34 pt with a dropcap on each segment's leading word.

**Cinematic intro / outro.** Two-second open: hairline rule draws edge-to-edge, title fades in as the sting plays, rail crystallizes from the rule (the rule *is* the rail's spine). Outro reverses to a point, fades.

**Voice barge-in.** Audio ducks 12 dB. Glass deepens tint with an inner glow on its leading edge — *listening*. Segment title freezes mid-word, italicized. Agent's answer lifts as a second glass card above the rail; on resume it morphs back as a branch crumb. *Return to briefing* chip with a 4 s auto-resume ring.

**Generation in progress.** Stream-as-ready: segment 1 plays before the last synthesizes. Mid-generation cancel offers *"Save partial briefing?"* — partials are valid artifacts with a torn-edge cover motif.

**Dedicated library shelf.** Briefings live in a separate, brass-amber-tinted shelf — never mistaken for an episode. Filter by date, scope, length. 30-day auto-archive unless saved.

**Boundary contract: three briefs, one object.** UX-08 owns the **player** (this section). UX-05 hosts the **briefing card** in chat. UX-14 hosts the **daily edition delivery** (Today + push). The `BriefingComposer` and `BriefingPlayer` engines are owned here; the cards and pushes elsewhere are views onto the same object.

**Edge cases.** Original-audio fetch fails: substitute paraphrased TTS, mark the chip *paraphrased* — never silently drop a citation. Briefing too long for corpus: agent counter-proposes (*"12 min on this, or 25 with adjacent shows"*). Unfeasible scope: empty state offers a `perplexity_search` *web briefing* with a cool tint, distinct texture, labeled out-of-corpus. Already-heard segments flagged with badge; setting controls skip vs include.

### 5.9 Cross-Episode Knowledge Threading

> Source: [docs/spec/briefs/ux-09-cross-episode-threading.md](briefs/ux-09-cross-episode-threading.md)

The connective tissue. A second voice in the margin: calm by default, alive on demand. Where the wiki destination is the **library**, threading is the **librarian who finds you in the stacks**.

**Three layers, never a tab.**
- **Layer A — Now Playing Context Ribbon.** Thin, dismissible glass strip pinned to the bottom of the player above the transport controls. Appears only when the agent has detected an active topic with **≥3 prior mentions**. Auto-fades after 6 seconds if ignored. Single counter glyph: *"7 ↺"*. **Cap at 1 ribbon per 10 minutes of listening, never within 30 s of a chapter boundary or user action.**
- **Layer B — Transcript inline citations.** Topics get a thin parchment underline (1 px hairline) in editorial serif; long-press reveals a peek at 40 % detent. Coordinated with UX-03's text styling; we provide the underline token + long-press behavior.
- **Layer C — Thread Detail Sheet.** Full-screen modal sheet (not a destination page); dismiss with swipe-down. Three tabs: **Timeline · Contradictions · Evolution**. Defaults to whichever has the most signal.

**Color semantics.** Threading neutral = parchment underline (#E6DCC8 light / #3A352B dark). Contradiction = amber seam (#D9A441), 2 px, animated shimmer-once on first appearance. Evolution = gradient cool (#6B9BD1) → warm (#D88A5C) along chronological axis. Confidence-dim = 50 % opacity with dotted, not solid, underline.

**Confidence vocabulary.** Below 0.75 confidence, contradictions render with a dotted amber underline and a footer reading *"Agent's read — may not be a true clash."* Above 0.9, solid seam, no caveat. We never assert contradiction with certainty unless verbatim quotes oppose on the same noun phrase.

**Sparse-evidence rule.** No ribbon, no underline below 3 mentions. Threading is reserved for *patterns*, not coincidences.

**Scrub-the-timeline microinteraction.** In the timeline tab, horizontal strip of clip pills. User drags a finger across; a magnifier glass capsule (true `glassEffectID` morph) rides under the finger, expanding the hovered pill 1.4× and previewing 2 seconds of audio at low volume. Release commits → opens player at that clip.

**Boundary with UX-04.** Open *wiki entry for "ketogenic diet"* button at the bottom of every detail sheet is the primary reinforcement of the threading-vs-wiki boundary: episodic recall here, synthesized knowledge there.

**Boundary with UX-13.** Speaker chips in transcript long-press into UX-13 peek sheets (UX-13 owns); threading owns the underline + long-press *behavior* on topic chips.

### 5.10 Onboarding & First Run

> Source: [docs/spec/briefs/ux-10-onboarding.md](briefs/ux-10-onboarding.md)

The first five minutes must feel like the app was waiting for *this user specifically*. Onboarding's job is not to explain the app; it is to demonstrate that the app already understands them. By the time the first briefing fades, the user has already used four of the deepest features — import, identity, agent, voice — without ever feeling configured.

**Resolution of the discriminating decision: trial budget (Option A).** First briefing runs on a small house-funded LLM + TTS budget (~$0.05/user, device-attested, capped at one briefing + ~2K agent tokens). BYOK is gently introduced *after* the user is hooked, at the second substantial agent action. Option B (text-first) ships fast but loses the magical moment; Option C (BYOK before the magic) is a death spiral. PROJECT_CONTEXT's "BYOK, no default key" stance is honored everywhere except this single onboarding window.

**State machine.** S1 Welcome → S2 Import (OPML / clipboard / starter pack) → S3 Identity (auto, ~3 s) → S4 Agent (trial-on, BYOK soft) → S5 Voice persona (optional) → S6 First Briefing (mic permission requested in-context here) → S7 All Set.

**S1.** A single editorial sentence over a moving gradient — *"Talk to all your podcasts."* No logo splash, no carousel. Power-user escape: low-contrast *"I know what I'm doing"* link → 30-second condensed flow (paste OPML, paste OpenRouter key, done).

**S2 — the detection moment.** OPML imports and 47 shows fan out as the user watches; ovals are real artwork crops, not placeholders. Total animation: 1.4 s. Empty library → curated 12-show starter pack. *"Auto-detect from Apple Podcasts" is platform-impossible — we are honest in copy.*

**S3 — the quiet promise.** Identity generated invisibly. A constellation animation; one line: *"This stays on your device."* No keys shown unless asked. The term "nsec" never appears outside Settings.

**S4.** The agent is introduced as having *"read every episode you subscribe to"*; trial budget explained in two sentences; *"I have a key already"* opt-out present.

**S5.** Three voice persona cards (Aria / Kai / Sage) with one-tap preview. Skippable; default Aria.

**S6 — the magical moment.** *"Your week, in 4 minutes."* Briefing intro draws a horizontal timeline of dots (one per included show); play button breathes (subtle scale 0.98 ↔ 1.00, 2 s cycle). Mic permission requested in-context; on deny, briefing plays through normally and the *"Tap to interrupt"* pill becomes *"Tap to ask"*. **First audio chunk must stream within 6 seconds or the magic dies.**

**S7.** *"You're set."* Three checks: 47 shows imported, agent active (trial), daily briefing 7:30 AM (changeable). *Open app →*.

**Quiet Mode (BYOK declined / trial expired).** Playback, transcripts, library work fully; agent and briefings degrade to **read-only summaries from cached metadata**. A persistent but unobtrusive banner offers the BYOK walkthrough. **No feature is hidden, only agent intelligence is paused.**

### 5.11 Ambient Surfaces

> Source: [docs/spec/briefs/ux-11-ambient-surfaces.md](briefs/ux-11-ambient-surfaces.md)

Phone, watch, car dashboard, and AirPods are one product — a single agent always one squeeze away. The screen-off experience is not a stripped-down app; it is the app's **resting state**. Three actions are always one gesture away: **play, ask, brief me.**

**Lock Screen Live Activity (playing).** `GlassEffectContainer(spacing: 24)` with art tile + transcript line in 15 pt SF Pro Text on `.regular` glass. Tint sampled from album art (dominant + complement) so the activity feels native to *this* episode. **Throttle transcript-line updates to one per transcript-segment boundary (~6–10 s), not per word** — ActivityKit budgets ~16 high-frequency updates/hr.

**Dynamic Island states** morph via `glassEffectID` + `@Namespace`: idle → playing (compact: art L, waveform R) → expanded (title + transcript line + scrub + ask) → thinking (three orbs unioned via `glassEffectUnion`, pulsing L→R) → answer-ready → playing. Nothing fades; everything morphs.

**Home widgets** respect `widgetRenderingMode`. In `.accented`, artwork uses `widgetAccentedRenderingMode(.monochrome)`; briefing waveform stays accent-tinted. Small: now playing or *Brief me*. Medium: + 2 briefings + top thread. Large: + 3 threads + ask box.

**Lock Screen widgets.** Rectangular: *Ask agent* deep-link. Circular: play/pause or briefing-ready badge.

**CarPlay.** Strictest contrast environment. **No Liquid Glass blur — the API doesn't expose it and driver attention demands flat.** Min 22 pt body, 34 pt title Semibold, dark `#0A0A0F` backgrounds. Persistent voice mic button bottom-right of every screen. Pulses *only while agent generates* — not while listening (driver feedback is auditory). **No ambient barge-in by default in CarPlay** — false-positive risk at highway speed; PTT only via steering wheel + Siri-style alert tone.

**Apple Watch.** Tonal SF Symbols, full-bleed art on the player, corner complication uses `.accentedRenderingMode(.full)`. Crown scrubs at two rates by velocity: shallow ±5 s, aggressive ±30 s (chapter-jump). Watch standalone RAG is **not in v1** — voice mode degrades to "ask anyway, syncs when phone reachable" with clear UX.

**AirPods.** Single squeeze = play/pause (system default; do not override). Double = skip, triple = previous. **Long press = voice mode** (user opts in during onboarding; one app system-wide can claim it). Soft chime in the buds when listening — distinct from Siri's so blind users can disambiguate.

**Action Button + Lock Screen control + Siri Shortcut + Spotlight + CarPlay button** all share a single `StartVoiceModeIntent`. Document the AirPods setup once in onboarding; users assign in Settings → AirPods → Press and Hold AirPods → Shortcut.

**Boundary.** UX-11 owns the *persistent surfaces*; UX-14 owns *notifications* (which are events, not surfaces). UX-06 voice and UX-08 briefings *render into* the ambient surfaces; we own the data contract.

**Privacy on Lock Screen.** Settings → *Hide transcript on Lock Screen* (default ON for episodes the user flags sensitive). Briefing-rendering Live Activity copy uses *"Preparing your briefing…"*, never *"agent generating."*

### 5.12 Nostr Communication

> Source: [docs/spec/briefs/ux-12-nostr-communication.md](briefs/ux-12-nostr-communication.md)

Nostr is **not a tab. It is a relay layer** that lets people — and the agents they trust — exchange podcast knowledge as if they shared one library. A clip you send a friend lands in their app as a *playable, transcript-aware artifact*, not a URL. A question your friend's agent asks of your library returns prose, not a payload. A command you fire from your laptop arrives at your phone as a normal agent reply with a small *via desktop* glyph.

**Three principles.** Provenance is ambient, never a banner. Trust is tiered, not binary. The wire is invisible until it matters.

**Permission tiers as glass weight.** *Reader* (queries only) is a thin, low-saturation capsule. *Suggester* (drafts that need user approval) has medium tint with soft glow. *Actor* (full tool access, scoped by per-tool overrides) is `.glassProminent` with a tint matching the friend's accent. **Visual weight matches power.** Switching tiers is a morph (`glassEffectID`), never a segmented control.

**Two voices in one thread, four message kinds.** My human messages: right-aligned tinted glass capsule (system accent at 18 %). Friend's human: left-aligned neutral glass with friend avatar at 24 pt. **My agent: left-aligned, unbubbled editorial serif (matches UX-05).** Friend's agent: same, with a hairline vertical glass rule on the leading edge tinted to friend's accent + small-caps eyebrow `Maya's agent · 14:02`. **The eyebrow is the trust signal:** human-from-friend has none (we trust faces); agent-from-friend always carries one (we verify machines).

**Provenance chips.** 9 pt mono caption with a 6 pt circular avatar, prefixed `via`. Always at the trailing edge of the metadata row, never in headlines. Tap → sheet with original Nostr event id (copyable), the tool call, and *Revoke this action* button if reversible.

**Permissions infrastructure already present in the template.** `Friend.identifier` is hex pubkey; `NostrPendingApproval` queues first-contact handshakes; `NostrRelayService` (WebSocket + reconnect + ACL) and `AgentRelayBridge` already run the agent loop for inbound DMs. We extend with `permissionTier: PermissionTier` and `toolOverrides: [String: Bool]` on `Friend`.

**Cross-device own-DMs.** From a Nostr client on desktop you send your own npub a DM ("Make a 12-min briefing for tomorrow's commute"). Phone agent runs `generate_briefing`, replies on the same thread. Phone chat shows the message with a `􀙗 desktop` glyph — same prose, different origin. *My Other Devices* is its own pinned thread.

**Tool-exposure audit (security-critical).** Not every tool is safe to expose to friend-pubkey-driven calls. Default exposures:
- **Reader tier:** `query_transcripts`, `query_wiki`, `summarize_episode`, `find_similar_episodes`. No mutations.
- **Suggester tier:** above + drafts of `play_episode_at`, `generate_briefing` that surface as approval cards on the user's device.
- **Actor tier:** all of the above + `play_episode_at`, `set_now_playing`, `generate_briefing`, `send_clip` — gated by per-tool overrides.

**npub QR reveal.** Cinematic moment: card lifts off its row, expands to fill the screen, QR draws on with a 320 ms staggered shimmer (rows of QR modules cascade in). Tap dismisses with reverse morph. A single line below: `npub1…7q9` in mono with copy glyph.

### 5.13 Speaker & Topic Profiles

> Source: [docs/spec/briefs/ux-13-speaker-topic-profiles.md](briefs/ux-13-speaker-topic-profiles.md)

A podcast library is not a collection of episodes — it is a collection of **voices and ideas**. The same names recur across years; the same arguments mutate from show to show. Today's apps are blind to this; we refuse that. **A speaker is a first-class noun in this app. So is a topic.**

**Profiles are destinations, not summaries.** UX-04 wiki holds the encyclopedic three-line bio + headline links and *opens into* these profile pages. The wiki is the index; we are the article. Profiles are pushed onto the navigation stack of whichever tab summoned them — never their own tab.

**Speaker profile IA.** Header (3:4 portrait hero, name, role pill, stats row, *Follow ●* + *Brief me* + *Share*) → Bio (LLM-generated, sourced) → Most-discussed topics (chip cloud, weighted) → **Stance evolution** (per topic, expandable; each card plays a 12 s pre-roll + 30 s body + 5 s post-roll on tap) → Recent appearances (rail, reverse-chronological) → Best clips (agent-curated, 3–5) → Sources & corrections.

**Topic profile IA.** Header → Definition → Speakers who discuss it (faces row) → Episodes that discuss it (rail) → Timeline (when first surfaced + key inflection points) → **Contradictions** (paired-quote cards) → Subtopics & parent topics (graph chips) → Sources & corrections.

**Follow / notification settings** live as a peek-up sheet from the *Follow ●* pill, **not a separate screen**. New-appearance toggle, delivery (Proactive feed / Push / Both), confidence threshold slider, mute (1 day / 1 week / forever).

**Photo treatment.** Hero portrait at 3:4, 280 pt tall on iPhone, 24 pt corner radius, soft gradient bleed of the photo's extracted dominant color into the page background (luminance clamp for AA contrast — same algorithm as UX-02 show-detail header). When no photo: **initials monogram** (two letters, `.largeTitle` rounded bold) in a circular glass disc tinted from the speaker's most-frequent show's accent. **Never use a generic silhouette stock graphic.**

**Speaker identity resolution (the load-bearing problem).** Diarization gives voices; matching to a *named identity* across shows is hard. Tiered resolver: RSS show-notes first → transcript NER + co-reference → voiceprint clustering across the library → user's disambiguation choices fed back. Confidence surfaced via the threshold slider in Follow settings. Unknown guests offered *Help name this voice*: 4 s clip play, three candidate names suggested, user picks or types.

**Ambiguous identity (two people, same name).** Disambiguation chooser at page open: 2–3 candidate cards (portrait, role, last show context). User's pick remembered per-show context as a tiebreaker; resolver updated. If the chooser cannot be presented (incoming deep link), default to highest-confidence candidate with non-modal banner: *"Did we pick the right Sarah Chen? [Switch]"*.

**Photo licensing.** Prefer Perplexity-cited Wikimedia / Commons sources with explicit license metadata; fall back to verified social avatar (per-platform terms apply); fall back to monogram. Never mass-cache without per-image attribution. *Suggest correction* path lets a guest replace their own photo. Legal review required before ship.

### 5.14 Proactive Agent & Notifications

> Source: [docs/spec/briefs/ux-14-proactive-agent-notifications.md](briefs/ux-14-proactive-agent-notifications.md)

Most apps treat notifications as a megaphone. We treat them as a **front page** — one daily edition, edited by the agent, delivered with the calm of a paper landing on the porch.

**Three principles.** **One push a day, by default.** Everything else pools in Today, the in-app digest. Spam is a design failure, not a settings problem. **Today is editorial, not a feed** — magazine cover, one hero, three to five cards, generous whitespace, *finishable* in under a minute. **Confidence is visible** — solid rule for grounded, dashed rule and italic eyebrow for inferential.

**Insight Card taxonomy.**
| Type | Eyebrow | Confidence | Default Push |
|---|---|---|---|
| Briefing | `MORNING EDITION` | solid rule | yes (1/day) |
| Drop | `NEW · <show>` | solid rule | no |
| Thread | `THIS WEEK · CROSS-EPISODE` | solid rule | no |
| Echo | `YOU ASKED · <date>` | dashed, italic | no |
| Friend | `FROM <name> ·` Nostr glyph | solid rule | priority-only |
| Transcript | `READY · TRANSCRIPT` | solid rule | never |

**Smart Push Budget.** Default 1/day; max 3; off. Surplus pools in Today / Inbox. After day 7, surface a tooltip: *"Want more? Raise your push budget in Settings."* Never auto-raise.

**Confidence thresholds.** Echoes surface ≥0.65; solid rule ≥0.80. *This wasn't useful* taps are ground-truth ranking input; three taps in 30 days mutes that type for a week with confirmation.

**Vacation Mode.** Today and pushes pause; Inbox accumulates. On resume, hero is an *Editor's Note*: *"You were away 6 days. 23 items waiting; here are the 3 the agent thinks matter."* Gap-day editions remain via pull-down (7-day window).

**Background scheduling reliability.** `BGAppRefreshTask` is opportunistic. Trigger briefing generation at 4 AM via APNs background push; on-device fallback composes lazily on first open if missed. Briefing failures **never push broken content** — user opens to *"Briefing didn't compose this morning — try generating one now?"* with one-tap retry.

**Cross-device dedup.** APNs collapse-id keyed to `{user, edition_id}` so iPad + iPhone never double-push.

**Live Activity policy.** Briefings only. Briefings >12 minutes risk system kill — hand off to Now Playing chrome at 80 % completion. Non-briefing items never use Live Activities.

**Privacy.** Push body never reproduces the original question text (Echo cards) — user must open Today.

**Boundary contract.** UX-14 owns the *Today* editorial surface, the *Inbox*, push, and notification settings. UX-08 owns the briefing player itself. UX-13 emits `speaker_appeared` and `topic_referenced` events that this surface consumes. UX-12 emits friend-clip events keyed to a Priority bit per friend (≤1 push/friend/24h).

---

## 6. Liquid Glass Design System (Visual + Motion + Haptics + Sound)

> Source: [docs/spec/briefs/ux-15-liquid-glass-system.md](briefs/ux-15-liquid-glass-system.md)

This is the **ground truth** for every surface designer. If a token is not here (or in the brief), it does not exist. If a surface contradicts this, the surface is wrong.

### 6.1 Five-tier material system

| Tier | API | Use |
|---|---|---|
| **T0 Hairline** | none — solid `bg.elevated` + 0.5 pt hairline | Pure reading surfaces (transcript, wiki body) — glass would distract |
| **T1 Clear** | `.glassEffect(.regular, in: rect)` | Default toolbars, segment controls, secondary chips |
| **T2 Tinted** | `.glassEffect(.regular.tint(c), in: rect)` | Mini-bar, agent reply bubble, friend incoming |
| **T3 Interactive** | `.glassEffect(.regular.tint(c).interactive())` | Buttons, agent orb, draggable scrubber thumb |
| **T4 Cinematic** | `GlassEffectContainer` + tinted children + parallax | Now Playing full screen, voice mode, briefing player |

**Rules.** Always wrap multiple T2/T3 elements in `GlassEffectContainer(spacing:)` — required for morph and perf (default spacing 24 pt; bump to 40 pt when elements should *not* merge). Never stack T2 over T2 (second blur turns to mud — use T0 underneath). Refraction is automatic in iOS 26 — do not fake it with manual gradients. Use the system's auto light/dark adaptation; do not hardcode opacities. Edge corners come from the corner scale: `Corner.lg` (16) cards, `Corner.xl` (24) sheets, `Corner.bubble` (18) chat bubbles, `Corner.pill` (14) chips — never custom values.

### 6.2 Identity tints — the three signals must be distinguishable in 200 ms peripheral vision

| Role | Light | Dark | Used for |
|---|---|---|---|
| `accent.player` | `#E94B2B` | `#FF6A4A` | **Copper — exclusive to Now-Playing surfaces.** Mini-bar progress line, full-player chrome, `playerOrb` button, home-screen mini-thumbnail badge. Nothing else. |
| `accent.agent` | `#5B3FE0`→`#2872F0` gradient | `#7A5BFF`→`#4D8FFF` | **Electric indigo→azure — agent identity.** Orb, agent-CTA buttons, agent message tint, voice-mode backdrop. |
| `accent.wiki` | `#1F6E55` | `#46C29A` | **Moss — knowledge surfaces.** Wiki citations, leaf glyph. |
| `accent.friend` | `#D9892F` | `#F2B45C` | **Amber — Nostr friend / friend-agent action.** 2 pt amber seam on the leading edge of any element initiated by a friend. |
| `accent.live` | `#C72D4D` | `#FF5577` | Recording / "agent listening" — signal red. |

**Rule of mutual exclusion.** A card cannot be both *from a friend* and *agent-generated*. If the agent forwards a friend's message, the bubble is friend (amber), with a small agent orb badge.

### 6.3 Typography

- **Primary face: SF Pro (system).** SF Pro Rounded reserved for chips, badges, and the agent voice (carries the "warm" register).
- **Editorial display: New York (system serif)** for hero titles only — episode titles on Now Playing, wiki article titles, briefing intros, agent prose in chat. Reserved for sizes ≥19 pt; loses character below.
- **Mono: SF Mono** for timestamps and code.
- Tokens: `displayHero` (NY 34/38), `displayLarge` (NY 28/32), `titleLg` (SF 22/26), `headline` (SF Rounded 17/22), `body` (SF 17/24), `caption` (SF 13/17), `monoTimestamp` (SF Mono 13/17).
- **Dynamic Type to AX5.** Every token must scale.

### 6.4 Motion language — "motion communicates causality"

| Curve | Spec | Use |
|---|---|---|
| `motion.snappy` | `spring(duration: 0.22, bounce: 0.12)` | Press feedback, chip toggles, scrubber ticks |
| `motion.standard` | `spring(duration: 0.35, bounce: 0.15)` | Default — sheet open, card expand, glass morph |
| `motion.considered` | `spring(duration: 0.55, bounce: 0.10)` | Now-playing transitions, agent surface entrance |
| `motion.cinematic` | `spring(duration: 0.85, bounce: 0.05)` | Full-screen player open, voice-mode entrance |
| `motion.bouncy` | `spring(duration: 0.45, bounce: 0.32)` | Celebratory only (briefing complete, save) |
| `motion.linear` | `linear(duration: continuous)` | Scrubbers, progress bars, waveform draw |

**Choreography rules.** Stagger don't simultaneous (40–60 ms between elements, max 5; beyond that, fade the group). Out before in (outgoing finishes 80 % of exit before incoming starts). Hero anchors share `matchedGeometryEffect` + `glassEffectID`; everything else cross-fades. Parallax: artwork on Now Playing scrolls at 0.6×, transcript at 1.0×, max delta 24 pt. **Scrubbing is linear, never spring** — springs feel laggy on continuous user input. Glass merges only inside containers — outside `GlassEffectContainer` glass elements cross-fade rather than morph.

### 6.5 Haptic + sound vocabulary

Extends existing `Haptics.swift` (do not restructure). New patterns: `playStart`, `playPause`, `scrubTick`, `agentListenStart`, `agentSpeakStart`, `agentInterrupt`, `bargeAccepted`, `clipMarked`, `friendIncoming`, `briefingStart`, `briefingComplete`. All cues are short (≤450 ms), -18 LUFS, ducked under any active audio, with a "subtle" 50 % gain variant for the in-podcast experience.

Signature sound cues: `agent.listen.up` (soft inhale, two-tone rising G→D, 280 ms), `agent.speak.in` (warm fade-in chime D5, 220 ms), `agent.barge` (brief reverse-swell descending, 180 ms), `transcribe.done` (two-note arpeggio A4→E5, 320 ms), `briefing.intro` (editorial signature, 4-note ascending, 1.4 s), `friend.knock` (two soft taps warm, 240 ms).

**Rule.** Never play a sound *and* fire a haptic for the same event unless explicitly listed; the body double-counts.

### 6.6 Accessibility constants

Every surface must pass: Dynamic Type to AX5 (single column at AX3+; eyebrow stacks at AX4+); WCAG AA 4.5:1 on body text against worst-case wallpaper; Reduce Motion (springs → cross-fades, breath rhythms → static states); Reduce Transparency (T2/T3 → solid `surfaceElevated` + 1 pt hairline, tints preserved); color independence (state expressed by shape *and* color, never color alone); 44 × 44 pt minimum hit targets with 8 pt slop on chips; haptic-only fallback for every audio cue.

---

## 7. Technical Architecture

> Source: [docs/spec/research/template-architecture-and-extension-plan.md](research/template-architecture-and-extension-plan.md), [docs/spec/research/skeleton-bootstrap-report.md](research/skeleton-bootstrap-report.md)

### 7.1 What we inherit from the template (do not rebuild)

**Already shipping in the renamed Podcastr skeleton:**

- **Entry & app lifecycle.** `AppMain.swift` (`PodcastrApp` `@main`), `App/RootView.swift` (TabView with Today / Library / Wiki / Ask / Home / Settings), `App/AppDelegate.swift` (deep-link routing, notification action buttons, shake handler).
- **Domain models.** `Item`, `Note`, `Friend`, `AgentMemory`, `Anchor` (discriminated union), `Settings`, `AgentActivity`, `NostrPendingApproval`. All `Codable + Sendable`; every decoder uses `decodeIfPresent` for forward-compat.
- **State.** `State/AppStateStore.swift` plus six extension files (`+Items`, `+Notes`, `+Memories`, `+Friends`, `+Nostr`, `+AgentActivity`, `+DerivedViews`). `@MainActor @Observable`. Single source of truth.
- **Persistence.** `State/Persistence.swift` encodes the entire `AppState` as JSON, writes to App Group `UserDefaults` keyed `podcastr.state.v1`. `iCloudSettingsSync` already merges arbitrary `Settings` fields key-by-key.
- **Agent loop.** `Features/Agent/AgentChatSession.swift` plus `AgentOpenRouterClient.swift` runs the SSE streaming loop with up to 20 turns. `Agent/AgentTools.swift` + `AgentToolSchema.swift` + `AgentPrompt.swift`, with tool dispatchers split into `+Items`, `+NotesMemory`, `+Reminders`, `+DueDates`, `+Search`. `AgentRelayBridge.swift` runs the same loop at 8-turn cap for inbound Nostr DMs.
- **Nostr subsystem.** `NostrRelayService` (WebSocket + kind-1 + reconnect), `NostrKeyPair` (P256K), `Bech32`, ACL (`nostrAllowedPubkeys` / `nostrBlockedPubkeys` / `nostrPendingApprovals`). The whole subsystem is kept verbatim.
- **Services.** `KeychainStore`, `OpenRouterCredentialStore`, `ElevenLabsCredentialStore`, `NostrCredentialStore`, `BYOKConnectService` (PKCE), `NotificationService`, `BadgeManager`, `SpotlightIndexer`, `iCloudSettingsSync`, `DataExport`, `DeepLinkHandler`, `VoiceItemService` (`SFSpeechRecognizer` dictation, harden for full-duplex), `ChatHistoryStore`, `ReviewPrompt`, `UserIdentityStore`.
- **Design.** `AppTheme` (split by concern), `GlassSurface` (calls native iOS 26 `.glassEffect()`), `Haptics`, `PressableStyle`, `ShakeDetector`, `MarkdownView`, `AsyncButton`.
- **Feedback.** Shake → `FeedbackWorkflow` state machine, `FeedbackStore` in `Documents/feedback_threads.json`. Wire `FeedbackView.performSubmission` to a backend later; that hook exists.
- **Build & CI.** `Project.swift` (iOS 26 deployment target, Swift 6 strict concurrency, App Group `group.com.podcastr.app`, bundle ID `com.podcastr.podcastr`, URL scheme `podcastr://`); `.github/workflows/{test,testflight}.yml`; `ci_scripts/`.

The skeleton has empty stubs at `App/Sources/{Audio/AudioEngine, Briefing/BriefingComposer, Knowledge/{VectorIndex, WikiPage}, Podcast/{PodcastSubscription, Episode}, Transcript/Transcript, Voice/AudioConversationManager}.swift` and feature view stubs at `Features/{Today, Library, Wiki, AgentChat (AskAgentView), EpisodeDetail, Player, Voice, Briefings, Search (PodcastSearchView)}/`. **All net-new code lands inside these stubs or alongside them.**

### 7.2 New modules

| Module | Files | Purpose |
|---|---|---|
| `Audio/` | `AudioSessionCoordinator`, `PlaybackEngine` (+`+RemoteCommands`, `+NowPlaying`), `NowPlayingMetadataPublisher`, `RemoteCommandHandler`, `AudioRouteObserver` | Single owner of every `AVAudioSession` transition. AVPlayer wrapper. `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`. |
| `Podcast/` | `Subscription`, `Episode`, `RSSFeedParser`, `OPMLImporter`, `EnclosureDownloader`, `FeedRefreshScheduler` | RSS / OPML / Podcast Index / iTunes Search; `BGAppRefreshTask` scheduling. |
| `Transcript/` | `TranscriptChunk`, `TranscriptSource` enum, `PublisherTranscriptFetcher`, `ScribeTranscriptionClient` (ElevenLabs Scribe v2 batch), `TranscriptChunker` | Publisher-first → Scribe webhook fallback. |
| `Knowledge/` | `WikiPage`, `WikiCompiler` (`BGProcessingTask`), `EmbeddingService`, `VectorStore` protocol + `SQLiteVecStore`, `RAGQueryService` | LLM-wiki compile, embeddings via OpenRouter, sqlite-vec hybrid search. |
| `Voice/` | `AudioConversationManager` (state machine: idle → listening → thinking → speaking → bargeIn → listening) (+`+BargeIn`, `+TTSPlayback`), `BargeInDetector`, `TTSStreamer` (ElevenLabs Flash v2.5 WebSocket) | Conversational voice with sub-second barge-in. |
| `Briefing/` | `BriefingComposer` (script with `<beat>` markers + episode anchors), `BriefingScript`, `BriefingPlayer` (chains TTS clips; interrupt + resume to nearest `<beat>`) | Generate, stitch, play, branch. |

**File-size discipline.** AGENTS.md sets soft 300 / hard 500 lines. Follow the existing extension-per-concern pattern (`PlaybackEngine.swift` + `+RemoteCommands.swift` + `+NowPlaying.swift`).

### 7.3 State, persistence, SwiftData migration

The current `Persistence.save` rewrites the entire `AppState` JSON to App-Group `UserDefaults` on every mutation. Fine for items / notes / friends / memories; **catastrophic for thousands of transcript chunks each ~250 tokens, plus wiki pages, plus embeddings.** Recommendation:

- **v1: AppState UserDefaults stays.** Items / notes / friends / memories / agent activity log / pending approvals / settings continue to live in `AppState`. Add `subscriptions`, `nowPlaying: NowPlayingSnapshot?`, `briefingScripts` (index only), and new `HomeAction` cases `.openEpisode(UUID)`, `.openPlayer`, `.openBriefing(UUID)`. The `Anchor` discriminated union extends with `.episode(id:)`, `.podcast(id:)`, `.briefing(id:)`, `.transcriptChunk(id:)` cases — this is the bridge that lets existing notes / memories attach to new domain types without changing storage shape.
- **v1.1: SwiftData lands empty.** A `ModelContainer` in the App Group container holds `Subscription`, `Episode`, `EpisodeDownload`, `TranscriptChunk`, `WikiPage`, `BriefingScript`, `EmbeddingRef`. Schema versions explicit; migrations via `SchemaMigrationPlan`. **Items / notes do not migrate** — they remain in `AppState` for backward compat.
- **v1.2+: feature-by-feature entity migration** as new surfaces light up.
- **Vector store** is a separate `vectors.sqlite` (sqlite-vec) file in the App Group container. Keyed only by `episodeID: UUID` — never CloudKit-synced (re-embed from SwiftData transcripts on a new device, or pull cached embeddings from a future server bucket).
- **Widget compatibility.** The widget continues to read a small `NowPlayingSnapshot` struct from App-Group `UserDefaults` via `WidgetPersistence`. We do **not** give the widget a SwiftData container. Pattern is intentionally unchanged.

**Migration sequencing rule (architecture report §12).** Do not ship SwiftData and the agent-prompt rewrite in the same release.

### 7.4 Audio stack — playback + voice + AVAudioSession coordinator

**One `AVAudioSession`, three callers.** `VoiceItemService` (`.record`), player (`.playback + .spokenAudio`), conversation (`.playAndRecord + .voiceChat + .duckOthers + setPrefersEchoCancelledInput(true)`). A single **`AudioSessionCoordinator`** owns every transition or routing breaks.

State machine:
```
A. Idle               .ambient, no active session
B. Playing-only       .playback / .spokenAudio
C. Conversation       .playAndRecord / .voiceChat / AEC on / .duckOthers
D. Briefing+Listening C with the briefing player ducked (-12 to -18 dB)
E. Recording-only     .record (clip extraction, voice-note dictation)
```

Transition `B → C` re-negotiates the route in 50–150 ms; **pre-warm by reactivating with the new category on the wake gesture**, before VAD confirms. After turn, `C → B` ramps the briefing volume back up over 250 ms via `AVAudioPlayerNode.volume`. Briefings are **always paused** on barge-in (not just ducked); answers <8 s duck, ≥8 s pause.

`PlaybackEngine` (AVPlayer wrapper) callbacks fire on a private queue — translate through `MainActor.run { … }` boundaries before touching state.

### 7.5 Transcription pipeline

> Source: [docs/spec/research/transcription-stack.md](research/transcription-stack.md)

**Strategy.** Always check the publisher's `<podcast:transcript>` first (parse VTT / SRT / Podcasting 2.0 JSON into our internal `Transcript` model). When absent, send audio to **ElevenLabs Scribe v1/v2 batch** via async webhook, $0.22/hr — competitive with Deepgram Nova-3 and ~3.3× cheaper than Whisper / GPT-4o-transcribe. iOS 26 `SpeechAnalyzer` is the on-device opt-in privacy mode (no diarization).

**Flow.** RSS poll → new episode → `<podcast:transcript>`? → yes: fetch + parse; no: download audio (Wi-Fi background `URLSession`) → upload to R2 (background `URLSession`, `isDiscretionary = true`) → `POST /v1/speech-to-text` (`model=scribe_v2`, `diarize=true`, `webhook=true`, `cloud_storage_url=…`) → webhook → server-side normalize → device pulls via silent APNs → chunk (400–512 tokens, 15 % overlap, snap to speaker turn within ±20 %) → embed via OpenRouter → INSERT into sqlite-vec — **mark episode "ready for RAG"**.

**Latency.** Plan ~3–6 min end-to-end for a 1-hour episode.

**Cost ceiling.** Power user (50 hrs/wk = ~217 hrs/mo, ~25 % publisher hit-rate) ≈ **$36–50/month**. Typical user (10 hrs/wk) ≈ $7.15/month.

**Internal `Transcript` model is lossless across all source formats** (VTT / SRT / Podcasting 2.0 JSON / Scribe word-list / Apple SpeechAnalyzer / WhisperKit). Adapter pattern: `Transcript.fromScribe(_:)`, `Transcript.fromVTT(_:)`, etc. Each MUST set `source` and `model`, MUST sort segments, MUST stable-id speakers across calls.

**Webhook reliability.** Always have a poll-based reconciliation fallback (`BGAppRefreshTaskRequest`); never trust a single webhook.

### 7.6 Embeddings + RAG (sqlite-vec + OpenRouter)

> Source: [docs/spec/research/embeddings-rag-stack.md](research/embeddings-rag-stack.md)

**Embeddings.** OpenRouter ships an OpenAI-compatible `POST /api/v1/embeddings` endpoint. **Default: `openai/text-embedding-3-large` requested at 1024 dimensions** (Matryoshka truncation, no quality loss). Abstracted behind `EmbeddingProvider` protocol so we can swap to Voyage / Cohere if MTEB benchmarks for our domain demand it.

**Vector store: `sqlite-vec` via `jkrukowski/SQLiteVec`.** Single `vectors.sqlite` in the App Group container. Two virtual tables: `chunks_transcript` (sliding 400–512 tok / 15 % overlap, time-anchored, speaker-tagged) and `chunks_wiki` (~1000 tok semantic chunks, anchored to wiki section headings). FTS5 alongside for BM25.

**RAG pipeline (`query_transcripts`).**
```
agent calls query_transcripts(query, scope?)
  ├─ embed query with text-embedding-3-large @ 1024d   (~150 ms)
  ├─ SQL: vec0 MATCH for top-50 (cosine) WHERE podcastID IN scope
  ├─ SQL: FTS5 BM25 for top-50 WHERE podcastID IN scope
  ├─ RRF merge → top-20                                  (~30 ms)
  ├─ Cohere rerank-v3.5 → top-5                          (~200 ms)
  └─ return [{ episodeID, startSec, endSec, speaker, text, score }]
```
**Total ~400 ms.** For voice mode we drop the reranker (~180 ms total).

**Two indexes, same DB, same schema.** `query_wiki(topic)` hits `chunks_wiki`; `query_transcripts(query, scope?)` hits `chunks_transcript`. The orchestrator can call both in parallel for cross-synthesis. **Combining at query time is wrong** — different chunk sizes confuse RRF; let the agent reason over two retrieved sets.

**SwiftData ↔ vector store integration: keep them separate, bridge by UUID.** SwiftData owns Podcast / Episode / Transcript / WikiPage / prefs / queue / history; `vectors.sqlite` owns chunks (rowid + embedding + FTS) and nothing else. Vectors are **derived data, never CloudKit-synced**.

**Cost.** Power user ingest ~$4.66/year on `text-embedding-3-large`; query+rerank ~$10.4/year. **~$15/year total — not a constraint.**

### 7.7 LLM wiki generation pipeline

> Source: [docs/spec/research/llm-wiki-deep-dive.md](research/llm-wiki-deep-dive.md)

**Generation is automatic** (departing from llm-wiki's user-invoked slash commands):
1. **New episode published** → enqueue transcript fetch → enqueue compile.
2. **Transcript ready** → diarize → chunk → embed → page-update pass on affected entity pages: show page, each speaker's person page, any concept page whose embedding centroid the new chunks fall near.
3. **User listens ≥X %** → optional favorite-quote extraction.
4. **Agent tools** `summarize_episode`, `query_wiki` are read-side, but queries that produce interesting Q→A pairs file back as new pages (Karpathy's "*file valuable explorations back*").

**Per-episode fan-out** replaces llm-wiki's 5/8/10 web-research-agent pattern: `extract_topics`, `extract_entities`, `extract_quotes`, `extract_action_items`, `link_to_existing_pages` — five parallel passes per new episode. Each writes `(episode_id, op)` rows to a queue drained by `WikiCompiler` BGProcessingTask (wakes on charge + Wi-Fi).

**Page taxonomy.** Per-podcast wiki + library-wide hub for cross-show synthesis. Page types: `concept`, `episode`, `show`, `person`, `cross-show debate`. **Confidence is extraction confidence**, not source quality. Provenance-or-it-doesn't-render — every claim points to `(episode_id, start_ms, end_ms)`. The only exception is `Definition` paragraphs with `[general knowledge]` tag.

**Mirror to iCloud Drive Markdown.** Articles persist as Markdown blobs in SQLite (FTS5 + vector index) **and** as files in an iCloud-Drive folder the user can open in Obsidian on Mac. *That single decision is what makes this feel like a personal knowledge base rather than a black-box AI summary.*

**Hallucination defense.** Post-compile verification pass: every synthesized sentence carries a span pointer; cheap classifier or LLM judge checks the cited span actually supports the claim.

**Quote ceiling.** Mirror llm-wiki's <125 char cap on raw quotes for fair-use posture.

**Edit conflicts across devices.** iCloud last-write-wins + monotonic `compile_revision` per page. Not CRDT.

### 7.8 Briefing composition + audio stitching

`BriefingComposer` produces a `BriefingScript` — an ordered list of `Segment` objects, each with: `title`, `tts_body` (TTS narration text), `quotes: [QuoteAnchor]` (original-audio spans to splice), `sources: [(episode_id, start_ms, end_ms, speaker)]`, and `<beat>` markers between sentences for resume-point granularity.

Pipeline:
1. Agent runs `query_transcripts` and `query_wiki` to gather candidates within the requested scope and length.
2. LLM drafts segment titles + bodies; emits source anchors inline; flags `[paraphrased]` if no original audio is available.
3. **TTS render in parallel.** ElevenLabs Multilingual v2 (or v3 GA) streamed and persisted as MP3/Opus per segment, cached in App Group. Stream-as-ready: segment 1 plays before the last finishes.
4. **Stitching.** `BriefingPlayer` chains segments via `AVPlayer` queue with `AVMutableComposition`-style splices for original-audio quotes. Original audio fetch fails → substitute paraphrased TTS, mark chip *paraphrased*.
5. **Branch contract.** Pause-and-resume — main thread freezes at the sample the user spoke over; the branch plays as a parenthetical `Briefing`-shaped sub-object; on completion or *back*, main resumes from that sample. Branches persist and resurface on re-listen.

**Now Playing integration is mandatory.** The briefing is a first-class `MPNowPlayingInfoCenter` episode — lock screen, CarPlay, AirPlay all work without special-casing. Live Activity shows briefing-rendering progress via APNs background pushes (collapse-id `briefing/<id>`).

### 7.9 Agent loop & new tools

**The load-bearing change to `AgentPrompt.swift`: rewrite to *inventory + handles + RAG-via-tools*.** Today it dumps every active item, recent note, memory, and friend into the prompt. That fails at 50 podcasts × 200 episodes. New shape:

```
SYSTEM
  · App identity + persona
  · Subscription inventory: [show_id, title, episode_count, latest_episode_pubdate, last_listened_at]
  · "New this week": last 5 unplayed episodes
  · Current `nowPlaying`: { episode_id, position, transcript_line }
  · Tool descriptions
  · Explicit instruction: "Call search_episodes / query_transcripts / query_wiki to read further. Do not assume content; verify with tools."
TOOLS
  [array — see table below]
USER / ASSISTANT / TOOL turns
```

The agent's **eyes become its tools**; its memory is a vector store. This is the contract the toolset is designed against.

**New tools (added to `Agent/AgentTools+{Podcast,RAG,Wiki,Briefing,Web}.swift`).**

| Tool | Args | Dispatch file | Friend-Reader-tier exposure |
|---|---|---|---|
| `play_episode_at` | `episode_id`, `timestamp_sec` | `+Podcast` | Suggester (draft), Actor |
| `pause_playback` | — | `+Podcast` | Actor |
| `set_now_playing` | `episode_id`, `timestamp_sec` | `+Podcast` | Actor |
| `search_episodes` | `query`, `scope?` | `+Podcast` | Reader |
| `find_similar_episodes` | `seed_episode_id` | `+Podcast` | Reader |
| `summarize_episode` | `episode_id` | `+Podcast` | Reader |
| `open_screen` | `route` | `+Podcast` | Suggester (draft) |
| `query_transcripts` | `query`, `scope?` | `+RAG` | Reader |
| `query_wiki` | `topic` | `+Wiki` | Reader |
| `summarize_speaker` | `speaker_id` | `+Wiki` | Reader |
| `find_contradictions` | `topic`, `scope?` | `+Wiki` | Reader |
| `generate_briefing` | `scope`, `length_min`, `voice?` | `+Briefing` | Suggester (draft), Actor |
| `send_clip` | `clip_id`, `recipient_pubkey` | `+Briefing` | Actor |
| `perplexity_search` | `query` | `+Web` | Reader |

Every mutating tool records an `AgentActivityEntry` with a new `AgentActivityKind` case so per-batch undo keeps working.

**Reuse of the existing loop.** `AgentChatSession.runAgentTurns` (text) and `AgentRelayBridge` (Nostr inbound, 8-turn cap) both stay. Voice mode (UX-06) hooks `AgentChatSession.send(message, source: .voice)` with a per-sentence callback so TTS streams while the LLM is still generating.

### 7.10 Concurrency, background tasks, lifecycle

**Swift 6 strict concurrency stays on.** Inter-actor boundaries pass `Sendable` value types only.

- **Main-actor:** `AppStateStore`, `AgentChatSession`, `AgentRelayBridge`, `VoiceItemService`, `NostrRelayService`, `ChatHistoryStore`, `AudioConversationManager`, `BriefingPlayer` state, `RAGQueryService` request-coordinator, `PlaybackEngine` observable wrapper.
- **Background:** RSS parsing, OPML parse, transcript chunking, embedding HTTP calls, vector-store reads — `Task.detached` or background actors that return `Sendable` value types and hop back to `@MainActor` for the write.
- **System frameworks:** `AVPlayer` callbacks fire on a private queue; translate through `MainActor.run { … }`. `SFSpeechRecognizer` callbacks already use `MainActor.assumeIsolated` in the existing `VoiceItemService`.
- **Background tasks.** `BGAppRefreshTask` for RSS poll (≤30 s); `BGProcessingTask` for transcription + embedding indexing + wiki compile (longer, deferrable, can require power). Identifiers registered in `Info.plist`.

**Lifecycle additions to `App/Resources/Info.plist`.** `UIBackgroundModes`: `audio`, `fetch`, `processing`. `BGTaskSchedulerPermittedIdentifiers`: feed-refresh ID, transcription ID, embedding-index ID, wiki-compile ID. `NSAppleMusicUsageDescription` (lock-screen now-playing). `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` (voice mode). `NSUserActivityTypes` already updated for the renamed scheme.

**Entitlements.** `Podcastr.entitlements` already in place. CarPlay (`com.apple.developer.carplay-audio`) added in v1.1.

### 7.11 Settings, secrets, Keychain

Existing Keychain stores follow a uniform pattern: `(service, account)` with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, all access through a typed enum. New entries follow the same shape:

- `PerplexityCredentialStore` — for `perplexity_search`.
- `EmbeddingProviderCredentialStore` — only required if OpenRouter cannot serve the embedding model we choose. **Verify before wiring** — OpenRouter's embedding coverage has historically been thinner than its chat coverage. If we end up calling Voyage / Cohere / OpenAI directly, this store handles their key.

**Settings extensions** (non-secret; `iCloudSettingsSync` already merges arbitrary fields key-by-key, so cross-device sync comes free): `transcriptionPreference: { publisher | scribe | local }`, `embeddingProvider`, `embeddingModel`, `briefingVoiceID` (reuse `elevenLabsVoiceID`), `briefingDefaultLengthMin`, `downloadOverCellular`, `defaultPlaybackRate`, `skipBackSeconds`, `skipForwardSeconds`, `dailyBriefingTime`, `dailyBriefingWeekendTime`, `pushBudget`, `incognitoSearch`, `hideTranscriptOnLockScreen`, `voicePersona`.

---

## 8. Cross-Cutting Decisions Already Made

These are settled. Surface briefs that contradict are wrong.

1. **Tab structure: 5 tabs at v1** (Today, Library, Wiki, Ask, Settings) once template Home retires. Skeleton currently has 6 (the sixth is template Home, kept until TestFlight).
2. **Onboarding trial budget (Option A).** First briefing on a small house-funded budget; BYOK introduced after the user is hooked.
3. **Persistence migration order.** v1 `AppState` UserDefaults stays; v1.1 SwiftData lands empty; v1.2+ entities migrate feature by feature.
4. **Agent context strategy: inventory + handles + RAG-via-tools.** No more dumping every item, note, memory into the prompt.
5. **Single `AudioSessionCoordinator`** owns every `AVAudioSession` transition. No exceptions.
6. **Live STT default: Apple `SpeechAnalyzer` on iOS 26+** (we deploy iOS 26). `SFSpeechRecognizer` is fallback; cloud STT is for offline transcript ingest only, never the live loop.
7. **Embeddings: OpenRouter `openai/text-embedding-3-large` @ 1024 d** behind `EmbeddingProvider` protocol; vector store sqlite-vec via `SQLiteVec` Swift package; rerank Cohere `rerank-v3.5`.
8. **Transcription: ElevenLabs Scribe v2 batch + async webhook**, publisher transcripts first, on-device `SpeechAnalyzer` as opt-in privacy mode.
9. **Conversational TTS: ElevenLabs Flash v2.5** WebSocket streaming (~75 ms TTFB). Briefing TTS: ElevenLabs Multilingual v2 / v3 pre-rendered.
10. **Briefing surface ownership.** UX-08 owns the player engine; UX-05 hosts the card in chat; UX-14 hosts the daily edition delivery. Three briefs, one `Briefing` object.
11. **Copper accent (`accent.player`) is exclusive to Now-Playing surfaces.** No other primary CTA in the app uses copper.
12. **Editorial typography is the load-bearing decision.** New York serif for hero + agent prose + transcript body + wiki body; SF Pro for chrome; SF Pro Rounded for chips and the agent voice; SF Mono for timestamps.
13. **One push a day default; surplus pools in Today.** Spam is a design failure.
14. **Wikipedia-style provenance.** Every claim in wiki / briefing / threading points to `(episode_id, start_ms, end_ms)`. Provenance-or-it-doesn't-render.
15. **Quiet Mode is the BYOK-declined fallback.** Playback / transcripts / library work fully; agent and briefings degrade to read-only summaries.
16. **iCloud Drive Markdown mirror** for the wiki is what makes it feel like a real second brain.
17. **Skeleton file layout is final.** Net-new code lands inside the existing module/feature stubs; no `AgentExtensions/` folder; new agent tool dispatchers live in `Agent/AgentTools+{Podcast, RAG, Wiki, Briefing, Web}.swift`.

---

## 9. Open Decisions (need a call before build)

Resolve before sprint zero. Each carries a recommended default; the row says what is undecided.

| # | Decision | Default / recommendation | Why it matters |
|---|---|---|---|
| 1 | **Bundle ID single-segment override.** Skeleton resolves to `com.podcastr.podcastr` (concatenation artifact). | Keep `com.podcastr.podcastr` for v1 to avoid re-provisioning; consider override to `com.podcastr.app` post-launch. | App Store identity, push topic, App Group are downstream. |
| 2 | **OPML at 2 k+ feeds.** UX-02 flagged perf. | Cap initial parse at 2,000; stream the rest. | Power-user import path. |
| 3 | **Discover regeneration cadence.** UX-02 + UX-14 boundary handshake. | Nightly at 3 AM, plus on-subscription change. | Avoids stale rails without burning compute. |
| 4 | **Auto-scroll lock duration after manual scroll on Now Playing.** UX-01 §9. | Indefinite, until *Return to live* pill tapped (Slack model). | Reading mid-listen is a marquee user moment. |
| 5 | **Agent inline-answer → full-chat threshold.** UX-01 §9. | ≤3 turns inline; *Continue in chat* CTA appears on turn 3. | Player↔chat handoff. |
| 6 | **Citation density per paragraph.** UX-03 §9. | Cap at 2 visible; rest in margin marker. | Reader noise / RAG temptation. |
| 7 | **Wiki disambiguation:** "Cold" the noun vs "Cold open" the chapter. UX-03 + UX-04. | Topic NER prefers entity over chapter; chapter only links if no entity match. | Linking policy for the entire reader. |
| 8 | **Live transcript freshness smoothing.** UX-03 §9. | 8-second smoothing buffer; flag if drift exceeds 800 ms persistently. | 30 s ElevenLabs blocks make the cursor sticky. |
| 9 | **Wake-word on/off at v1.** UX-06 §9. | **Off** at v1 (gesture-only). Hot-phrase "Hey, podcast" at v1.1 with parody guard. | Podcast audio itself contains "Hey, …" |
| 10 | **TTS voice identity choice.** UX-06 §9. | Select branded ElevenLabs Pro voice at launch ("Aria"); user can switch in S5 onboarding. | One-time brand decision. |
| 11 | **AirPods long-press claim.** UX-11 §9. | Off by default; opt-in in onboarding S5; copy explains the system override. | One app system-wide can claim. |
| 12 | **Push budget UX after raising.** UX-14 §9. | Day-7 tooltip offering "Want more? Raise in Settings." Never auto-raise. | Avoid spam-creep. |
| 13 | **Transcript ready over Lock Screen.** UX-14 + UX-11. | Today only, never push. | Privacy + push-budget. |
| 14 | **Photo licensing source order.** UX-13 §9. Legal review. | Wikimedia Commons → verified social → monogram. | Copyright. |
| 15 | **Speaker-resolver confidence threshold default.** UX-13 §3. | `medium`. User can lower to surface plausible matches. | Resolver false-positive rate. |
| 16 | **Per-show *Shareable / Private* toggle for Nostr.** UX-12 §9. | Default Shareable; Health / Finance preset auto-Private. | Library privacy. |
| 17 | **Default Nostr relay set.** UX-12 §9. | 3 relays minimum, parallel writes, first-ack reads, none Apple-/Anthropic-owned. | Single-relay rate-limit risk. |
| 18 | **NIP-44 vs NIP-04 for friend DMs.** UX-12 §9. | NIP-44 mandatory for sensitive content (Health-tagged); NIP-04 fallback otherwise. | Privacy. |
| 19 | **Cross-device delegation key (NIP-26-style).** UX-12 §9. | Per-device, scoped, revocable from My Other Devices. | Don't leak the seed. |
| 20 | **Trial budget per-user ceiling.** UX-10 §10. Finance sign-off. | One briefing + ~2 K agent tokens, device-attested. | Abuse / multi-install farming. |
| 21 | **OpenRouter signup deep-link.** UX-10 §10. | In-app web view (keeps thread); deep-link with referral code. | BYOK conversion. |
| 22 | **Embedding provider Keychain store.** Architecture §8. | Verify OpenRouter `openai/text-embedding-3-large` is reliably available **before** designing around it. If not, add `EmbeddingProviderCredentialStore`. | Vendor coverage. |
| 23 | **Quote-reply visual link in chat.** UX-05 §9. | Defer to v2. | Layout complexity. |
| 24 | **Editorial serif licensing.** UX-05 §9. | New York (system-supplied, free). Custom serif → licensing review. | Cost / risk. |

---

## 10. Phased Delivery Plan

### v1 — Launch (the floor + the magic)

**Baseline.** Every "must" row in §4.1 (variable speed, Smart Speed, Voice Boost, configurable skip, sleep timer, chapter support, AirPlay 2, CarPlay, Lock Screen / Now Playing / Control Center, smart Up Next queue, resume / mark-played, bookmarks, RSS + OPML import-export, iTunes + Podcast Index search, manual + background refresh, downloads + auto-download policy, storage + auto-delete, filter / sort, played-state viz, iCloud sync, Dynamic Type, VoiceOver, reduce motion / transparency, captions / transcripts, in-library + directory search, share-with-timestamp, App Intents + Siri, Live Activity, Watch companion, iPad multitasking, PiP + video, theme + accent, default speed / skip, auto-download defaults, restore-from-backup, analytics opt-out, data delete, per-show cache clear).

**Differentiating.** Five marquee user stories from §2. Now Playing transcript surface (UX-01). Library + Discover (UX-02). Episode Detail + Reading + Follow-Along (UX-03). Wiki browser including Topic, Person, Citation Peek, Generate Page (UX-04). Agent Chat with editorial unbubbled prose, embedded media cards, Tool-Call Inspector (UX-05). Voice mode with sub-second barge-in via SpeechAnalyzer + Flash v2.5 (UX-06). Semantic Search + Topic chips + Voice search overlay (UX-07). Briefings: compose + player + branch contract + library shelf (UX-08). Threading: ribbon + transcript inline + detail sheet (UX-09). Onboarding S1–S7 with trial budget (UX-10). Lock Screen Live Activity, Dynamic Island, small + medium widgets, CarPlay (Audio entitlement, deferred from v1.0 to v1.0.x if entitlement provisioning is slow), Watch standalone playback (UX-11). Nostr friend / friend-agent comms with permission tiers, share-clip, cross-device own-DMs (UX-12). Speaker + Topic profiles with peek sheet, Follow, Brief-me handoff (UX-13). Today + Inbox + 1-push-default + Insight Card taxonomy (UX-14). Liquid Glass design system: AppTheme tokens, Sounds.swift, Haptics extensions, AgentOrb component (UX-15).

### v1.1 — Fast-follow (~6 weeks post-launch)

**Baseline.** Volume normalization, long-press scrub, shake-to-extend sleep timer, Handoff iPhone↔iPad↔Mac↔Watch, episode-update detection, premium / private feeds, episode size cap, archive, custom playlists, queue / badge / history sync, RTL + CJK + initial localizations (es / pt / ja / de / fr), language indicator, quiet hours, download-complete notifs, recent / saved searches, clip creation + share, data export, reset settings, diagnostics export, Mac Catalyst, external display, large widgets, action button shortcut presets.

**Differentiating.** SwiftData lands empty (architecture §6). Wake-word "Hey, podcast" (UX-06). Briefing scheduling (UX-08 + UX-14 handoff). Voice persona swap post-S5. Threading evolution view for guests (≥3 chronological mentions). Speaker-stance evolution `Hear in context` affordance. Per-tier per-tool override UI for Nostr friends. iCloud-Drive Obsidian mirror for the wiki. Shared subscription via `pcst://` deep link or Nostr event. Co-listen via SharePlay (deferred to v2 if SharePlay budget tight).

### v2 — After product-market fit

Smart playlists, alt feeds, Apple Podcasts Subscriptions OAuth, translated transcripts, SharePlay co-listen, V4V Lightning tipping, boostagrams, in-app tip jar, Spatial Audio, Family Sharing, community / comments. Watch standalone RAG. CarPlay full voice-conversational template (CPListItem + voice-primary modality). Quote-reply visual link in chat. WhisperKit Pro toggle for languages where Apple's accuracy lags.

---

## 11. Risk Register

| # | Risk | Likelihood / impact | Mitigation | Owner |
|---|---|---|---|---|
| 1 | **Hallucination at synthesis** (wiki, briefings, threading misattribute claims to a host who didn't say them) | High / Severe | Provenance-or-it-doesn't-render. Post-compile verifier. Diarization-confidence threshold below which we attribute to "the show," not a named speaker. | Knowledge / Briefing |
| 2 | **Voice barge-in false-positive** (orb interrupts itself for coughs, laughs in podcast audio) | Medium / Severe | AEC always on. 250 ms voiced minimum. Cross-correlate against TTS ring buffer. Optimistic preview rim-light with forgiveness behavior. | Voice |
| 3 | **AVAudioSession routing mistakes** (player talks over voice, voice talks over briefing) | Medium / Severe | Single `AudioSessionCoordinator`. State machine with pre-warm on wake gesture. Integration tests with fake `AVAudioSession`. | Audio |
| 4 | **Transcription latency vs UX promise** ("talk to all your podcasts" with no transcripts ready) | Medium / High | Background prefetch from moment of subscription. *Transcribing… 38 %* surfaced honestly. On-device `SpeechAnalyzer` opt-in for power users who want it now. | Transcript |
| 5 | **Speaker identity misresolution** ("Tim said X" when guest said X) | High / High | Tiered resolver (RSS → NER → voiceprint → user disambig). Attribute to "the show" below threshold. Disambiguation chooser at page open. | Knowledge / UX-13 |
| 6 | **OpenRouter embedding model availability** (coverage thinner than chat) | Medium / Medium | **Verify before wiring.** `EmbeddingProvider` protocol abstracts; fallback to direct Voyage / Cohere / OpenAI keys. | Knowledge |
| 7 | **Live Activity battery drain** (transcript-line scrolling at high frequency) | Medium / High | Throttle to one update per transcript-segment boundary (~6–10 s), not per word. Battery soak test before ship. | Ambient |
| 8 | **Trial-budget abuse** (multi-install farming during onboarding) | Medium / Medium | Device-attested + capped at one briefing + ~2 K agent tokens. Finance sign-off on per-user ceiling. | Onboarding |
| 9 | **Photo / clip licensing posture** (scraped portraits, cross-publisher clip embedding) | Medium / High (legal) | Wikimedia/Commons → verified social → monogram. Quote ceiling 125 char. Fair-use ≤20 s clip ceiling for inline cross-publisher. Legal review before ship. | UX-13 + UX-09 |
| 10 | **Nostr DM tool-exposure (privilege escalation)** | Low / Severe | Tier-gated tool exposure (Reader / Suggester / Actor). Per-tool overrides. TTL on agent-originated DMs; max hop count of 2. | Nostr |

---

## 12. Appendix — Source Briefs Index

### Project context

- [docs/spec/PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) — vision, foundations, marquee user stories.
- [docs/spec/baseline-podcast-features.md](baseline-podcast-features.md) — table-stakes feature checklist.

### UX briefs (15)

- [docs/spec/briefs/ux-01-now-playing.md](briefs/ux-01-now-playing.md) — Now Playing (the hero surface).
- [docs/spec/briefs/ux-02-library.md](briefs/ux-02-library.md) — Library & Subscriptions.
- [docs/spec/briefs/ux-03-episode-detail.md](briefs/ux-03-episode-detail.md) — Episode Detail & Transcript Reader.
- [docs/spec/briefs/ux-04-llm-wiki.md](briefs/ux-04-llm-wiki.md) — LLM Wiki Browser.
- [docs/spec/briefs/ux-05-agent-chat.md](briefs/ux-05-agent-chat.md) — Agent Chat (text mode).
- [docs/spec/briefs/ux-06-voice-mode.md](briefs/ux-06-voice-mode.md) — Voice Conversational Mode.
- [docs/spec/briefs/ux-07-search-discovery.md](briefs/ux-07-search-discovery.md) — Semantic Search & Discovery.
- [docs/spec/briefs/ux-08-briefings-tldr.md](briefs/ux-08-briefings-tldr.md) — AI Briefings / TLDR Player.
- [docs/spec/briefs/ux-09-cross-episode-threading.md](briefs/ux-09-cross-episode-threading.md) — Cross-Episode Knowledge Threading.
- [docs/spec/briefs/ux-10-onboarding.md](briefs/ux-10-onboarding.md) — Onboarding & First Run.
- [docs/spec/briefs/ux-11-ambient-surfaces.md](briefs/ux-11-ambient-surfaces.md) — Ambient Surfaces (Lock Screen / Live Activities / Widgets / CarPlay / Watch / AirPods / Action Button / Shortcuts).
- [docs/spec/briefs/ux-12-nostr-communication.md](briefs/ux-12-nostr-communication.md) — Nostr Communication.
- [docs/spec/briefs/ux-13-speaker-topic-profiles.md](briefs/ux-13-speaker-topic-profiles.md) — Speaker & Topic Profiles.
- [docs/spec/briefs/ux-14-proactive-agent-notifications.md](briefs/ux-14-proactive-agent-notifications.md) — Proactive Agent & Notifications.
- [docs/spec/briefs/ux-15-liquid-glass-system.md](briefs/ux-15-liquid-glass-system.md) — Liquid Glass Design System & Motion Language.

### Research notes (5)

- [docs/spec/research/template-architecture-and-extension-plan.md](research/template-architecture-and-extension-plan.md) — what we have, what we extend, what we add. The architectural backbone.
- [docs/spec/research/skeleton-bootstrap-report.md](research/skeleton-bootstrap-report.md) — the rename pass and module/feature stubs already on disk.
- [docs/spec/research/transcription-stack.md](research/transcription-stack.md) — Scribe + publisher + iOS-26 SpeechAnalyzer pipeline.
- [docs/spec/research/embeddings-rag-stack.md](research/embeddings-rag-stack.md) — OpenRouter embeddings + sqlite-vec + FTS5 + RRF + reranker.
- [docs/spec/research/voice-stt-tts-stack.md](research/voice-stt-tts-stack.md) — STT + TTS + AVAudioSession + barge-in.
- [docs/spec/research/llm-wiki-deep-dive.md](research/llm-wiki-deep-dive.md) — adapting nvk/llm-wiki to a podcast knowledge base.

---

*End of spec. The next deliverable is an engineering plan that turns §7 into PRs and §10 into a sprint cadence.*
