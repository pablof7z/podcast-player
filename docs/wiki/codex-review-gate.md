---
title: Codex Review Gate
slug: codex-review-gate
topic: project-setup
summary: All references to the deprecated 'codex exec review --base main' CLI must be replaced with Opus agent terminology across codex-review-gate.md, d5-wire-contract.
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-02
updated: 2026-06-13
verified: 2026-06-02
compiled-from: conversation
sources:
  - session:8bfa1b91-b40c-44b3-acb9-245b36f4c841
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
---

# Codex Review Gate

## Terminology: Opus Agent vs. Deprecated CLI

All references to the deprecated 'codex exec review --base main' CLI must be replaced with Opus agent terminology across codex-review-gate.md, d5-wire-contract.md, m1-stack-integration.md, and disk-full-recovery.md.

Reviewers must never perform working-tree git operations (checkout, restore, stash, add) in the shared root; they use read-only `git diff`/`git show` from the object DB to avoid clobbering uncommitted work.

<!-- citations: [^8bfa1-1] [^c1691-17] [^c1691-36] [^c1691-132] [^c1691-203] [^c1691-230] [^c1691-251] -->
