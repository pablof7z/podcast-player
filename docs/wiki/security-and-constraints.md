---
title: Security and Constraints
slug: security-and-constraints
summary: "Security constraints: nsec never logged, real relay only, Ollama models, and the reactive-no-polling rule."
tags:
  - security
  - nsec
  - relay
  - ollama
  - reactive
volatility: cold
confidence: medium
created: 2026-05-29
updated: 2026-05-29
verified: 2026-05-29
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# Security and Constraints

> Security constraints: nsec never logged, real relay only, Ollama models, and the reactive-no-polling rule.

## nsec Handling

The nsec MUST NOT be logged. It is forwarded straight to the kernel FFI, which copies it into `Zeroizing<String>` on the Rust side. The `KernelBridge+Identity.swift` file contains a `// SECURITY: the nsec MUST NOT be logged.` comment marker. [^14943-66]

## Relay Configuration

The app uses the real relay `relay.primal.net`. No fake or test relays are permitted in any configuration (development, testing, or production). [^14943-67]

## Ollama Configuration

Ollama runs at `http://localhost:11434`. Two models are available:
- `deepseek-v4-flash:cloud` — fast model for quick responses
- `deepseek-v4-pro:cloud` — thinking model for complex analysis [^14943-68]

## Reactive Over Polling

Nostr code must be reactive — no polling. This is a D8 requirement. Any timer-based polling loop is forbidden. Updates must be event-driven via the kernel push channel or event-driven one-shot pulls at known change sites (e.g., after shell-initiated reports). The `Nostr code must be reactive, no polling` rule was the user's explicit instruction and is enforced by the codex review gate. [^14943-69]


Agent-to-agent communication and friend messages use public kind:1 notes threaded via NIP-10, matching the reference implementation at `/Users/pablofernandez/Work/win-the-day-app`. NIP-17 (kind 14/1059) is an explicit non-goal and must not appear as planned work anywhere in the backlog, plan, or spec documents. [^14943-14]
## See Also
- [[reactive-update-model|Reactive Update Model (No Polling)]] — related guide
- [[nmp-integration-rules|NMP Integration Rules]] — related guide
- [[agent-and-social-protocols|Agent-to-Agent and Social Protocols]] — related guide

