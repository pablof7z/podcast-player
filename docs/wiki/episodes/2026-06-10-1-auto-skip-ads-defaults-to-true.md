---
type: episode-card
date: 2026-06-10
session: dced2b33-dfba-41f2-b631-a0dffd418d59
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/dced2b33-dfba-41f2-b631-a0dffd418d59.jsonl
salience: product
status: active
subjects:
  - auto-skip-ads
  - settings-defaults
supersedes: []
related_claims: []
source_lines:
  - 1-1
  - 1055-1248
  - 1756-1944
captured_at: 2026-06-12T13:44:45Z
---

# Episode: Auto-skip-ads defaults to true

## Prior State

auto_skip_ads defaulted to false in all 7+ locations (Rust Settings::default(), PodcastStore::new(), PersistedSettings serde/default, Swift Settings, Swift SettingsSnapshot) — users who never explicitly toggled the setting had ad-skipping silently off

## Trigger

User reported that ads are not automatically skipped even with the toggle on, and explicitly stated the feature 'should default to true'

## Decision

Changed every default/fallback from false to true across Rust and Swift. Used serde(default = "default_true") for PersistedSettings so legacy JSON files missing the key hydrate as true. Users who explicitly set false are unaffected (serde only invokes default when key absent).

## Consequences

- New installs and upgrades from versions predating the field now have ad-skip on by default
- Existing users who explicitly turned it off retain their preference (explicit false in JSON)
- The setting's intended behavior now matches its default — ad segments are skipped unless the user opts out

## Open Tail

- The functional bug (ads still not skipped even when toggle is manually enabled) was not resolved in this session — potential timing race between engine.play() and kernelLoad, or iCloud sync resetting the value, remain as hypotheses

## Evidence

- transcript lines 1-1
- transcript lines 1055-1248
- transcript lines 1756-1944

