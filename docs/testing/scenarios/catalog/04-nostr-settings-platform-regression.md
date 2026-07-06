# BDD Catalog 04 - Nostr, Settings, Platform, Regression

## Nostr Publishing And Protocol

| ID | Scenario | Evidence |
|---|---|---|
| NOSTR-001 | Given local identity exists, when a podcast is published as NIP-F4, then kind:10154 event is signed and accepted by relay. | SS: publish state; Perf: relay ack timing; Deps: fixture relay signed-event replay; Boundary: D3,D7,D10. |
| NOSTR-002 | Given a podcast author claim is published, when inspected, then kind:10064 links author identity and podcast correctly. | SS: claim state; Perf: none; Deps: fixture relay plus nak; Boundary: D3,D7,D10. |
| NOSTR-003 | Given NIP-F4 episode kind:54 is published, when relay replay fetches it, then tags match expected podcast and enclosure metadata. | SS: published episode; Perf: relay query timing; Deps: fixture relay kind:54 replay; Boundary: D3,D7. |
| NOSTR-004 | Given publishing requires signing and active account has no signer, when publish is tapped, then signing-required state appears. | SS: blocked publish; Perf: none; Deps: no-signer fixture; Boundary: D6,D7,D10. |
| NOSTR-005 | Given remote signer approves a publish, when callback returns, then event signs and publishes without exposing secret material. | SS: approval and published state; Perf: signing latency; Deps: NIP-46 signer cassette; Boundary: D7,D10. |
| NOSTR-006 | Given remote signer rejects a publish, when callback returns, then publish remains failed and retry is available. | SS: rejected state; Perf: none; Deps: NIP-46 reject cassette; Boundary: D6,D7. |
| NOSTR-007 | Given relay publish queue has pending items, when app restarts, then queue state persists and resumes according to Rust policy. | SS: queue before/after relaunch; Perf: resume timing; Deps: relay queue fixture; Boundary: D4,D7. |
| NOSTR-008 | Given a relay ACK is delayed, when publish remains pending, then UI shows pending state without native retry policy. | SS: pending state; Perf: injected delay; Deps: delayed ACK fixture; Boundary: D7,D9. |
| NOSTR-009 | Given an naddr is generated for an owned podcast, when copied and resolved, then it opens the same show on a clean install. | SS: copied naddr and clean resolve; Perf: resolve timing; Deps: fixture relay; Boundary: D3,D4. |
| NOSTR-010 | Given a malformed naddr is pasted, when resolver runs, then error state is explicit and no relay request is made. | SS: malformed error; Perf: none; Deps: malformed input fixture; Boundary: D6,D7. |
| NOSTR-011 | Given relay routing is automatic, when publishing a note/share, then app-facing UI never asks for manual relay URL. | SS: share flow; Perf: none; Deps: relay config fixture; Boundary: D3,D7. |
| NOSTR-012 | Given user adds a relay in settings, when saved, then configured relays projection updates and routing remains Rust-owned. | SS: relay settings; Perf: update under 500 ms; Deps: settings fixture; Boundary: D3,D4,D7. |
| NOSTR-013 | Given relay diagnostics opens, when relay state is unavailable, then diagnostics show raw connectivity facts only. | SS: diagnostics; Perf: none; Deps: relay mock; Boundary: D7. |
| NOSTR-014 | Given private event inbox is unknown, when a private share is attempted, then send fails closed. | SS: blocked private send; Perf: none; Deps: unknown inbox fixture; Boundary: D10. |
| NOSTR-015 | Given a private inbound event is received, when app processes it, then content never republishes to public relays. | SS: conversation state and relay log; Perf: none; Deps: private event fixture; Boundary: D10. |
| NOSTR-016 | Given a signed event is malformed by tampering, when relay replay returns it, then kernel rejects it and UI degrades safely. | SS: rejection state; Perf: none; Deps: tampered event fixture; Boundary: D6,D7,D10. |

## Social, Friends, Feedback

