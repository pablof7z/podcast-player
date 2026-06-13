---
title: Tuist Project Configuration
slug: tuist-project-configuration
topic: project-setup
summary: The project uses Tuist with a glob pattern `App/Sources/**` for source files
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-06-12
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:9692d124-a1a0-411c-91f9-9d6ebc0b29b1
  - session:1eb0c519-6723-489e-b777-71997fd7e216
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
  - session:84c4d49c-d034-4d2e-8e1e-dfd5a4453b2d
  - session:f3b466c6-7791-44b3-b004-aae2066a9019
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
  - session:a6320d4d-f2c8-4a8b-a21a-d71f5af73509
  - session:04b5f843-fdbe-4aa1-ae41-6770eac82957
  - session:rollout-2026-05-10T20-46-06-019e12ff-12ba-79d2-a14c-78a7ec6b0bfa
  - session:rollout-2026-05-25T12-53-35-019e5e8d-dcce-7582-85bd-8c4b7d017c17
  - session:rollout-2026-05-25T12-53-43-019e5e8d-f919-7521-a540-9ca4b95f10ff
  - session:rollout-2026-05-25T12-53-46-019e5e8e-043d-7dc2-8171-2238de03d145
  - session:rollout-2026-05-25T22-18-09-019e6092-b9c8-7f53-b3e0-898bfeec48c4
  - session:rollout-2026-05-26T10-26-17-019e632d-5c5d-7bb3-8b90-fb176055c79d
---

# Tuist Project Configuration

## Source File Configuration

The live iOS app compiles from App/Sources/, not the decommissioned ios/Podcast/Podcast/ directory. The project uses a Tuist-generated Xcode project with glob sources (App/Sources/**, AppTests/Sources/**); the committed project.pbxproj is a force-tracked generated artifact, and canonical project configuration lives in Project.swift. Generated project/workspace outputs (Podcastr.xcodeproj/project.pbxproj, Podcastr.xcworkspace) must be regenerated with tuist generate after Project.swift changes, not hand-edited. tuist generate must be run whenever project shape, target membership, resources, entitlements, packages, or generated Xcode project state may have changed. When salvaging dirty changes onto a fresh worktree, prefer source/test/Tuist project membership over stale xcodeproj churn and run tuist generate only if project membership changed. The project uses Tuist with an App/Sources/** glob that auto-includes new files on the next tuist generate. ci_scripts/bootstrap_project.sh runs tuist generate --no-open. project.pbxproj is gitignored in this repo; feature PRs do not commit pbxproj regen. DerivedDevice/ must be added to .gitignore (or a broader Derived*/ rule), and the local generated directory removed. ENABLE_USER_SCRIPT_SANDBOXING is set to NO in Project.swift because the pre-build script invokes cargo build which writes to App/core/target/. Validation must include Tuist regeneration when project shape changes, focused xcodebuild test, and git diff --check.

<!-- citations: [^f3b46-24] [^9692d-5] [^1eb0c-7] [^84c4d-14] [^14943-25] [^a6320-11] [^04b5f-8] [^rollo-59] [^rollo-177] [^rollo-192] [^rollo-201] [^rollo-214] [^rollo-262] -->
## CI Simulator Destination

The CI iOS sim destination fix (PR #392) replaces the hardcoded "iPhone 17" with runtime UDID discovery preferring *ci sims then any available iPhone simulator, restoring the silently-dead Build and Test gate. <!-- [^c1691-15] -->

## Agent Worktree and Git Discipline

Implementer agents on this repo must use worktree isolation (not the shared checkout) to prevent clobbering, and the default branch is main (not master). Inspector/reviewer agents must use git diff/show only and never run working-tree git operations (checkout, restore, etc.) in the shared root, to prevent clobbering uncommitted WIP from other agents. <!-- [^c1691-16] -->

## Worktree Symlink for Tuist

A worktree-local symlink at .claude/worktrees/ios-shake-feedback is required for tuist generate to resolve the ../ios-shake-feedback package path when building inside the .claude/worktrees/ directory. <!-- [^f3b46-25] -->

## Path Conventions

Paths in the repo must use /Users/pablofernandez/Work/..., not stale /home/pablo/... paths from the NMP migration plan. <!-- [^rollo-193] -->
