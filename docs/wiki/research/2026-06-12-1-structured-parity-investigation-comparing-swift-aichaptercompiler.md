---
type: research-record
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
source_lines: 5836-5895
agent_attribution: a256c91aaf8c77d29
has_preregistered_criteria: true
has_method: true
has_structured_report: true
characterization: "Structured parity investigation comparing Swift AIChapterCompiler vs Rust kernel port across 5 focus areas (behavior parity, LLM invocation, call sites, persistence/events/ad-skip, golden/hygiene), yielding PASS on all 5 but overall REQUEST-CHANGES due to an orphaned overlapsAd Swift compile blocker"
captured_at: 2026-06-12T21:44:18Z
---

Structured parity investigation comparing Swift AIChapterCompiler vs Rust kernel port across 5 focus areas (behavior parity, LLM invocation, call sites, persistence/events/ad-skip, golden/hygiene), yielding PASS on all 5 but overall REQUEST-CHANGES due to an orphaned overlapsAd Swift compile blocker

---

User: [Agent task result: Agent "Opus review: kernel AI chapters+ads #413" completed]
Wiring confirmed. The Rust side is well-engineered and faithful. The single blocker is the orphaned `overlapsAd` deletion. Let me do one last parity confirmation on the prompts (verbatim claim) using a direct diff of the prompt text — Swift used line continuation `\` (which inserts a space), Rust uses `\` at line ends in a string literal (no space, continues). Let me verify the first line of the FULL prompt is semantically identical.

The Swift prompt uses `"""..."""` with trailing `\` on the first two lines (Swift `\` at end of line in multiline string = line continuation, removes the newline). Rust uses `"\...\"` (also removes newline). Both produce: `"You analyse podcast episode transcripts and return chapter boundaries, chapter summaries, and advertisement spans in a single JSON response. Always respond with ONLY this JSON object (no prose, no markdown fences):\n{..."`. These match. The rest use explicit `\n`. The prompts are verbatim-equivalent.

I have enough to deliver a decisive verdict.

---

## VERDICT: REQUEST-CHANGES

One blocking compile break. Everything else (the actual focus of the review — LLM behavior parity) is faithfully ported and sound. The fix is a ~25-line mechanical relocation.

### The blocker: deleted `overlapsAd` leaves orphaned call sites (Swift won't compile)

`AIChapterCompiler.swift` (deleted) contained more than the compiler — at the bottom it carried `extension Episode.Chapter { func overlapsAd(in:adSegments:) }` (origin/main `AIChapterCompiler.swift:387`). That helper is **not relocated anywhere** on the branch (zero `func overlapsAd` definitions in the entire tree), yet it is still called by:
- `App/Sources/Features/Player/PlayerChaptersScrollView.swift:67` (production — the amber ad-overlap stripe on the chapter rail)
- `AppTests/Sources/AdSegmentDetectorTests.swift:162,172-174,181,190,199-200` (tests, file still present)

This is a hard Swift compile failure. It also explains the PR-description discrepancy ("501 lines deleted" vs the diff's 405): the deletion swept up the load-bearing `overlapsAd` extension and the "Chapter overlap helper" section. The 1229 *Rust* tests passing does not catch this — it's Swift.

**Minimal fix:** move the `overlapsAd` extension (verbatim, lines ~373–410 of the old file) into a surviving Swift file — e.g. a new `App/Sources/Podcast/Episode+AdOverlap.swift`, or append to `EpisodeSubtypes.swift`. No logic change needed; just relocate.

### Focus #1 — Behavior parity (the crux): PASS

| Aspect | Swift (`AIChapterCompiler`) | Rust port | Match |
|---|---|---|---|
| **Mode selection** | `hasExistingChapters = (episode.chapters?.isEmpty == false)` at call time | `read_episode_inputs` (`ai_chapters.rs:208`): `if has_chapters → EnrichOnly else Full`, decided in-kernel from `episode_chapters_state` | ✅ in kernel (D0), same condition |
| **Ad rule: monotonic/non-overlap** | `start >= prevEnd` | `parse_ads`: `if start < prev_end { continue }` (`prev_end=-1`) | ✅ |
| **Ad rule: end>start** | `guard end > start` | `if end <= start { continue }` | ✅ |
| **Ad rule: duration clamp** | `max(0, min(s, cap))` both ends | `s.max(0.0).min(cap)` both ends | ✅ |
| **Ad key tolerance** | accepts `start`/`end` + `start_seconds`/`end_seconds` | `item["start"].or_else(start_seconds)` | ✅ |
| **Ad kind default** | `AdKind(rawValue: kind ?? "midroll") ?? .midroll` | filters to preroll/midroll/postroll, else `"midroll"` | ✅ |
| **Full parse: chapter clamp/monotonic/min4/max12/first→0** | all present | `parse_full` identical order & thresholds | ✅ |
| **Enrich parse: summaries by index, empty-on-failure** | `parseEnrichOnly` | `parse_enrich_only` returns empty map+ads, never aborts | ✅ |
| **FULL system prompt** | `systemPromptFull` | `SYSTEM_PROMPT_FULL` | ✅ verbatim (Swift `\` continuation == Rust `\` continuation) |
| **ENRICH-ONLY system prompt** | `systemPromptEnrichOnly` | `SYSTEM_PROMPT_ENRICH_ONLY` | ✅ verbatim |
| **Transcript cap** | 28_000 chars | `TRANSCRIPT_EXCERPT_CHARS = 28_000` | ✅ |

Note (not blocking): the Rust FULL path adds a **retry ladder** the Swift never had — on `Parse` failure it retries with a `Simple` chapters-only prompt (no summaries, no ads); on `Unavailable` it emits equal-length stub chapters. Swift just logged and returned (no chapters, no ads, but it *did* persist an empty ad marker to stop looping). This is a behavior *improvement* (more graceful degradation) and is well-documented, but it is a deliberate divergence from "verbatim" — worth a one-line callout in the PR. The stub-on-offline path means an offline episode now gets 5 generic "Chapter N" stubs where Swift gave none; acceptable per the documented design, flag for product awareness.

### Focus #2 — LLM invocation: PASS
`round_trip` resolves via `resolve_request(store, chapter_compilation_model(), CHAPTERS_MODEL="deepseek-v4-flash:cloud", ...)` — same role (`chapterCompilationModel`) Swift read, same cloud default, honors provider-prefixed overrides. 45s timeout → `Unavailable` (structural, not string-matched). Accessor `chapter_compilation_model()` exists (`provider_settings.rs:111`).

### Focus #3 — Call sites: PASS
All three (`PlayerView:123`, `EpisodeDetailView:101`, `TranscriptIngestService:441`) convert `await AIChapterCompiler.shared.compileIfNeeded(...)` → `store.kernelCompileChapters(episodeID:)` — same trigger points, correct `episode.id`, fire-and-forget, no double-fire. The kernel reads transcript/publisher-chapters/duration itself from the store (D0) — nothing the old compiler needed must be passed in; `read_episode_inputs` gathers all of it. Dispatch `{"op":"compile","episode_id":...}` matches the `ChaptersAction::Compile` snake_case variant; routed to `handle_compile_chapters[_with_signal]` (`router.rs:127/135`).

### Focus #4 — Persistence/events/ad-skip: PASS
- `set_ad_segments_for` now always-inserts (even empty) → `ad_detection_ran()` = `contains_key` correctly distinguishes "ran, none" from "never ran" **within a session**. ✅
- `ad_skip_handler.rs` untouched — this PR only feeds segments, no skip-policy change. ✅
- `CHAPTERS_READY`/`ADS_READY` events follow the existing diagnostic pattern.
- **Minor (acceptable, documented):** empty ad vecs are dropped on disk (`disk.rs:357` `.filter(|(_,v)| !v.is_empty())`), so the gate resets across process restart for no-ad episodes → one cheap re-run. The module doc (`ai_chapters.rs:18`) calls this out explicitly. Matches Swift's effective on-disk behavior. Could be a follow-up if re-running the LLM on every cold-start for ad-free episodes proves costly.

### Focus #5 — Golden / deleted fallback / hygiene: PASS
- Golden `snapshot_golden_fixture.json`: **byte-identical** (not in diff; chapters/ads aren't in the deterministic fixture). ✅
- Deleted `KernelProjection` Swift-chapters fallback: was solely a stopgap for the legacy Swift compiler writing chapters without dispatching to Rust; now chapters persist in the Rust store and project normally, so removal is safe — no other reader depended on it. ✅
- 500-LOC ceiling respected via `#[path]` splits (`ai_chapters_impl.rs`, `ai_chapters_llm_compile.rs`). No nmp-core change.

### Bottom line
The hard part — moving LLM chapter/ad behavior into the kernel — is done correctly and is a faithful (slightly improved) port; golden is clean; no ad-skip-policy regression. **Single blocker:** relocate the `overlapsAd` extension that was deleted with `AIChapterCompiler.swift` so the Swift target (and `AdSegmentDetectorTests`) compiles. Re-run an actual Swift build, not just the Rust suite, before merge — the Rust-only green is what masked this.
