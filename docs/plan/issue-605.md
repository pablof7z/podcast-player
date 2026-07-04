# Issue 605 — Adopt NMP Input-Intent And Open Search

**Target:** v0.8.0+

**Priority:** High

**Status:** Implemented for current shipped surfaces after #597. The NMP intent ABI is available, iOS Add Show and Add Friend use it for Nostr profile/address and NIP-05 inputs, and the Nostr discovery tab now renders relay-targeted NIP-50 search results. Android has no Nostr subscribe text-entry surface today; any future one should use the same NMP intent ABI.

## Goal

Route Nostr-facing text-entry/discovery surfaces through NMP's framework-level input-intent classifier and open_search path. Keep RSS, iTunes, local library, transcript, and knowledge search in podcast-owned modules.

## Completed In Current Pass

- Added Swift wire DTOs for `InputIntentRequest`, classification results, dispatch outcomes, and decoded NIP-21 refs.
- Exposed the NMP input-intent operations through the app bridge:
  - `nmp_app_intent_classify`
  - `nmp_app_intent_dispatch`
  - `nmp_nip21_decode_uri`
- Added `PodcastHandle`, `KernelModel`, and `AppStateStore` wrappers for the intent ABI.
- Updated Add Show > From URL to classify Nostr inputs through NMP before falling back to RSS:
  - `nsec` is rejected from the Rust classification result without echoing the key.
  - `npub`/`nprofile` profile refs subscribe through `subscribe_nostr`.
  - Nostr address refs subscribe by author pubkey.
  - NIP-05 inputs dispatch NMP resolution, await the kernel's `resolved_profiles`
    projection, and subscribe to the resolved author on success.
  - event refs remain recognized but not subscribable from Add Show.
- Removed the Swift prefix detectors `looksLikeNsecKey` and `looksLikeNostrInput`.
- Retired the legacy `podcast.open_search` compatibility action so native text-entry surfaces have one NMP-owned Nostr routing path.
- Updated Add Friend to classify/decode npub, nprofile, and nostr profile links
  through the NMP intent ABI before approving a peer; raw 64-hex pubkeys remain
  a compatibility fallback.
- Updated the TUI subscribe prompt to classify Nostr identifiers through NMP:
  profile/address refs dispatch `subscribe_nostr`, NIP-05 starts the NMP
  dispatch path and reports pending lookup, and ordinary feed URLs still use
  the RSS subscribe fallback.
- Updated the iOS Nostr discovery tab to dispatch query searches through
  `nmp_app_intent_dispatch`, decode NMP NIP-50 search-session projections, and
  render relay search hits separately from NIP-F4 discovery rows.
- Updated Add Show > From URL so NIP-05 addresses complete the subscribe flow
  after the NMP async profile projection lands, with a bounded 5-second timeout.
- Updated Add Friend so NIP-05 addresses dispatch through NMP and complete
  the friend-add flow after the async profile projection lands.

## Remaining Work

1. **Android.** No Nostr subscribe text-entry surface exists today. When one is added, use the NMP intent ABI instead of local prefix checks.

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
