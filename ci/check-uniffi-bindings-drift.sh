#!/usr/bin/env bash
# check-uniffi-bindings-drift.sh — Verify the checked-in `PodcastApp` UniFFI
# Swift bindings match a fresh uniffi-bindgen run.
#
# Usage:
#   bash ci/check-uniffi-bindings-drift.sh          # CI: fail on any diff
#   bash ci/check-uniffi-bindings-drift.sh --regen  # regenerate + commit-ready
#
# This is the canonical regeneration procedure for the wave-1 UniFFI facade
# (podcast-player#681 follow-on, apps/nmp-app-podcast/src/ffi/uniffi_facade.rs):
#   App/Sources/Bridge/Generated/PodcastApp.uniffi.swift
#   App/Sources/Bridge/Generated/PodcastAppFFI/{nmp_app_podcastFFI.h,module.modulemap}
# Regenerate whenever `PodcastApp`'s interface changes (new/renamed methods,
# types, or fields). Mirrors NMP's own `ci/check-uniffi-bindings-drift.sh`
# (crates/nmp-uniffi), adapted to this app's own facade crate — podcast-player
# builds its own UniFFI object directly on nmp-native-runtime +
# nmp-uniffi-support, per the validated nmp-app-gallery/nmp-app-29er precedent.
#
# Kotlin generation is intentionally out of scope until the Android consumer
# wave lands (no `android/.../uniffi/` package exists yet to drift-check
# against) — adding an unconsumed generated Kotlin file now would be dead
# code. Add it back in that wave, mirroring this script's Swift half.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGEN=false

for arg in "$@"; do
    case "$arg" in
        --regen) REGEN=true ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

# ── Step 1: build the cdylib ─────────────────────────────────────────────────
echo "Building nmp-app-podcast cdylib..."
cargo build -p nmp-app-podcast --lib 2>&1

DYLIB="${REPO_ROOT}/target/debug/libnmp_app_podcast.dylib"
if [[ ! -f "$DYLIB" ]]; then
    # macOS uses .dylib; Linux uses .so
    DYLIB="${REPO_ROOT}/target/debug/libnmp_app_podcast.so"
fi
if [[ ! -f "$DYLIB" ]]; then
    echo "ERROR: could not find libnmp_app_podcast.dylib or .so" >&2
    exit 1
fi

# ── Step 2: run uniffi-bindgen into a temp dir ───────────────────────────────
TMPDIR_SWIFT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_SWIFT"' EXIT

echo "Generating Swift bindings..."
cargo run -p nmp-app-podcast --features bindgen --bin uniffi-bindgen \
    -- generate --library "$DYLIB" --language swift --out-dir "$TMPDIR_SWIFT"

# UniFFI's Swift generator currently emits trailing spaces in several type
# declarations. Normalize generated text here so the drift gate and
# `git diff --check` agree (same normalization as NMP's own drift script).
find "$TMPDIR_SWIFT" -type f -print0 \
    | xargs -0 perl -0pi -e 's/[ \t]+$//mg; s/\n+\z/\n/'

# ── Step 3: diff against checked-in bindings ─────────────────────────────────
GENERATED_SWIFT="${REPO_ROOT}/App/Sources/Bridge/Generated"
GENERATED_SWIFT_FFI="${REPO_ROOT}/App/Sources/Bridge/Generated/PodcastAppFFI"

if [[ "$REGEN" == "true" ]]; then
    echo "Regenerating checked-in bindings..."
    cp "$TMPDIR_SWIFT/nmp_app_podcast.swift" "$GENERATED_SWIFT/PodcastApp.uniffi.swift"
    mkdir -p "$GENERATED_SWIFT_FFI"
    cp "$TMPDIR_SWIFT/nmp_app_podcastFFI.h" "$GENERATED_SWIFT_FFI/nmp_app_podcastFFI.h"
    cp "$TMPDIR_SWIFT/nmp_app_podcastFFI.modulemap" "$GENERATED_SWIFT_FFI/module.modulemap"
    echo "Done. Stage and commit the updated files to update the drift baseline."
    exit 0
fi

echo "Diffing against checked-in bindings..."
DIFF_OUT=$(diff -u "$GENERATED_SWIFT/PodcastApp.uniffi.swift" "$TMPDIR_SWIFT/nmp_app_podcast.swift" 2>&1 || true)
DIFF_OUT+=$(diff -u "$GENERATED_SWIFT_FFI/nmp_app_podcastFFI.h" "$TMPDIR_SWIFT/nmp_app_podcastFFI.h" 2>&1 || true)

if [[ -n "$DIFF_OUT" ]]; then
    echo ""
    echo "ERROR: PodcastApp UniFFI bindings are out of date. Regenerate with:"
    echo "  bash ci/check-uniffi-bindings-drift.sh --regen"
    echo ""
    echo "Diff:"
    echo "$DIFF_OUT"
    exit 1
fi

echo "OK: PodcastApp UniFFI bindings are up to date."
