---
title: RootView Extensions
slug: rootview-extensions
topic: project-setup
summary: Files must stay under the 500-line AGENTS.md limit; RootView.swift was refactored from 721 lines down to ~395 lines by extracting extensions into separate files
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-14
updated: 2026-06-12
verified: 2026-05-14
compiled-from: conversation
sources:
  - session:1eb0c519-6723-489e-b777-71997fd7e216
  - session:2a4cc6d5-8204-4e85-9d30-198832dc52a2
  - session:84c4d49c-d034-4d2e-8e1e-dfd5a4453b2d
  - session:02078283-91db-41b1-80f8-989daef628ac
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
  - session:c33b9adb-9d1a-4717-9314-b45a61e6cbc3
  - session:rollout-2026-05-09T14-55-33-019e0c97-c60d-7bb1-84ac-b4898708e7d6
  - session:rollout-2026-05-09T17-51-25-019e0d38-c712-70c3-9607-bb9c5c518360
  - session:rollout-2026-05-10T10-27-27-019e10c8-ab1d-7523-8825-9bb1a52e6aac
  - session:rollout-2026-05-10T20-45-04-019e12fe-1fe8-7d93-a41f-0cebfa991f0a
  - session:rollout-2026-05-10T20-46-06-019e12ff-12ba-79d2-a14c-78a7ec6b0bfa
  - session:rollout-2026-05-10T20-50-50-019e1303-6619-7020-b335-29bdce14a986
  - session:rollout-2026-05-11T08-21-02-019e157b-4d93-7042-aab8-cc756f719dcd
  - session:rollout-2026-05-13T16-51-04-019e219a-f6d8-78d2-8c63-e09938281252
  - session:rollout-2026-05-17T10-33-06-019e34da-5c83-7591-8bfc-850541168727
  - session:rollout-2026-05-25T12-53-39-019e5e8d-ec64-74f1-a1b1-91055dcab442
---

# RootView Extensions

## Architecture

Files have a soft length limit of 300 lines, preferring to split into smaller files when approaching that threshold. Files must not exceed 500 lines (hard limit); code must be refactored before adding more code to a file approaching that limit. Files slightly over the 300-line soft limit but under the 500-line hard limit may be committed without structural refactoring. Do not commit generated build output. PRODUCT_SPEC.md is split into section files serving as entry points rather than a single monolithic file. RootView.swift was refactored from 721 lines down to ~395 lines by extracting extensions into separate files. host_op_handler.rs was split from 800 lines into host_op_handler.rs (421), settings_actions.rs (309), and dispatch.rs (97) to satisfy the 500-line hard limit. Owned-podcast tool schemas live in a separate file (AgentToolSchema+OwnedPodcasts.swift) to keep AgentToolSchema+Podcast.swift under the 500-line hard limit. publishFeedbackNote was moved from UserIdentityStore.swift to the Publishing extension to keep the main file under the 500-line hard limit (result: 488 lines). File size hard limit violations (issue #325) were fixed by splitting 5 oversized Rust files (snapshot.rs, inbox_handler.rs, etc.) into cohesive siblings, with 1095 tests green, via PR #347. RootView state properties accessed from extension files use `internal` access (no `private` modifier) to allow cross-file access. RootView no longer holds clipSourceEpisodeID state or an onReceive(.openEpisodeDetailRequested) handler. When merging remote changes, the RootView.swift conflict resolution keeps the local sidebar layout version over the remote's older version. Tracked text files must not exceed 500 lines. README.md still contains stale template placeholders that must be rewritten, along with fixing the Xcode 15.0+ requirement that conflicts with the iOS 26 deployment target. (Previously: Docs do not contain old bundle/template names, superseded — see nmp-version-upgrades.) The Downloads Manager implementation is split across DownloadsManagerView.swift, DownloadsManagerRows.swift, and DownloadsManagerModels.swift to stay under the hard 500-line file limit. The `HighlightedText` component must be moved from the dead `UniversalSearchView`/`UniversalSearchResults` code to `Design/HighlightedText.swift`, and the universal search files must be deleted or deliberately remounted. `DiscoverSearchField`, `DiscoverResultList`, `DiscoverSearchState`, and `ShowDetailSettingsSheet` must each be extracted into separate files to bring `DiscoverSearchForm.swift` (469 lines) and `ShowDetailView.swift` (463 lines) under the hard 500-line limit. InboxTriageService.swift was refactored by extracting EngagementBuilder into its own file to stay under the 300-line soft cap, and inbox_llm.rs was gutted to only contain TriageResult and TriageStatus types with all LLM calling code removed. (Previously: New files `InboxTriageService.swift` (341 lines) and `Episode.swift` (472 lines) must be refactored to respect the 300-line soft / 500-line hard file-length limits, superseded — see inbox-triage.) New helper files have been added for per-podcast keys and wire constants instead of adding logic to large existing files like LiveAgentOwnedPodcastManager and discovery, completing the required split. (Previously: `LiveAgentOwnedPodcastManager.swift` (380 lines) and discovery (305 lines) must be split into helpers to stay under the repo file-length rules, superseded — see agent-owned-podcasts.)

<!-- citations: [^rollo-36] [^1eb0c-5] [^1eb0c-6] [^2a4cc-4] [^84c4d-13] [^02078-7] [^14943-22] [^c33b9-7] [^rollo-1] [^rollo-24] [^rollo-50] [^rollo-58] [^rollo-61] [^rollo-103] [^rollo-154] [^rollo-155] [^rollo-186] -->
