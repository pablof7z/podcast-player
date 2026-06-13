---
type: episode-card
date: 2026-06-09
session: 0964cb48-04df-4b35-9ad9-67cdc6a9d488
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/0964cb48-04df-4b35-9ad9-67cdc6a9d488.jsonl
salience: product
status: active
subjects:
  - ad-detector
  - ad-skip
  - auto-skip-ads
supersedes: []
related_claims: []
source_lines:
  - 4398-5415
captured_at: 2026-06-12T13:38:33Z
---

# Episode: Ad-skip detector fills the missing segment source — skip mechanism now complete

## Prior State

The kernel ad-skip mechanism was fully implemented (maybe_skip_ad, set_auto_skip_ads toggle, hydrate_actor_for_play, set_ad_segments action) with 18 passing tests — but nothing produced ad segments. No detector existed, so the mechanism was idle.

## Trigger

Investigation confirmed set_ad_segments had zero callers; the only gaps were (1) a source/detector of ad segments and (2) the Android settings toggle UI.

## Decision

Built an LLM-based ad detector (ad_detector_llm.rs + ad_detector.rs) mirroring the AI chapters pattern: reads cached transcript + duration, calls LLM via the existing crate::llm factory helpers, produces clamped AdSegments with AdKind classification. Auto-triggered from the transcript-ready FFI hook gated by auto_skip_ads_enabled. Also added the Android settings toggle (1:1 mirror of AutoDeleteRow) and a TUI 'V' keybinding.

## Consequences

- Ad detection + skip now works across all three platforms via the shared kernel
- iOS: auto-detect on transcript ingest (no UI change needed — toggle already existed)
- Android: settings toggle + explicit 'Detect ads' button on episode detail
- TUI: 'V' key dispatches podcast.ads.detect action
- 5 new parse/extract tests for the detector; 118 total ad-related kernel tests pass
- The podcast.ads action namespace is registered and routed in host_op_handler

## Open Tail

- LLM ad detection requires a configured model (same as AI chapters) — degrades silently to no-segments when unavailable
- No on-device end-to-end ad-skip visual verification due to emulator ANR degradation (verified via kernel tests + successful build)

## Evidence

- transcript lines 4398-5415

