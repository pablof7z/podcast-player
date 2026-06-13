---
type: episode-card
date: 2026-05-15
session: ce9e0cdb-a00d-4c13-ad7e-93e3dced2648
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/ce9e0cdb-a00d-4c13-ad7e-93e3dced2648.jsonl
salience: root-cause
status: active
subjects:
  - audio-engine-load
  - agent-generated-podcast
  - episode-download-store
  - container-path-rotation
supersedes: []
related_claims: []
source_lines:
  - 794-868
  - 896-918
  - 944-960
captured_at: 2026-06-12T12:36:03Z
---

# Episode: Agent-generated episodes fail to play due to stale file URL resolution

## Prior State

AudioEngine.load(_:) resolved local audio via EpisodeDownloadStore.shared.exists() (checks only downloads/ directory) then fell back to episode.enclosureURL. Agent-generated episodes are stored in agent-episodes/, not downloads/, so EpisodeDownloadStore always returned false — forcing the engine to use the persisted enclosureURL, which becomes stale after iOS rotates the app container path between launches. This caused AVPlayerItem to fail silently: playback never started, current time stayed at 0.

## Trigger

User reported agent-generated podcast episodes do not play at all — 'it doesn't play anything, it just sits there, current time doesn't increase either.' Code analysis confirmed EpisodeDownloadStore lacks awareness of the agent-episodes/ directory, and stored absolute file:// URLs rot on container path rotation.

## Decision

Modified AudioEngine.load(_:) to attempt path recomputation via AgentGeneratedPodcastService.audioFileURL(episodeID:) for episodes whose downloadState is .downloaded but not found by EpisodeDownloadStore — recomputing the fresh container path via FileManager before falling back to the stale enclosureURL.

## Consequences

- Agent-generated episodes now resolve their audio file path freshly at load time, surviving iOS container rotation
- The two-path resolution (downloads/ for RSS episodes, agent-episodes/ for synthetic ones) is now explicit in the load path rather than accidentally falling through
- Future episode types added outside downloads/ must also be wired into this resolution chain

## Open Tail

- Build and install to verify the fix on device — log capture tool returned empty logs both attempts, so live testing is the only confirmation
- Consider whether AgentGeneratedPodcastService.audioFileURL should be promoted to a protocol/shared service that EpisodeDownloadStore or AudioEngine can reference without direct coupling

## Evidence

- transcript lines 794-868
- transcript lines 896-918
- transcript lines 944-960

