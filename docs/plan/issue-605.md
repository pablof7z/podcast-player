# Issue 605 — Adopt NMP Input-Intent And Open Search

**Target:** v0.8.0+

**Priority:** High

**Status:** Partially implemented after #597. The NMP intent ABI is available and iOS Add Show now uses it for Nostr profile/address input. Relay-targeted NIP-50 UI and remaining platform surfaces are still pending.

## Goal

Route Nostr-facing text-entry/discovery surfaces through NMP's framework-level input-intent classifier and open_search path. Keep RSS, iTunes, local library, transcript, and knowledge search in podcast-owned modules.

## Completed In Current Pass

- Added Swift wire DTOs for `InputIntentRequest`, classification results, dispatch outcomes, and decoded NIP-21 refs.
- Exposed the NMP C ABI in `NmpCore.h`:
  - `nmp_app_intent_classify`
  - `nmp_app_intent_dispatch`
  - `nmp_nip21_decode_uri`
- Added `PodcastHandle`, `KernelModel`, and `AppStateStore` wrappers for the intent ABI.
- Updated Add Show > From URL to classify Nostr inputs through NMP before falling back to RSS:
  - `nsec` is rejected from the Rust classification result without echoing the key.
  - `npub`/`nprofile` profile refs subscribe through `subscribe_nostr`.
  - Nostr address refs subscribe by author pubkey.
  - NIP-05 inputs dispatch NMP resolution and show a pending notice.
  - event refs remain recognized but not subscribable from Add Show.
- Removed the Swift prefix detectors `looksLikeNsecKey` and `looksLikeNostrInput`.
- Updated the legacy `podcast.open_search` comments to make clear it is compatibility-only unless reworked around the NMP ABI.

## Remaining Work

1. **Async NIP-05 completion.** Add a projected result/await path so Add Show can turn NIP-05 resolution into a completed Nostr subscription instead of a pending notice.
2. **NostrDiscoverForm NIP-50 search.** Submit query text through `nmp_app_intent_dispatch`, observe the NMP search session projection, and render relay-targeted NIP-50 results separately from NIP-F4 discovery rows.
3. **AddFriendSheet.** Replace its remaining npub/hex-only helper flow with NMP direct-ref classification/decode, then decide whether NIP-05 friend add waits for async resolution or remains a follow-up.
4. **TUI.** Route `handle_subscribe_input` Nostr identifiers through NMP intent APIs while keeping RSS subscribe as the fallback.
5. **Android.** No Nostr subscribe text-entry surface exists today. When one is added, use the NMP intent ABI instead of local prefix checks.
6. **Legacy Rust action.** Either remove the `podcast.open_search` compatibility action or rebuild it around NMP's public Rust-side APIs if those are exported for app crates.

## Validation Targets

```bash
git diff --check
./ci/check-file-sizes.sh
./ci/check-ffi-header-drift.sh
cargo check -p nmp-app-podcast
cargo build --target aarch64-apple-ios-sim -p nmp-app-podcast
xcodebuild test -workspace Podcastr.xcworkspace -scheme Podcastr \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation \
  -only-testing:PodcastrTests/NostrIntentWireTests \
  -only-testing:PodcastrTests/KernelBridgeWireTests
JAVA_HOME=/opt/homebrew/opt/openjdk@17 \
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
ANDROID_NDK_HOME=/opt/homebrew/share/android-commandlinetools/ndk/26.3.11579264 \
./gradlew :app:compileDebugKotlin --no-daemon --stacktrace
```
