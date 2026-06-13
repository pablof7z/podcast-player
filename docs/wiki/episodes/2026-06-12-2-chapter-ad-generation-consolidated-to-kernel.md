---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: active
subjects:
  - ai-chapters
  - ad-spans
  - ai-chapter-compiler
  - d0-consolidation
supersedes:
  - 2026-06-12-2-kernel-d0-consolidation-of-ai-chapter
related_claims: []
source_lines:
  - 5798-5828
  - 5836-5895
  - 5903-5909
  - 5911-5936
  - 5953-5974
captured_at: 2026-06-12T22:05:45Z
---

# Episode: Chapter+ad generation consolidated to kernel, Swift AIChapterCompiler deleted

## Prior State

AI chapter and ad-span generation lived in Swift (`AIChapterCompiler.swift`, 501 lines), a fragmentation point outside the kernel's ownership. Ad detection was not kernel-side, blocking Android Tier-2 auto-skip.

## Trigger

D0 architecture doctrine: the kernel must own all LLM behavior. Cycle-6 directive to consolidate chapter+ad generation into the kernel and delete the Swift compiler.

## Decision

All chapter+ad generation moved to the Rust kernel (`ai_chapters_llm_compile.rs`, `ai_chapters_impl.rs`). `AIChapterCompiler.swift` deleted. LLM behavior is now D0 (kernel-owned) with FULL and enrich-only modes ported verbatim, plus a deliberate improvement: a retry ladder with offline stub chapters (Swift gave none on failure). `overlapsAd` extension relocated to `Episode+AdOverlap.swift` after review caught an orphaned reference that Rust-only tests couldn't detect.

## Consequences

- 501 lines of Swift deleted; chapter+ad generation is now kernel-owned
- Ad detection is kernel-side, pre-paying Android Tier-2 chapters/auto-skip
- Rust FULL path adds a retry ladder (graceful degradation) that Swift never had — offline episodes now get generic stub chapters instead of nothing
- Process doctrine: PRs that delete Swift files must run actual `xcodebuild`, not just `cargo test` — Rust-green masked the orphaned `overlapsAd` reference
- Empty ad vecs are dropped on disk, so ad-free episodes re-run the LLM on cold start (documented, acceptable, potential follow-up)

## Open Tail

*(none)*

## Evidence

- transcript lines 5798-5828
- transcript lines 5836-5895
- transcript lines 5903-5909
- transcript lines 5911-5936
- transcript lines 5953-5974

