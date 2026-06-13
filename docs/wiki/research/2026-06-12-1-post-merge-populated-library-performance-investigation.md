---
type: research-record
date: 2026-06-12
session: deb49f4f-f275-419a-ab1c-b68c123af73b
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/deb49f4f-f275-419a-ab1c-b68c123af73b.jsonl
source_lines: 2216-2275
agent_attribution: main
has_preregistered_criteria: true
has_method: true
has_structured_report: true
characterization: "Post-merge populated-library performance investigation: empirically confirmed O(N²) snapshot fix (224ms→7.6ms at 3600 episodes, 30× speedup), rev-discipline (Playing tick doesn't bump rev), and off-main decode present; verdict: Win B (delta projection) not justified"
captured_at: 2026-06-12T13:22:04Z
---

Post-merge populated-library performance investigation: empirically confirmed O(N²) snapshot fix (224ms→7.6ms at 3600 episodes, 30× speedup), rev-discipline (Playing tick doesn't bump rev), and off-main decode present; verdict: Win B (delta projection) not justified

---

Assistant: **Confirmed on the actual merged `main` (`a52ae566`)** — all three wins present and verified empirically:

| Concern | Result on main |
|---|---|
| **#267 O(N²) fix** | 3,600-ep rebuild: **224 ms → 7.6 ms** |
| **#265 rev-discipline** | Playing tick does **not** bump `rev` (no rebuild during playback); Paused does ✓ |
| **#264 off-main decode** | present; the ~3.8 MB decode runs off the MainActor |

Let me record the key finding in memory, then clean up my worktrees/WIP per AGENTS.md:

User: [Tool result]: File created successfully at: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/memory/perf_on2_snapshot_rebuild.md (file state is current in your context — no need to Read it back)

User: [Tool result]: The file /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/memory/MEMORY.md has been updated successfully. (file state is current in your context — no need to Read it back)

Assistant: Now clean up my worktrees and WIP entry per AGENTS.md (PRs are merged). Let me remove my WIP line and the two worktrees I own:

User: [Tool result]: WIP entry removed
removed agent-perf-integration
removed agent-ffi-delta-perf
Deleted branch perf/ffi-delta-projection (was d4a441b7).
deleted local perf/ffi-delta-projection
Deleted branch perf/snapshot-rebuild-on2 (was a52ae566).
deleted local perf/snapshot-rebuild-on2
Deleted branch perf/integration-verify (was 6ba48761).
deleted local perf/integration-verify
 - [deleted]           perf/ffi-delta-projection
 - [deleted]           perf/snapshot-rebuild-on2
=== remaining worktrees ===
/Users/pablofernandez/Work/podcast-player/.claude/worktrees/agent-ffi-perf-metrics          279dbcf7 [feat/ffi-perf-metrics]

Assistant: Cleanup done (remaining `agent-ffi-perf-metrics` worktree is a peer's #263, not mine). Everything's landed and verified on `main`.

User: [Tool result]: notified

Assistant: Done. Worked the bigger wins, landed everything on `main`, and the post-merge measurement on a populated library settled the Win B question — with a surprise.

## What landed on `main` (`a52ae566`)
Three perf PRs, verified together (green build + 26 iOS tests + a real-kernel measurement):

| PR | Win | Effect |
|---|---|---|
| **#264** (mine) | Decode off the MainActor | User actions no longer stall the UI on the ~3.8 MB decode |
| **#265** (peer) | Playback ticks don't bump `rev` + `clean_html` memo | No full rebuild during playback |
| **#267** (mine) | **Fixed O(N²) snapshot rebuild** | **224 ms → 7.6 ms at 3,600 episodes (30×)** |

I drove the #264+#265 merge as you asked (resolved their `KernelModel.swift` collision so either order compiled), verified the merged tree locally since CI was badly backlogged, then measured.

## The headline: measurement found the real bottleneck
You gated Win B (the risky delta/wire-contract projection) on post-merge measurement. So I built a deterministic measurement that drives a **real seeded kernel handle** with a populated library (3,600 episodes) — and it surfaced something the empty-sim and synthetic-payload numbers had hidden: the full library rebuild was **O(N²)**, ~224 ms at 3,600 episodes (≈0.5–1 s on device), firing on every mark-played/star/pause and every background triage/categorization tick.

Cause: `build_podcast_update` read each episode's position via `position_for(id)`, which **linearly scans every episode (stringifying each UUID) to re-find the episode already in hand**. One line — read `ep.position_secs` directly — made it linear: **30× faster**, behavior-identical, 86 snapshot tests still pass, zero wire-contract change.

## Win B (delta projection): recommend skipping it
The measurement answers your gate. After these three fixes, a durable-change rebuild is ~7.6 ms Rust + an off-main decode — infrequent and non-UI-blocking. The delta projection's only remaining benefit (shrinking the 3.8 MB transfer + off-main decode) **doesn't justify the D5 wire-contract risk**. The O(N²) fix was the real win that the original transport analysis was circling around.

## Empirically confirmed on merged `main`
- Playing tick → `rev` unchanged (no rebuild); Paused → `rev` bumps. ✓
- Rebuild 224 ms → 7.6 ms, now linear. ✓
- Off-main decode present. ✓

