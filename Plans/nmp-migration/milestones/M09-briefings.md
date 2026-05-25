# M9 — Briefings

**Status:** unclaimed
**Scale:** M
**Depends on:** M3, M7, M8
**Blocks:** M11
**Parallel work units:** 3

---

## Scope

`podcast-briefings` crate hosts composition, stitching policy, briefing
player state machine. Audio playback routes through M3's audio
capability; TTS via M8's TTS capability. Briefings tab unchanged.

---

## Pre-flight

- [ ] M3 + M7 + M8 exits green.

---

## Parallel work units

### Unit M9.A — `podcast-briefings` Rust

**Tasks:**
- [ ] Port `BriefingComposer`, `BriefingScript`, `BriefingSegment`,
      `BriefingAudioStitcher`, `BriefingPrompts`, `BriefingTrack`,
      `BriefingStorage`, `BriefingPlayerEngine`, `BriefingProtocols`.
- [ ] Segment-list generation: agent tool `generate_briefing` (in
      `podcast-agent-core`); composer drives the segment plan.
- [ ] Stitching policy: crossfade timing, intro/outro selection,
      segment ordering.
- [ ] Briefing player state machine: pause, scrub, branch-points
      ("ask agent a question about this segment").
- [ ] Storage migration: read legacy briefing files into new store.

**Quality gates:**
- [ ] Unit tests cover composer output for a week of fixture
      episodes.

### Unit M9.B — iOS UI migration: Briefings tab + Player

Files:
- `App/Sources/Features/Briefings/*.swift`
- Splits:
  - `BriefingsViewModel.swift` (class excised).
  - `BriefingMicCaptureController.swift` (class excised).

**Tasks:**
- [ ] Tooling: copy → split → token-swap.
- [ ] Bind to `briefings` projection.

**Quality gates:**
- [ ] Goldens match for: empty briefings, briefing being composed,
      briefing playing, branch-point sheet.

### Unit M9.C — Briefing playback integration with audio capability

**Tasks:**
- [ ] Briefing player drives `nmp.audio.capability` with pre-stitched
      audio file (one-shot composed by Rust) OR `nmp.tts.capability`
      for live streaming when supported.
- [ ] Voice-mode interruption: barge-in detected during briefing
      pauses TTS (via M8 cancellation), agent answers, then resume.

**Quality gates:**
- [ ] Live test: generate "Today's Briefing"; play; interrupt with
      voice question; resume.

---

## Sequential integration

- [ ] Merge M9.A → M9.B → M9.C.
- [ ] Live test end-to-end.

---

## Exit checklist

- [ ] Briefings tab unchanged.
- [ ] Briefing generation works.
- [ ] Briefing playback + branch points work.
- [ ] Generated briefings appear as "Agent Generated" pseudo-podcast
      in Library (provenance per D10).
- [ ] **Swift files deleted:**
  - `App/Sources/Briefing/*.swift` (all 13)
  - `App/Sources/Features/Briefings/BriefingsViewModel.swift` (class)
  - `App/Sources/Features/Briefings/BriefingMicCaptureController.swift` (class)
  - `App/Sources/Agent/AgentTTSComposer.swift` (referenced earlier;
    in scope here)
  - `App/Sources/Agent/AgentGeneratedPodcastService.swift`
- [ ] M11 unblocked (M11 depends on M9 for player+briefing-on-CarPlay
      surfaces).

## Hand-off to M10

M10 runs in parallel (depends on M1+M7, not on M9). Briefings doesn't
gate it.

## Hand-off to M11

M11 can rely on briefings for CarPlay + Live Activity surfaces.
