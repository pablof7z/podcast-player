---
type: episode-card
date: 2026-06-10
session: 38f8143c-c90d-49e3-a8fa-8d5ca17ac319
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/38f8143c-c90d-49e3-a8fa-8d5ca17ac319.jsonl
salience: root-cause
status: active
subjects:
  - widget-snapshot
  - now-playing
  - episode-lookup
  - uuid-case
supersedes: []
related_claims: []
source_lines:
  - 1552-1575
  - 1606-1626
captured_at: 2026-06-12T13:48:00Z
---

# Episode: UUID case mismatch leaves widget idle during live playback

## Prior State

Kernel's WidgetSnapshot projection was assumed to populate now_playing fields during active playback; the iOS audio engine plays independently via its own path, creating the appearance of functioning playback

## Trigger

Live simulator PROOF 2 showed confirmed playback (mini-player advancing, MPNowPlayingInfoCenter populated) but the App Group nmp.widget.snapshot.v1 stayed idle: is_playing=false, no now_playing_episode_title, position/duration 0. The kernel was emitting an idle snapshot on every tick

## Decision

Root-cause diagnosed: iOS dispatches podcast.player load/play with UPPERCASE UUID.uuidString, but kernel stores lowercase Rust Uuid strings; case-sensitive == in episode_playback_info fails, handle_play/handle_load bail with 'episode not found' before stage_load sets episode_id; PodcastUpdate.now_playing is gated on episode_id.is_some(), so widget stays idle. Fix: case-insensitive episode lookup in PR #373, with regression pin (snapshot_widget_seam_tests.rs) that drives the real UPPERCASE play host-op + AudioReport::Playing and asserts both now_playing and widget populate

## Consequences

- Explains the apparent contradiction: iOS audio engine plays on its own path independent of kernel Load, so the mini-player advances while the kernel thinks nothing is playing
- The change-gate correctly suppressed plist rewrites because the kernel kept emitting identical idle snapshots
- Kernel-only fix preserves the validated D4 iOS write seam from #366/#371
- A home-screen now-playing widget would have rendered the idle state while audio played — a user-visible defect

## Open Tail

- PROOF 2 and PROOF 3 (change-gating) need live re-verification after #373 merges to confirm now_playing populates and pause transitions reach the plist

## Evidence

- transcript lines 1552-1575
- transcript lines 1606-1626

