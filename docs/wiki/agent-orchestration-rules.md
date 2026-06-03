---
title: Agent Orchestration Rules
slug: agent-orchestration-rules
summary: The main thread should only orchestrate — all implementation, review, and decision-making should be delegated to agents.
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-01
updated: 2026-06-03
verified: 2026-06-01
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
  - session:4dd36f3c-199e-4d1b-9f63-2f86c41e2f2a
---

# Agent Orchestration Rules

## Orchestration Principle

The main thread should only orchestrate and never implement directly, including decisions on what to work on next and reviewing code — all work must be delegated to agents. Implementation is executed via a multi-agent workflow: an Opus agent plans it, Haiku agents implement it in parallel in the same git worktree, a Sonnet agent reviews it, and upon completion it is merged to main immediately with proper testing. Code reviews use Opus agents instead of codex CLI. Every substantive PR must be reviewed by an Opus agent before merge.

<!-- citations: [^14943-99] [^14943-132] [^4dd36-8] -->
