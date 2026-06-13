---
title: Clip Exporter
slug: clip-exporter
topic: playback
summary: ClipExporter.exportVideo and ClipVideoComposer.exportVideo unconditionally throw .notImplemented; the entire file is flagged STUBBED
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-06-10
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:0f3f24f7-54de-49f8-b160-a92f735f6a00
  - session:b4d663c7-85f0-4086-9bdc-030177ef43e5
  - session:681fa743-322c-4b1a-8e99-81a97aa1a904
---

# Clip Exporter

## Export Pipeline

ClipExporter.exportVideo and ClipVideoComposer.exportVideo unconditionally throw .notImplemented; the entire file is flagged STUBBED. ClipComposerSheet share button routes to a shareTargetPlaceholder view reading 'Share targets coming soon'; real share stack is not wired. clip.shared is a reserved event kind but is deliberately not wired because SwiftUI's ShareLink provides no completion callback; clip.exported serves as the meaningful signal instead.

<!-- citations: [^0f3f2-27] [^681fa-2] -->
## Subtitle & Handles

ClipVideoOverlayLayer supports sentence-level subtitle cues only; word-level karaoke is deferred. ClipComposerHandlesView wordSnap was never a parameter, only a stale doc comment; the comment has been rewritten to remove the v2 reference and correct 'second-values' to 'millisecond-values'. <!-- [^0f3f2-28] -->

## Speculative Code

ClipVideoComposer retains helper code speculatively for a future implementation pass. <!-- [^0f3f2-29] -->

## Clippings Ghost-Header Fix

The Clippings ghost-header defect is caused by clipRow guarding on store.episode(id:) and rendering nothing when the episode is nil, while the date-bucket Section header still shows, leaving a lone 'EARLIER' heading over blank space. The fix renders clipRow unconditionally, since ClippingsCard already accepts episode: Episode? and degrades gracefully with nil (placeholder artwork, omitted title, still shows caption/quote/footer); only episode-navigation is gated on a resolvable episode. The fix is committed as 19b46163, pushed to origin/qa/device-scenario-tests (PR #268), with a whats-new entry, and is build-verified (BUILD SUCCEEDED, installs on device and sim); the empty-state path is visually confirmed on sim (shows 'No Clippings Yet' with no ghost headers), but the orphan-case visual repro is not yet done. <!-- [^b4d66-1] -->

## Clip Storage

Clips are held by the kernel (clip_handler.rs ClipRecord / handle.clips), likely persisted inside podcasts.json or the App Group state file, not in a separate clips.json file. <!-- [^b4d66-2] -->
