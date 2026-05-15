#!/usr/bin/env bash
# Build podcastr-core for iOS (device + simulator), produce a universal
# simulator static library, and generate Swift bindings via uniffi-bindgen.
#
# Outputs land in app/ios/Vendor/ + app/ios/Generated/ for the Tuist-generated
# Xcode project to consume.
#
# Usage:
#   PLATFORM_NAME=iphonesimulator ./scripts/generate-swift-bindings.sh
#   PLATFORM_NAME=iphoneos        ./scripts/generate-swift-bindings.sh
#   PLATFORM_NAME=macosx          ./scripts/generate-swift-bindings.sh
#   (empty PLATFORM_NAME is treated as iphonesimulator)

set -euo pipefail

export PATH="$HOME/.cargo/bin:$PATH"

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ROOT="$(cd "$CORE_DIR/../.." && pwd)"
VENDOR_DIR="$APP_ROOT/App/Vendor"
SWIFT_OUT_DIR="$APP_ROOT/App/Sources/PodcastrCore/Generated"

TEMP_OUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/podcastr-swift-bindings.XXXXXX")"
trap 'rm -rf "$TEMP_OUT_DIR"' EXIT

ARM64_SIM_LIB="$CORE_DIR/target/aarch64-apple-ios-sim/release/libpodcastr_core.a"
X86_64_SIM_LIB="$CORE_DIR/target/x86_64-apple-ios/release/libpodcastr_core.a"
IOS_DEVICE_LIB="$CORE_DIR/target/aarch64-apple-ios/release/libpodcastr_core.a"
MACOS_LIB="$CORE_DIR/target/release/libpodcastr_core.a"
UNIVERSAL_SIM_DIR="$CORE_DIR/target/universal-ios-sim/release"
UNIVERSAL_SIM_LIB="$UNIVERSAL_SIM_DIR/libpodcastr_core.a"

platform_name="${PLATFORM_NAME:-}"
default_bindgen_lib=""

build_ios_sim_libs() {
  echo "Building iOS simulator libraries..." >&2
  cargo build --manifest-path "$CORE_DIR/Cargo.toml" --target aarch64-apple-ios-sim --release
  cargo build --manifest-path "$CORE_DIR/Cargo.toml" --target x86_64-apple-ios     --release

  echo "Creating universal simulator library..." >&2
  mkdir -p "$UNIVERSAL_SIM_DIR"
  lipo -create "$ARM64_SIM_LIB" "$X86_64_SIM_LIB" -output "$UNIVERSAL_SIM_LIB"
}

case "$platform_name" in
  macosx)
    echo "Building macOS Rust library..." >&2
    cargo build --manifest-path "$CORE_DIR/Cargo.toml" --release
    default_bindgen_lib="$MACOS_LIB"
    ;;
  iphoneos)
    echo "Building iOS device Rust library..." >&2
    cargo build --manifest-path "$CORE_DIR/Cargo.toml" --target aarch64-apple-ios --release
    default_bindgen_lib="$IOS_DEVICE_LIB"
    ;;
  iphonesimulator|"")
    build_ios_sim_libs
    default_bindgen_lib="$ARM64_SIM_LIB"
    ;;
  *)
    echo "Unknown PLATFORM_NAME '$platform_name'; defaulting to macOS." >&2
    cargo build --manifest-path "$CORE_DIR/Cargo.toml" --release
    default_bindgen_lib="$MACOS_LIB"
    ;;
esac

BINDGEN_LIB="${PODCASTR_CORE_LIB_PATH:-$default_bindgen_lib}"
if [ ! -f "$BINDGEN_LIB" ]; then
  echo "Expected Rust library at $BINDGEN_LIB" >&2
  exit 1
fi

mkdir -p "$SWIFT_OUT_DIR" "$VENDOR_DIR"

# uniffi-bindgen internally shells out to `cargo metadata`, which must run
# against the podcastr-core Cargo.toml, not whatever CWD Xcode left us in.
(cd "$CORE_DIR" && cargo run --bin uniffi-bindgen -- generate \
  --library "$BINDGEN_LIB" \
  --language swift \
  --out-dir "$TEMP_OUT_DIR")

if [ ! -f "$TEMP_OUT_DIR/podcastr_core.swift" ]; then
  echo "Expected $TEMP_OUT_DIR/podcastr_core.swift to be generated." >&2
  exit 1
fi

cp "$TEMP_OUT_DIR/podcastr_core.swift"        "$SWIFT_OUT_DIR/podcastr_core.swift"
cp "$TEMP_OUT_DIR/podcastr_coreFFI.h"         "$VENDOR_DIR/podcastr_coreFFI.h"
cp "$TEMP_OUT_DIR/podcastr_coreFFI.modulemap" "$VENDOR_DIR/module.modulemap"

echo "Swift bindings generated." >&2
echo "  Swift:      $SWIFT_OUT_DIR/podcastr_core.swift" >&2
echo "  FFI header: $VENDOR_DIR/podcastr_coreFFI.h" >&2
echo "  modulemap:  $VENDOR_DIR/module.modulemap" >&2
