---
title: Sleep Timer
slug: sleep-timer
topic: playback
summary: SleepTimer exposes a shake-to-extend API; ShakeDetector integration is deferred to Lane 4.
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
  - session:c33b9adb-9d1a-4717-9314-b45a61e6cbc3
  - session:rollout-2026-05-10T20-46-07-019e12ff-1573-7b82-ba04-59c91f91ebce
  - session:rollout-2026-05-11T08-21-01-019e157b-4863-7563-a43b-8405491d88a1
  - session:rollout-2026-05-11T09-10-30-019e15a8-9491-7d33-9bbf-ee806e2f875c
---

# Sleep Timer

## Integration

SleepTimer exposes a shake-to-extend API; the ShakeFeedbackCore migration into NMP (issue #270) was merged and closed, no longer deferred to Lane 4. (Previously: SleepTimer exposes a shake-to-extend API; ShakeDetector integration is deferred to Lane 4, superseded — see nmp-version-upgrades.) Android sleep timer (issue #323) is fixed by PR #342. UI selection for the sleep timer should be derived from the engine mode/phase, or a single timer state model owned above both engine and UI should be added. The SleepTimer.extend(by:) method is unused dead code and should be removed or shake-to-extend should be properly implemented. Sleep timer fire must pause through PlaybackState instead of directly through AudioEngine.

<!-- citations: [^0f3f2-65] [^c33b9-8] [^rollo-55] [^rollo-84] [^rollo-127] -->
