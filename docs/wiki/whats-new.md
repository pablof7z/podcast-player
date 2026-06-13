---
title: What's New
slug: whats-new
topic: project-setup
summary: Every user-facing change requires an entry in `whats-new.json`.
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-14
updated: 2026-06-09
verified: 2026-05-14
compiled-from: conversation
sources:
  - session:1eb0c519-6723-489e-b777-71997fd7e216
  - session:2a4cc6d5-8204-4e85-9d30-198832dc52a2
  - session:02078283-91db-41b1-80f8-989daef628ac
  - session:a6b98d9b-32b6-49e0-9bda-3204ca8808bb
  - session:04b5f843-fdbe-4aa1-ae41-6770eac82957
  - session:rollout-2026-05-11T08-21-01-019e157b-49b7-7663-891c-1c44d125ca44
  - session:rollout-2026-05-11T08-21-01-019e157b-4863-7563-a43b-8405491d88a1
  - session:rollout-2026-05-11T08-21-02-019e157b-4d93-7042-aab8-cc756f719dcd
  - session:rollout-2026-05-11T09-10-30-019e15a8-9491-7d33-9bbf-ee806e2f875c
  - session:rollout-2026-05-13T09-40-04-019e2010-60db-72b0-af0f-d40f44ca1989
  - session:rollout-2026-05-13T11-19-46-019e206b-a5e1-75a3-99e2-4500171ec8cc
  - session:rollout-2026-05-13T12-06-20-019e2096-4937-7fa1-bf10-5bb75b265a8d
  - session:rollout-2026-05-25T12-53-35-019e5e8d-dcce-7582-85bd-8c4b7d017c17
  - session:rollout-2026-05-25T12-53-39-019e5e8d-ec64-74f1-a1b1-91055dcab442
  - session:rollout-2026-05-25T12-53-46-019e5e8e-043d-7dc2-8171-2238de03d145
  - session:rollout-2026-05-26T10-16-01-019e6323-f6b1-7f03-85ec-1a51289f331a
---

# What's New

## What's New Entries

Every commit that ships a user-facing change to the iPhone must add an entry to `App/Resources/whats-new.json` with a one-liner the user will read, containing `shipped_at` (current UTC, ISO-8601) and `lines`. The `shipped_at` value must be current UTC, not local time with a `Z` suffix, to avoid future timestamps that suppress later entries. The decision to add a whats-new entry is guided by whether the user would notice the change; when in doubt, add a line. The app surfaces whats-new entries whose `shipped_at` is newer than the user's last-seen marker, with no commit SHA needed. Timestamps in `whats-new.json` must be unique across entries; if two land in the same minute, bump one by a minute. Purely-internal commits (encoder caches, log line tweaks, formatting) must not receive a whats-new entry. A rename implementation commit is a user-facing change and requires a whats-new entry. The NIP-F4 publishing/discovery change is a user-facing behavior change and requires a whats-new entry when it ships. WhatsNewServiceTests must be kept parseable with `App/Resources/whats-new.json` and a user-facing changelog line added.

<!-- citations: [^1eb0c-8] [^2a4cc-5] [^02078-8] [^a6b98-10] [^04b5f-9] [^rollo-75] [^rollo-85] [^rollo-104] [^rollo-128] [^rollo-139] [^rollo-140] [^rollo-142] [^rollo-178] [^rollo-187] [^rollo-203] [^rollo-246] -->
