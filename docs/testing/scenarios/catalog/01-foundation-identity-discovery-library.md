# BDD Catalog 01 - Foundation, Identity, Discovery, Library

## Foundation And First Run

| ID | Scenario | Evidence |
|---|---|---|
| FND-001 | Given a fresh install with no app group data, when Pod0 launches, then onboarding page 1 appears and no main-tab state is reachable behind it. | SS: launch page and UI tree; Perf: cold launch metric; Deps: erased sim; Boundary: D1,D5. |
| FND-002 | Given a fresh install, when the user advances through every onboarding page with primary buttons, then page order, progress indicators, and final app entry are stable. | SS: every page; Perf: page transition under 250 ms; Deps: erased sim; Boundary: D1. |
| FND-003 | Given AI setup is skipped, when onboarding completes, then provider settings remain disconnected without blocking library or playback. | SS: AI page and Settings AI; Perf: none; Deps: erased sim; Boundary: D6. |
| FND-004 | Given the user enters an agent name during onboarding, when onboarding completes, then Settings identity shows the same display name from kernel state. | SS: input page and identity screen; Perf: none; Deps: erased sim; Boundary: D4,D5. |
| FND-005 | Given onboarding subscription suggestions are visible, when the user subscribes to a starter show, then the show appears in Library without manual refresh. | SS: suggestion row, subscribe state, Library; Perf: subscribe UI under 1 sec; Deps: starter feed cassette; Boundary: D4,D5,D8. |
| FND-006 | Given an invalid RSS URL is entered during onboarding, when the user submits it, then an inline recoverable error appears and onboarding can continue. | SS: invalid state and recovery; Perf: none; Deps: RSS error cassette; Boundary: D6,D7. |
| FND-007 | Given onboarding is completed, when the app is force quit and relaunched, then onboarding does not reappear. | SS: relaunch home; Perf: cold launch metric; Deps: preserved app data; Boundary: D4. |
| FND-008 | Given onboarding was partially completed, when the app is relaunched, then it restores the correct step or restarts safely without duplicate identity creation. | SS: restored step and identity count; Perf: none; Deps: interrupted sim state; Boundary: D4,D9. |
| FND-009 | Given a seeded library launch, when `--UITestSeed` runs, then the Home, Library, Bookmarks, and Clippings tabs render deterministic fixtures. | SS: each tab; Perf: first snapshot under 1 sec; Deps: UITestSeed; Boundary: D4,D5. |
| FND-010 | Given a preserved seeded launch, when `--UITestSeedRelaunch` runs, then playback and library persistence survive without reseeding destructive data. | SS: before and after relaunch; Perf: none; Deps: UITestSeed plus relaunch; Boundary: D4. |
| FND-011 | Given a large seeded library, when Home opens, then only screen-shaped projections cross FFI and scroll remains responsive. | SS: Home top and scroll end; Perf: frame hitch and snapshot bytes; Deps: large library seed; Boundary: D5,D8. |
| FND-012 | Given no subscriptions exist, when Home opens, then the empty state offers add/import actions without agent chatter. | SS: Home empty state; Perf: none; Deps: empty seed; Boundary: D1. |
| FND-013 | Given the app receives a deep link to an episode while cold, when the app launches, then it routes to the episode after kernel readiness. | SS: link open and final screen; Perf: route under 2 sec after first snapshot; Deps: deep-link fixture; Boundary: D4,D7. |
| FND-014 | Given network is offline on first launch, when onboarding tries provider or feed setup, then offline state is explicit and no spinner loops. | SS: offline banners; Perf: no repeated wake loop; Deps: network capability mock; Boundary: D6,D8. |
| FND-015 | Given Dynamic Type is set to accessibility size, when onboarding and main shell render, then text remains readable and controls do not overlap. | SS: key pages at AX size; Perf: none; Deps: simulator text size; Boundary: native render. |
| FND-016 | Given reduce motion and reduce transparency are enabled, when onboarding and Home render, then transitions simplify and controls remain discoverable. | SS: motion-disabled screens; Perf: none; Deps: simulator accessibility prefs; Boundary: native render. |

## Identity And Accounts

