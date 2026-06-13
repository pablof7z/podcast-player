---
title: Product Spec Conventions
slug: product-spec-conventions
topic: project-setup
summary: PRODUCT_SPEC must respect the hard-limit concerns and must not have additional sections stuffed into it
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-11
updated: 2026-06-12
verified: 2026-05-11
compiled-from: conversation
sources:
  - session:rollout-2026-05-11T09-10-31-019e15a8-991d-7890-957e-f45fb0ff5a7c
  - session:rollout-2026-05-25T12-50-00-019e5e8a-9307-7903-9302-dbc867f91c61
  - session:rollout-2026-05-25T12-53-43-019e5e8d-f919-7521-a540-9ca4b95f10ff
  - session:rollout-2026-05-25T22-18-09-019e6092-b9c8-7f53-b3e0-898bfeec48c4
---

# Product Spec Conventions

## PRODUCT_SPEC Conventions

PRODUCT_SPEC.md is split into section files serving as entry points rather than a single monolithic file. (Previously: PRODUCT_SPEC must respect the hard-limit concerns and must not have additional sections stuffed into it, superseded — see rootview-extensions.) Only existing lines may be replaced, with no new sections added. Every durable concept should have one canonical representation and one code path to avoid fragmentation. The `docs/spec/` directory must be kept as product/spec archive material, not as the current source of truth for active implementation status. Active feature guides and wiki operating pages are updated to match the current Pod0/NIP-F4 code; historical/archived product-spec and research docs are left unchanged.

<!-- citations: [^rollo-135] [^rollo-172] [^rollo-191] [^rollo-208] -->
## Repository Workflow

The repository uses exactly three canonical planning/status files: docs/plan.md for the overarching plan, docs/BACKLOG.md for the tactical queue, and WIP.md for in-flight branch tracking. (Previously: The repo uses an NMP-style workflow with `AGENTS.md`, `WIP.md`, `docs/plan.md`, `docs/BACKLOG.md`, and `docs/plan/pod0-nostr-publishing.md`. <!--  -->, superseded — see project-workflow.)
