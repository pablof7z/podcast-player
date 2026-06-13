---
title: Local Model Inference
slug: local-model-inference
topic: agent-system
summary: "Local model inference uses a reverse-FFI callback: Swift registers a function pointer at startup via `nmp_app_register_local_llm`, Rust stores it, and `LocalMod"
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-03
updated: 2026-06-04
verified: 2026-06-03
compiled-from: conversation
sources:
  - session:4dd36f3c-199e-4d1b-9f63-2f86c41e2f2a
  - session:e1ab0629-64bc-4383-bd22-c0843ca16a99
  - session:56e47844-b4ff-4402-9528-c704eade1d7b
---

# Local Model Inference

## Reverse-FFI Callback Architecture

Local model inference uses a reverse-FFI callback: Swift registers a function pointer at startup via `nmp_app_register_local_llm`, Rust stores it, and `LocalModelBackend` calls it synchronously on a background `spawn_blocking` thread. Swift owns model lifecycle and Metal GPU session; Rust owns prompt construction and tool loop. Rust `LocalModelBackend` sends `{system, history, user}` and Swift inference parses that shape (not the old `{prompt}` shape).

The C FFI boundary defines `NmpLocalLlmFn` as `char* (*)(const char* prompt_json)` and the registration function `nmp_app_register_local_llm(handle, fn_ptr)`. The callback receives `(context, prompt_json)` — a context pointer alongside the prompt JSON string, not just a bare prompt pointer. Swift returns `strdup`-allocated strings; Rust frees them via `nmp_app_free_string`.

The local model FFI callback blocks a background thread for 1–3 seconds during inference, not the main UI thread. The UI remains responsive because the FFI call runs inside a `Task.detached`.

If the local model is selected as the provider but not loaded (cold launch or memory pressure eviction), the Rust `LocalModelBackend` returns `LlmError::Unavailable` — there is no silent cloud fallback because the user made a deliberate provider choice. (Previously: no entitlement requirement documented; PR #259 merged this fallback-removal behavior to main.)

The app requires the `com.apple.developer.kernel.increased-memory-limit` and `com.apple.developer.kernel.extended-virtual-addressing` entitlements to mmap the 2.6 GB Gemma model on-device. Without `increased-memory-limit`, LiteRT-LM's mmap of the 2.6 GB model fails with ENOMEM 'Cannot allocate memory', causing `litert_lm_conversation_send_message` to return null. PR #259 (increased-memory-limit entitlement + fallback removal) is merged to main.

`LocalLLMService` is a Swift `actor` that uses direct `async/await` for inference (no `DispatchSemaphore` on cooperative threads) and imports the real LiteRT-LM SPM package version 0.12.0.

<!-- citations: [^4dd36-8] [^4dd36-9] [^4dd36-10] [^4dd36-11] [^4dd36-12] [^e1ab0-11] [^56e47-3] -->

## Rust Dylib Embed Build Phases

Project.swift includes a `.pre` build phase that sets the Rust dylib's install name to `@rpath` before linking, and a `.post` phase that embeds and codesigns the dylib into the bundle's `Frameworks/`. The `.pre` install-name fix (before linking) is necessary because the `.post`-only approach left `Podcastr.debug.dylib` recording an absolute Mac path for the dylib dependency, causing dyld launch crashes on device. PR #255 (Rust dylib embed build phases) is merged to main. <!-- [^56e47-4] -->
