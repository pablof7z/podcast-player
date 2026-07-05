# I4 Evidence - SET-005 Storage, Downloads, And Data Settings

Run: 2026-07-05T19:40:50Z on iPhone 17 / iOS 26.2 with `--UITestSeed`.

Verdict: `fail`.

Issue: https://github.com/pablof7z/podcast-player/issues/717

## Evidence

| Artifact | UI critique | UX critique | Performance/accessibility notes |
| --- | --- | --- | --- |
| `assets/scenarios/i4-storage-downloads-settings/20260705T194050Z-downloads-list.jpg` | Downloads manager clearly separates Active, Failed, and Saved and labels the saved episode with `Downloaded` and `240 KB`. | The saved download and delete affordance are discoverable. | UI tree has 183 nodes and exposes `downloads-list`. No visible load delay was observed. |
| `assets/scenarios/i4-storage-downloads-settings/20260705T194100Z-settings-system-row.jpg` | Lower Settings rows are scannable and show concise summaries. | `Data & Storage, 4 records` gives a useful pre-navigation summary. | UI tree has 250 nodes after scrolling the settings list; scrolling remained responsive. |
| `assets/scenarios/i4-storage-downloads-settings/20260705T194110Z-data-storage-main.jpg` | Data & Storage main screen uses a clear three-action layout: Export Data, Downloads & Disk, Clear All Data. | The destructive copy clearly says credentials and identity are preserved. | UI tree has 171 nodes. Clear destructive copy reduces error risk. |
| `assets/scenarios/i4-storage-downloads-settings/20260705T194120Z-storage-detail-zero-kb.jpg` | Storage detail is visually simple but contradicts Downloads. | The user sees `Zero KB` and `Nothing on disk` after seeing one saved 240 KB episode, which breaks trust in cleanup/accounting. | UI tree has 174 nodes. This is a functional data consistency failure, not a rendering issue. |
| `assets/scenarios/i4-storage-downloads-settings/20260705T194130Z-export-data.jpg` | Export Data clearly lists record categories and JSON schema metadata. | The export summary is actionable and states that API keys/private keys are excluded. | UI tree has 213 nodes. Record count `4` matches the visible category breakdown: 1 subscription + 3 episodes. |

## Current Result

Observed:

- Downloads manager lists one saved downloaded episode at `240 KB`.
- Data & Storage main shows Export Data, Downloads & Disk, and Clear All Data.
- Export Data exposes 4 records and a share/export action.

Failure:

- Downloads & Disk reports `Zero KB` and `Nothing on disk` in the same seeded
  run where Downloads reports one saved `240 KB` episode.

## Gap

Clear All Data teardown was intentionally skipped. The storage mismatch blocks
I4 from passing until the underlying accounting path is fixed or the UI explains
why the saved download is excluded from disk totals.
