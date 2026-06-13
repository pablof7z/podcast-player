---
type: research-record
date: 2026-06-12
session: ede5e5c5-01cb-4985-aae5-6a4e1b09fc08
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/ede5e5c5-01cb-4985-aae5-6a4e1b09fc08.jsonl
source_lines: 1900-1937
agent_attribution: main
has_preregistered_criteria: false
has_method: true
has_structured_report: true
characterization: "End-to-end download and transcription pipeline test: download feedback fixes PASS (✅), transcription FAIL (❌) due to path mismatch, chapters FAIL (❌) blocked by transcription"
captured_at: 2026-06-12T13:33:01Z
---

End-to-end download and transcription pipeline test: download feedback fixes PASS (✅), transcription FAIL (❌) due to path mismatch, chapters FAIL (❌) blocked by transcription

---

## Test Results

### Download Feedback Fixes (PR #343) — ✅ All passing

1. **Immediate `.queued` indicator**: Faint full-width bar appears on the row within milliseconds of tapping Download — no more blank start
2. **Swipe → "Cancel" for queued**: Fixed and confirmed working  
3. **Immediate 0-byte progress emit**: `rev=40` fires at 12:36:52.475 (same timestamp as `task.resume()`) — Rust transitions from `.queued` → `.downloading` instantly, not after 60s
4. **Download completes**: `rev=41` fires 6 seconds later — accessibility label flips to `"...unplayed, downloaded"`, swipe shows "Free up"
5. **No spurious cancels**: Both episodes downloaded clean, no OS-driven cancel

---

### Transcription — ❌ Pre-existing bug (separate from PR #343)

**Root cause: path mismatch**

| | Path |
|---|---|
| `DownloadCapability` saves to | `AppSupport/Downloads/<uuid>.mp3` |
| `EpisodeDownloadStore` expects | `AppSupport/podcastr/downloads/<uuid>.mp3` |

`podcastr/downloads/` is empty — `EpisodeDownloadStore.shared.exists(for: episode)` always returns `false`.

In `TranscriptIngestService.runAITranscription`, the guard at line 221:
```swift
if provider == .appleNative && !EpisodeDownloadStore.shared.exists(for: episode) {
    return  // silent exit — no log, no state change
}
```
With no API keys in the sim (default = `appleNative`), every ingest silently exits here. This was the bug the peer agent was already investigating.

### Chapters — ❌ Blocked by transcription

Chapters are generated as a side-effect of `persistAndIndex` (Step 3 in `TranscriptIngestService`), which only runs after transcription succeeds. Since transcription never starts, chapters never generate.

---

**Bottom line**: The download feedback fixes in PR #343 are correct and verified working. The transcription/chapters pipeline has a pre-existing path mismatch bug that needs a separate fix — either reconcile `DownloadCapability.downloadsDirectory()` with `EpisodeDownloadStore.rootURL`, or fix `EpisodeDownloadStore.exists()` to also check the legacy `Downloads/` path.
