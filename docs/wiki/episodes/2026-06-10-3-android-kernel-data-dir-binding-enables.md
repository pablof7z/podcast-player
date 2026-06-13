---
type: episode-card
date: 2026-06-10
session: 38f8143c-c90d-49e3-a8fa-8d5ca17ac319
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/38f8143c-c90d-49e3-a8fa-8d5ca17ac319.jsonl
salience: product
status: active
subjects:
  - android-persistence
  - kernel-data-dir
  - native-set-data-dir
supersedes: []
related_claims: []
source_lines:
  - 1025-1156
captured_at: 2026-06-12T13:48:00Z
---

# Episode: Android kernel data-dir binding enables persistence across process restarts

## Prior State

Android kernel state lived only in memory; process restart (am force-stop, OS reclaim, etc.) caused complete data loss — podcasts, subscriptions, queue, identity, and settings were all ephemeral

## Trigger

NMP/RMP architecture audit identified that the kernel must own persistence per the Rust-owns-state doctrine; Android was missing the data-dir binding that iOS already had

## Decision

MainActivity calls bridge.setDataDir(context.filesDir) before bridge.start(), routing through JNI to nativeSetDataDir → nmp_app_podcast_set_data_dir, which loads podcasts.json, identity, queue, relay config, and triage cache from the bound data directory (PR #368)

## Consequences

- Subscriptions, queue, identity, and settings now survive process restart on Android, bringing parity with iOS
- The ordering constraint (setDataDir before start) is now load-bearing — calling start first would leave the kernel in ephemeral mode
- Verified live: podcasts.json created at /data/data/io.f7z.podcast/files/, persisted through am force-stop + relaunch with content intact

## Open Tail

*(none)*

## Evidence

- transcript lines 1025-1156

