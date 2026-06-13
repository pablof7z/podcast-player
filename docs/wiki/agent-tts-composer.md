---
title: Agent TTS Composer
slug: agent-tts-composer
topic: agent-system
summary: AgentTTSComposer.audioDuration throws AudioDurationError (.zeroDuration or .assetLoadFailed) instead of returning fabricated durations
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-05-13
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:0f3f24f7-54de-49f8-b160-a92f735f6a00
---

# Agent TTS Composer

## Audio Duration Error Handling

AgentTTSComposer.audioDuration throws AudioDurationError (.zeroDuration or .assetLoadFailed) instead of returning fabricated durations. buildTracks catches per-turn, logs the bad URL, skips the turn, and only adds surviving turns to the parallel arrays. (Previously: TTS duration returned hardcoded 1.0 when <=0 and 60.0 on AVURLAsset load failure, which corrupted chapter math silently.) <!-- [^0f3f2-11] -->

## Episode Title Resolution

AgentTTSComposer.resolveEpisodeTitle returns String? and logs the missing episodeID. Snippet chapters fall back to 'Quote at M:SS' using the snippet's actual start offset instead of the generic word 'Clip'. (Previously: fell back to literal 'Clip' when episode title was unresolved.) <!-- [^0f3f2-12] -->

## Snippet Duration Validation

AgentTTSComposer snippet duration = end - start does not validate that end > start; negative durations would still corrupt chapter math. <!-- [^0f3f2-13] -->
