---
type: episode-card
date: 2026-06-04
session: 56e47844-b4ff-4402-9528-c704eade1d7b
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/56e47844-b4ff-4402-9528-c704eade1d7b.jsonl
salience: root-cause
status: active
subjects:
  - on-device-llm
  - gemma-e2b
  - entitlements
  - mmap-enomem
supersedes: []
related_claims: []
source_lines:
  - 4671-4677
  - 4681-4697
  - 4744-4753
  - 4835-4846
  - 5477-5499
captured_at: 2026-06-12T13:17:31Z
---

# Episode: On-device LLM fails without iOS increased-memory-limit entitlement

## Prior State

On-device Gemma 4 E2B (2.6 GB) model silently failed — native sendMessage returned null — and the app showed a misleading 'Couldn't reach the agent' error. The app had no increased-memory-limit entitlement, so iOS capped the process address space below what mmap of the model weights required.

## Trigger

Diagnosis of the native crash log revealed LiteRT-LM's mmap of the 2.59 GB model file failed with ENOMEM ('Cannot allocate memory'). Other apps on the same device ran the same model because they ship the entitlement; Podcastr did not.

## Decision

Added com.apple.developer.kernel.increased-memory-limit and com.apple.developer.kernel.extended-virtual-addressing to Podcastr.entitlements. Verified mmap status went from 'Cannot allocate memory' to 'ok', model loaded (976 subgraphs, 4 signatures), and on-device inference returned real output.

## Consequences

- On-device Gemma inference now works — single-engine XCTest produced 'Hello!' and XCUITest driving the real UI got 'Hey Pablo — ready when you are.'
- First message after cold launch is slow (~minutes for model mmap + load); a 'warming up' indicator would help UX
- Any iOS app shipping a large on-device model (>1 GB) must carry these entitlements or mmap will fail silently

## Open Tail

- Cold-start latency UX (model warm-up indicator) not yet implemented

## Evidence

- transcript lines 4671-4677
- transcript lines 4681-4697
- transcript lines 4744-4753
- transcript lines 4835-4846
- transcript lines 5477-5499