| ID | Scenario | Evidence |
|---|---|---|
| SOC-001 | Given a valid npub is entered in Add Friend, when submitted, then friend appears after NMP resolves profile data. | SS: add friend and friend row; Perf: relay resolve timing; Deps: fixture relay profile; Boundary: D3,D4,D7. |
| SOC-002 | Given an invalid npub is entered, when submitted, then validation error appears without network requests. | SS: validation error; Perf: none; Deps: invalid npub fixture; Boundary: D6,D7. |
| SOC-003 | Given a contact list exists, when Following opens, then followed users render from kind:3 projection. | SS: following list; Perf: render under 1 sec; Deps: kind:3 fixture relay; Boundary: D4,D5. |
| SOC-004 | Given user follows another pubkey, when relay accepts kind:3 edit, then UI reflects follow state and raw event verifies. | SS: follow toggle and relay event; Perf: ack timing; Deps: fixture relay signed event; Boundary: D3,D7,D10. |
| SOC-005 | Given user unfollows a pubkey, when relay accepts update, then contact list projection removes only that user. | SS: list before/after; Perf: projection timing; Deps: fixture relay; Boundary: D4,D7. |
| SOC-006 | Given friend activity includes a played episode, when friend detail opens, then activity row links to episode if resolvable. | SS: friend detail; Perf: none; Deps: social activity fixture; Boundary: D5. |
| SOC-007 | Given friend activity references unknown episode, when detail opens, then raw reference is represented without crash. | SS: unknown activity; Perf: none; Deps: unknown episode fixture; Boundary: D6. |
| SOC-008 | Given a feedback thread is opened, when the user posts a comment, then comment target includes episode identity and author. | SS: comment thread; Perf: post timing; Deps: feedback relay fixture; Boundary: D4,D7. |
| SOC-009 | Given a feedback comment fails to publish, when ACK rejects, then the composer preserves draft and shows retry. | SS: failed comment; Perf: none; Deps: relay reject cassette; Boundary: D6,D7. |
| SOC-010 | Given screenshot annotation is opened from feedback, when the user draws and sends, then image attachment is bounded and redaction warning is visible. | SS: annotation and send preview; Perf: image encode time; Deps: screenshot fixture; Boundary: D7,D10. |
| SOC-011 | Given a friend sends an agent prompt, when trust is not approved, then the app shows approval controls before tool execution. | SS: approval row; Perf: none; Deps: NIP-17 prompt fixture; Boundary: D7,D10. |
| SOC-012 | Given friend is blocked, when their prompt arrives, then it is hidden or marked blocked and no tools run. | SS: blocked state; Perf: none; Deps: blocked prompt fixture; Boundary: D4,D10. |
| SOC-013 | Given an approved friend asks for a harmless summary, when agent responds, then outbound reply is signed and sent through Rust policy. | SS: conversation and relay log; Perf: LLM plus publish timing; Deps: LLM and relay cassettes; Boundary: D7,D10. |
| SOC-014 | Given a peer prompt asks for private data, when evaluated, then policy denies and reply does not include secrets. | SS: denial reply; Perf: none; Deps: policy replay; Boundary: D10. |
| SOC-015 | Given conversation projection contains inbound and outbound turns, when Android and iOS decode it, then trust and direction fields match. | SS: iOS and Android screens or decode logs; Perf: decode time; Deps: domain frame fixture; Boundary: D4,D5. |
| SOC-016 | Given social migration has legacy native-store records, when app starts, then migration writes one canonical Rust-owned representation. | SS: migration result; Perf: migration timing; Deps: legacy store fixture; Boundary: D4. |

## Settings And Storage

| ID | Scenario | Evidence |
|---|---|---|
| SET-001 | Given playback settings are opened, when skip intervals change, then player uses new values and settings persist. | SS: settings and player skip; Perf: none; Deps: settings seed; Boundary: D4. |
| SET-002 | Given auto-download defaults change, when a new episode arrives, then policy applies from Rust settings. | SS: setting and download state; Perf: policy timing; Deps: feed refresh cassette; Boundary: D4,D7. |
| SET-003 | Given notification permission is undetermined, when notifications are enabled, then native prompt appears and result reports raw capability status. | SS: permission prompt and setting; Perf: none; Deps: simulator permission reset; Boundary: D7. |
| SET-004 | Given notification permission is denied, when per-show toggle is enabled, then UI shows denied state without pretending alerts are active. | SS: denied state; Perf: none; Deps: simulator denied permission; Boundary: D6,D7. |
| SET-005 | Given storage screen opens, when downloads exist, then storage breakdown shows audio, transcripts, cache, and total values. | SS: storage breakdown; Perf: calculation latency; Deps: storage seed; Boundary: D5. |
| SET-006 | Given Clear All Data is confirmed, when app resets, then user data is removed and app returns to onboarding safely. | SS: confirmation and onboarding; Perf: reset time; Deps: seeded app; Boundary: D4,D10. |
| SET-007 | Given Data Export is tapped, when export completes, then OPML, JSON, and diagnostics are included without secrets. | SS: export file preview or lint log; Perf: export time; Deps: seeded app; Boundary: D10. |
| SET-008 | Given Whats New has unseen entries, when app launches, then only entries newer than last seen display. | SS: sheet; Perf: none; Deps: changelog fixture and marker; Boundary: D4,D9. |
| SET-009 | Given provider settings are cleared, when agent run starts, then missing credential state appears and no stale key is used. | SS: cleared setting and error; Perf: none; Deps: credential store fixture; Boundary: D4,D7,D10. |
| SET-010 | Given model catalog contains provider-native and selection IDs, when user selects a model, then stored ID survives projection round trip. | SS: selector after relaunch; Perf: none; Deps: catalog cassette; Boundary: D4,D7. |
| SET-011 | Given relay settings add/remove actions run, when app relaunches, then configured relay projection matches prior edits. | SS: relay list after relaunch; Perf: none; Deps: relay settings fixture; Boundary: D3,D4. |
| SET-012 | Given category recompute runs, when LLM suggests categories, then results are replayed and user edits override generated labels. | SS: recompute sheet; Perf: LLM latency; Deps: `cassettes/llm/category-recompute.json`; Boundary: D4,D7. |
| SET-013 | Given debug logs are opened, when provider errors exist, then logs redact secrets and show correlation IDs. | SS: logs; Perf: none; Deps: error log fixture; Boundary: D10. |
| SET-014 | Given Performance screen opens during playback, when metrics update, then update cadence does not exceed 60 Hz and UI stays responsive. | SS: performance screen; Perf: frame and update cadence; Deps: seeded player; Boundary: D8. |
| SET-015 | Given subscriptions settings opens, when per-show notification toggle changes, then setting applies to that show only. | SS: subscriptions settings; Perf: none; Deps: multi-show seed; Boundary: D4. |
| SET-016 | Given app typography is inspected, when key screens render, then no serif fonts are used anywhere in Pod0 UI. | SS: representative screens and font audit output; Perf: none; Deps: UI tree/font audit; Boundary: native render. |