| ID | Scenario | Evidence |
|---|---|---|
| ID-001 | Given no account exists, when onboarding completes, then a local Nostr identity is generated and the npub is non-empty. | SS: account screen; Perf: none; Deps: erased keychain; Boundary: D4,D7,D10. |
| ID-002 | Given a valid nsec is pasted, when import succeeds, then the account becomes active and no secret is displayed in normal snapshots. | SS: import success and account screen; Perf: none; Deps: test nsec; Boundary: D5,D7,D10. |
| ID-003 | Given an invalid nsec is pasted, when import is submitted, then the error is stateful and the app does not crash. | SS: validation error; Perf: none; Deps: invalid key fixture; Boundary: D6. |
| ID-004 | Given an account has a display name and avatar URL, when Edit Profile saves, then profile fields survive relaunch and are projected from Rust-owned state. | SS: edit form, profile row after relaunch; Perf: none; Deps: profile fixture; Boundary: D4,D5. |
| ID-005 | Given avatar URL fetch fails, when profile renders, then initials fallback is shown without blocking account details. | SS: fallback avatar; Perf: none; Deps: avatar HTTP failure cassette; Boundary: D6,D7. |
| ID-006 | Given Account Details is open, when the user copies npub and hex, then clipboard actions succeed without exposing nsec. | SS: copy controls and redacted details; Perf: none; Deps: local identity; Boundary: D10. |
| ID-007 | Given a valid bunker URI, when remote signer connect starts, then pairing state is visible and signing remains pending until callback/projection confirms. | SS: connect state; Perf: handshake timing; Deps: NIP-46 fixture relay cassette; Boundary: D4,D7,D10. |
| ID-008 | Given NIP-46 pairing times out, when the timeout fires, then busy state clears and retry is available. | SS: timeout state; Perf: injected clock timeout; Deps: replay clock and signer cassette; Boundary: D6,D9. |
| ID-009 | Given a signer callback arrives for another account, when the app handles it, then it rejects or isolates the callback without switching active account. | SS: rejection state; Perf: none; Deps: callback fixture; Boundary: D4,D10. |
| ID-010 | Given multiple accounts exist, when active account changes, then identity, relays, and social surfaces update from a single projected active account. | SS: account switch and affected screens; Perf: projection update under 500 ms; Deps: multi-account fixture; Boundary: D4,D5. |
| ID-011 | Given the user removes an inactive account, when removal completes, then active account and key material remain unchanged. | SS: account roster before/after; Perf: none; Deps: multi-account fixture; Boundary: D4,D10. |
| ID-012 | Given the user removes the active account, when confirmed, then the app transitions to a no-active-account state without stale profile data. | SS: confirmation and empty account state; Perf: none; Deps: multi-account fixture; Boundary: D4,D5,D10. |
| ID-013 | Given profile metadata is fetched from relay, when kind:0 arrives, then display values hydrate without native relay policy. | SS: before/after profile; Perf: relay to projection timing; Deps: fixture relay kind:0; Boundary: D3,D4,D7. |
| ID-014 | Given relay metadata is malformed, when profile hydration runs, then the profile degrades to stable fallback labels. | SS: fallback label; Perf: none; Deps: malformed relay cassette; Boundary: D6. |
| ID-015 | Given a private key import succeeds, when diagnostics/export runs, then no secret appears in exported logs or state files. | SS: export screen; Perf: none; Deps: export fixture scan; Boundary: D10. |
| ID-016 | Given app group data has an older identity shape, when migration loads it, then account fields map to the current projection without duplicate accounts. | SS: migrated account; Perf: migration time; Deps: legacy fixture; Boundary: D4,D5. |

## Discovery And Search

| ID | Scenario | Evidence |
|---|---|---|
| DISC-001 | Given network is available, when the user searches "This American Life", then keyword results show podcast rows with title, author, artwork, and feed URL. | SS: results list; Perf: first result under 3 sec; Deps: iTunes search cassette; Boundary: D7. |
| DISC-002 | Given a raw RSS URL is pasted, when submitted, then URL intent is detected and feed parsing is used instead of keyword search. | SS: URL result; Perf: feed parse under 5 sec; Deps: RSS cassette; Boundary: D7. |
| DISC-003 | Given a malformed RSS URL is pasted, when submitted, then input error appears and no network retry loop starts. | SS: error row; Perf: no repeated requests; Deps: malformed URL; Boundary: D6,D8. |
| DISC-004 | Given a valid RSS feed has relative artwork and audio URLs, when parsed, then rows render resolved absolute media URLs. | SS: show and episode rows; Perf: none; Deps: RSS relative URL cassette; Boundary: D4. |
| DISC-005 | Given a feed omits GUIDs, when episodes import, then stable synthesized GUIDs persist across refresh. | SS: episode IDs via debug/export; Perf: none; Deps: RSS missing GUID cassette; Boundary: D4. |
| DISC-006 | Given a search result is already subscribed, when opened, then the subscribe control shows subscribed state immediately. | SS: result and detail state; Perf: no extra refresh; Deps: subscribed seed; Boundary: D4,D5. |
| DISC-007 | Given Discover popular is opened, when rows load, then each recommendation has provenance or a deterministic fallback reason. | SS: popular rail; Perf: render under 1 sec after data; Deps: recommendation seed; Boundary: D4,D6. |
| DISC-008 | Given a Nostr naddr is pasted, when search resolves it, then a NIP-F4 show detail opens through the NMP open-search path. | SS: Nostr result; Perf: relay resolve timing; Deps: fixture relay naddr; Boundary: D3,D7,D10. |
| DISC-009 | Given a Nostr nevent for an episode is pasted, when search resolves it, then episode detail opens without app-side relay selection. | SS: episode detail; Perf: relay resolve timing; Deps: fixture relay nevent; Boundary: D3,D5,D7. |
| DISC-010 | Given the search query has transcript terms, when local results exist, then transcript snippets appear before online escalation. | SS: snippets; Perf: local search under 500 ms; Deps: transcript seed; Boundary: D5,D8. |
| DISC-011 | Given no local results exist, when the user chooses open web search, then Perplexity/OpenRouter search uses a cassette in replay mode. | SS: escalation card and result; Perf: provider latency; Deps: `cassettes/search/perplexity-no-local.json`; Boundary: D7. |
| DISC-012 | Given provider credentials are missing, when open-web search is requested, then Rust-owned missing-credential state is shown. | SS: credential error; Perf: none; Deps: no provider keys; Boundary: D6,D7. |
| DISC-013 | Given offline mode, when keyword discovery runs, then cached/local results show and online sections explain they are unavailable. | SS: offline results; Perf: local result under 500 ms; Deps: network mock offline; Boundary: D6,D7. |
| DISC-014 | Given search returns duplicate feeds from multiple directories, when results render, then duplicates are collapsed by canonical feed URL. | SS: deduped list; Perf: none; Deps: multi-directory cassette; Boundary: D4. |
| DISC-015 | Given a show result is long-pressed, when preview opens, then no subscription state mutates until the user confirms. | SS: preview and library unchanged; Perf: none; Deps: search fixture; Boundary: D4. |
| DISC-016 | Given search text includes leading/trailing whitespace and mixed case, when submitted, then normalized intent preserves user-visible query but routes correctly. | SS: query field and results; Perf: none; Deps: search cassette; Boundary: D7. |

