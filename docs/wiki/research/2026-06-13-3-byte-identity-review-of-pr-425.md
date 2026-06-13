---
type: research-record
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
source_lines: 7977-7987
agent_attribution: a3d5753031e6277ca
has_preregistered_criteria: false
has_method: true
has_structured_report: true
characterization: "Byte-identity review of PR #425 slice-local builders: found one BLOCKER (queue-row builder drops per-episode derived fields), verdict FIX-FIRST"
captured_at: 2026-06-13T02:55:31Z
---

Byte-identity review of PR #425 slice-local builders: found one BLOCKER (queue-row builder drops per-episode derived fields), verdict FIX-FIRST

---

📋 SUMMARY: Adversarial byte-identity review of PR #425 found one BLOCKER in the slice-local playback queue builder; the other seven builders are byte-equivalent.

🔍 ANALYSIS: The golden test only exercises `build_podcast_update` directly with an empty queue, so it proves nothing about the slice-local path and never touches the divergent code.

⚡ ACTIONS: Compared all 8 slice-local builders + 2 store helpers against `build_podcast_update` and its callees via `git show`/`git diff`; inspected `EpisodeSummary` serde attributes and the golden fixture state.

✅ RESULTS: Found a confirmed byte-divergence in `build_queue_rows_from_store` (dropped per-episode derived fields) plus a related id-casing issue; widget/settings/identity/social/downloads/library/misc all reproduce prior output.

📊 STATUS: Review complete. Verdict: FIX-FIRST.

📁 CAPTURE: PR #425 `perf/slice-local-domain-payloads`. Riskies
