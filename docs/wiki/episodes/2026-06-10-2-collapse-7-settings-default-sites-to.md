---
type: episode-card
date: 2026-06-10
session: dced2b33-dfba-41f2-b631-a0dffd418d59
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/dced2b33-dfba-41f2-b631-a0dffd418d59.jsonl
salience: architecture
status: active
subjects:
  - settings-defaults
  - single-source-of-truth
  - settings-consolidation
supersedes:
  - 2026-05-13-9-wiki-model-fallback-must-use-canonical
related_claims: []
source_lines:
  - 2016-2072
captured_at: 2026-06-12T13:44:45Z
---

# Episode: Collapse 7+ settings-default sites to 2 canonical sources

## Prior State

Settings defaults were independently specified in 7+ locations across three type systems (Rust domain, Rust persistence, Swift snapshot/Swift domain) with no shared definition and no enforcement mechanism. Adding a new setting required updating all sites manually, and defaults had already drifted (auto_skip_ads was false in SettingsSnapshot::default() but true elsewhere after the initial fix).

## Trigger

User reaction: 'how can there be SEVEN defaults for auto skip ads???! how come it isn't ONE??' — the explicit recognition that fragmentation is a structural problem, not a one-off mistake

## Decision

PodcastStore::new() is the single canonical Rust default source. PersistedSettings::default() now delegates to PodcastStore::new().persisted_settings(). SettingsSnapshot::default() now calls build_settings_snapshot(&PodcastStore::new()) (memoized via OnceLock). The dead podcast_core::Settings type was deleted entirely. On the Swift side, Settings derives from SettingsSnapshot at runtime; all ?? literal decoder fallbacks removed. A cross-language fixture test enforces that the two remaining sites stay in sync.

## Consequences

- New settings need their default set in exactly one place (PodcastStore::new() for Rust, SettingsSnapshot property initializer for Swift)
- Default drift is caught structurally: Rust test fails until fixture is regenerated, Swift test fails until initializer is updated
- The SettingsSnapshot::default().auto_skip_ads_enabled = false bug (missed by PR #361) is fixed structurally by derivation
- disk.rs hydration no longer repeats 150+ literal fallbacks — uses PersistedSettings::default() as a single fallback object

## Open Tail

*(none)*

## Evidence

- transcript lines 2016-2072