## Library And Episode Management

| ID | Scenario | Evidence |
|---|---|---|
| LIB-001 | Given one subscribed show, when Library opens, then the show appears with artwork, title, author, and episode count. | SS: Library row/grid; Perf: render under 1 sec; Deps: UITestSeed; Boundary: D5. |
| LIB-002 | Given multiple subscriptions, when the user toggles grid/list, then the same Rust-owned show set renders without changing sort or filters. | SS: grid and list; Perf: no layout hitch; Deps: multi-show seed; Boundary: D4. |
| LIB-003 | Given unplayed filter is selected, when Library updates, then only shows or episodes with unplayed content remain visible. | SS: filter chip and results; Perf: filter under 300 ms; Deps: mixed played seed; Boundary: D4. |
| LIB-004 | Given downloaded filter is selected, when Library updates, then only downloaded content remains visible and offline playback affordances remain. | SS: downloaded filter; Perf: filter under 300 ms; Deps: downloaded seed; Boundary: D4,D5. |
| LIB-005 | Given a show detail opens, when episodes load, then episode sort order is newest-first unless the user changes it. | SS: show detail top; Perf: list render under 1 sec; Deps: show seed; Boundary: D4. |
| LIB-006 | Given an episode row is swiped, when mark played is tapped, then played state changes in the kernel and projections update once. | SS: row before/after; Perf: one projection bump; Deps: UITestSeed; Boundary: D4,D5,D8. |
| LIB-007 | Given an episode is marked played, when the user marks it unplayed, then progress and played threshold derive from the kernel state. | SS: row state; Perf: none; Deps: played seed; Boundary: D4. |
| LIB-008 | Given a show is unsubscribed with "keep history", when Library refreshes, then show is removed but episode history remains searchable. | SS: Library and search result; Perf: projection update under 1 sec; Deps: subscribed seed; Boundary: D4,D5. |
| LIB-009 | Given a show feed refresh finds new episodes, when refresh completes, then new rows appear without clobbering existing progress. | SS: before/after episode list; Perf: refresh timing; Deps: RSS refresh cassette; Boundary: D4,D5. |
| LIB-010 | Given a feed refresh returns 404, when refresh completes, then the show remains listenable and feed-gone state is visible. | SS: show warning; Perf: none; Deps: RSS 404 cassette; Boundary: D6,D7. |
| LIB-011 | Given OPML import has valid and invalid outlines, when imported, then valid feeds import and invalid line errors are listed. | SS: OPML preview and result; Perf: import timing; Deps: OPML mixed fixture; Boundary: D6,D7. |
| LIB-012 | Given OPML export runs, when the share sheet appears, then exported XML includes current subscriptions and no private secrets. | SS: export share preview; Perf: export time; Deps: subscribed seed; Boundary: D4,D10. |
| LIB-013 | Given a category chip is selected on Home, when Library opens, then the same category scoping is not silently applied unless projected as active filter. | SS: Home chip and Library filters; Perf: none; Deps: category seed; Boundary: D4. |
| LIB-014 | Given a user-defined podcast category is edited, when saved, then category membership survives relaunch and Android/TUI projections can decode it. | SS: category screen; Perf: none; Deps: category fixture; Boundary: D4,D5. |
| LIB-015 | Given a very long show description includes HTML, when show detail renders, then sanitized text and links render without script execution. | SS: show notes; Perf: layout under 1 sec; Deps: HTML RSS cassette; Boundary: D7. |
| LIB-016 | Given a library snapshot decode failure occurs for one domain sidecar, when the app receives the frame, then prior good data remains and resync state is visible. | SS: stale data plus resync indicator; Perf: no main-thread crash; Deps: malformed projection replay; Boundary: D5,D6,D8. |

