---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - ai-chapters-d0
  - ai-chapter-compiler-deletion
  - ad-span-generation
supersedes: []
related_claims: []
source_lines:
  - 5798-5966
captured_at: 2026-06-12T21:53:41Z
---

# Episode: Kernel D0 consolidation of AI chapter + ad-span generation — delete Swift AIChapterCompiler

## Prior State

AI chapter and ad-span generation lived in Swift (AIChapterCompiler.swift, ~501 lines); the shell called the LLM, parsed responses, and validated ad segments client-side

## Trigger

Cycle-6 plan to D0-consolidate chapter generation into the kernel, eliminating the Swift-side compiler and making the feature available to both iOS and Android shells

## Decision

Port all FULL/enrich-only LLM modes + ad-validation rules (monotonic, non-overlapping, end>start, duration-capped) to Rust (ai_chapters_llm_compile.rs, ai_chapters_impl.rs). Persist chapters+ads via CHAPTERS_READY/ADS_READY events. Convert 3 Swift call sites to kernel dispatch. Delete AIChapterCompiler.swift (501 lines). Deliberate improvement: Rust adds a retry ladder (Simple prompt on Parse failure) + offline stub chapters (5 generic 'Chapter N' entries when unavailable), neither of which Swift had.

## Consequences

- Chapter+ad generation is now kernel-owned (D0) — both shells consume it identically via dispatch
- 501 lines of Swift deleted; ad detection finally runs in the kernel
- Pre-pays Android Tier-2 chapters and auto-skip (the kernel now owns the compile + skip-ads pipeline)
- Offline episodes now get stub chapters instead of nothing (product improvement, documented as deliberate divergence)
- The review caught an orphaned overlapsAd extension that was deleted along with the compiler — had to be relocated to Episode+AdOverlap.swift

## Open Tail

- Empty ad vecs are dropped on disk (disk.rs filter), so ad-free episodes re-run the LLM on cold start — acceptable but could be optimized later

## Evidence

- transcript lines 5798-5966

