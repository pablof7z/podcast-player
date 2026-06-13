---
title: Briefing Player Host
slug: briefing-player-host
topic: agent-system
summary: FakeBriefingPlayerHost is the sole production host in BriefingPlayerView.prepareEngine(); BriefingPlayerHostProtocol has zero real conformers and no NowPlaying/
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-06-12
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:0f3f24f7-54de-49f8-b160-a92f735f6a00
---

# Briefing Player Host

## Production Host

CarPlay chapter visibility and chapter lists now resolve from the live Rust store projection (store.episodes) rather than the stale PlaybackState snapshot, with the poll tracker firing a refresh when navigableChapterCount changes on the same episode. (Previously: FakeBriefingPlayerHost is the sole production host in BriefingPlayerView.prepareEngine(); BriefingPlayerHostProtocol has zero real conformers and no NowPlaying/CarPlay integration exists. <!--  -->, superseded — see playback-state-seek-snapping.)

## Voice Interaction

BriefingPlayerView hold-to-ask mic returns hardcoded echo 'You asked: (transcript)' instead of a real agent answer; full agent-answer pipeline (Lane 6/8) is not wired. <!-- [^0f3f2-21] -->

## Missing Audio Handling

BriefingPlayerView missing audio files show a missing-audio banner instead of silently falling back to /dev/null. (Previously: Missing audio files fell back to URL(fileURLWithPath: '/dev/null') as the audioURL.) <!-- [^0f3f2-22] -->

## Share Action

The dead share button has been removed from BriefingPlayerView; tapping share previously did nothing (the action body was an empty comment with no ShareSheet invoked). <!-- [^0f3f2-23] -->
