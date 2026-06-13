---
type: episode-card
date: 2026-06-03
session: 55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1.jsonl
salience: architecture
status: active
subjects:
  - delete-after-played
  - kernel-policy
  - d0-doctrine
supersedes: []
related_claims: []
source_lines:
  - 1025-1052
captured_at: 2026-06-12T13:11:23Z
---

# Episode: Delete-after-played policy moved from Swift to Rust kernel

## Prior State

The Rust kernel owned the auto_delete_downloads_after_played setting and the clear_local_path operation, but Swift decided when to trigger the delete — a D0 violation (Rust decides; Swift renders).

## Trigger

Explicit D0 doctrine enforcement task. The task's premise about DownloadCommand::DeleteFile was wrong (that variant doesn't exist), but the violation was real: Swift held the policy gate.

## Decision

Added PodcastStore::clear_local_path_if_auto_delete in Rust, wired it at both mark-played entry points (ItemEnd writeback and inbox MarkListened) for coverage parity, removed three Swift gates and the dead helper.

## Consequences

- Policy decision now lives in one Rust method — no Swift-side gating possible
- Both mark-played paths (natural end + manual mark-listened) trigger the policy, matching prior Swift coverage exactly
- Seven new tests (4 store-level + 3 seam tests) ensure future edits that sever the wiring fail loudly

## Open Tail

*(none)*

## Evidence

- transcript lines 1025-1052