## Platform, Parity, Performance, Regression

| ID | Scenario | Evidence |
|---|---|---|
| XPLAT-001 | Given iOS and Android decode the same library domain frame, when rendered, then title, episode count, and subscription state match. | SS: iOS/Android or decode logs; Perf: decode time; Deps: domain frame fixture; Boundary: D4,D5. |
| XPLAT-002 | Given Android subscribes by RSS URL, when feed parses, then shared Rust action path matches iOS behavior. | SS: Android screens; Perf: subscribe timing; Deps: RSS cassette; Boundary: D4,D7. |
| XPLAT-003 | Given Android opens episode detail, when playback action is tapped, then media service reports raw audio events to Rust. | SS: Android player; Perf: start latency; Deps: Android audio fixture; Boundary: D7. |
| XPLAT-004 | Given Android provider settings are changed, when app relaunches, then shared settings projection matches iOS field semantics. | SS: Android settings; Perf: none; Deps: settings fixture; Boundary: D4,D5. |
| XPLAT-005 | Given TUI lists subscriptions, when kernel projection updates, then TUI renders changed list without app-side business policy. | SS: terminal snapshot/log; Perf: update latency; Deps: TUI fixture; Boundary: D4,D5. |
| XPLAT-006 | Given TUI creates a typed scheduled task, when run_due fires, then task intent fields match iOS and Android. | SS: TUI output and decode logs; Perf: none; Deps: task intent fixture; Boundary: D7,D9. |
| XPLAT-007 | Given malformed typed projection bytes arrive, when ProjectionCache decodes, then prior good cache remains and needs-resync latches. | SS: decode log and UI state; Perf: no crash; Deps: malformed sidecar replay; Boundary: D5,D6. |
| XPLAT-008 | Given full library snapshot has 1000 shows, when decoded on iOS, then decode and commit stay off main hot path. | SS: perf test output; Perf: decode wall time and frame hitch; Deps: large snapshot fixture; Boundary: D5,D8. |
| XPLAT-009 | Given one download progress changes, when snapshot transport emits update, then amplification stays bounded to download domain. | SS: perf log; Perf: payload bytes and update rate; Deps: transport perf fixture; Boundary: D5,D8. |
| XPLAT-010 | Given Rust actor receives rapid playback reports, when projecting player state, then update cadence is coalesced and no queue grows unbounded. | SS: metrics log; Perf: update rate <= 60 Hz; Deps: audio report replay; Boundary: D8. |
| XPLAT-011 | Given kernel time is injected in tests, when date buckets, retry-after, and sleep timer run, then outputs are deterministic. | SS: test logs; Perf: none; Deps: frozen clock fixture; Boundary: D9. |
| XPLAT-012 | Given native capability returns raw HTTP failure, when Rust handles it, then user-visible retry policy comes from state. | SS: error state; Perf: none; Deps: HTTP capability replay; Boundary: D6,D7. |
| XPLAT-013 | Given an FFI dispatch is sent, when operation later fails, then dispatch remains fire-and-forget and success/failure arrives via update state. | SS: action and later state; Perf: no blocking dispatch; Deps: failure replay; Boundary: RMP,D6,D8. |
| XPLAT-014 | Given native renders an OS share sheet, when share completes or cancels, then Rust receives raw completion result only if needed. | SS: share sheet; Perf: none; Deps: share capability mock; Boundary: D7. |
| XPLAT-015 | Given concurrent agents have docs-only worktrees, when this catalog branch changes files, then no app code or WIP entries are staged. | SS: git diff summary; Perf: none; Deps: git status; Boundary: process. |
| XPLAT-016 | Given the architecture scanner reports existing app findings, when scenario coverage is reviewed, then D4/D5/D6/D7/D8/D9/D10 risks map to catalog rows. | SS: scanner summary and catalog links; Perf: none; Deps: scanner output; Boundary: all doctrine. |
