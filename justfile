PABLO_IPHONE := "3C438D9B-2021-5A30-93DB-910F7754F9A2"

# Deploy to Pablo's iPhone: rebuild Rust, build Swift, install, launch, verify alive
pablo-iphone-deploy:
    #!/usr/bin/env bash
    set -euo pipefail
    DEVICE="{{PABLO_IPHONE}}"
    DD=/tmp/dd-iphone-deploy

    echo "==> Rebuilding Rust for aarch64-apple-ios..."
    cargo build --target aarch64-apple-ios -p nmp-app-podcast

    # KEEP the dylib. Project.swift has two build phases — "Fix Rust Dylib
    # Install Name" (install_name_tool -id @rpath/... before link) and
    # "Embed Rust Dylib" (copy to Frameworks/ + codesign). With the dylib
    # present the linker prefers it over the .a and records @rpath, so there
    # are NO duplicate std symbols. (Deleting the dylib to force static .a
    # linking — the old recipe — fails: two Rust .a libs each force-load std
    # via -all_load → ~15 duplicate-symbol errors. Don't do that.)
    # The phases source the dylib from $SRCROOT/target/$RUST_TARGET/debug, so
    # ensure cargo built it there (not ~/.cargo/target-shared).
    DYLIB=target/aarch64-apple-ios/debug/libnmp_app_podcast.dylib
    if [ ! -f "$DYLIB" ]; then
        SHARED="$HOME/.cargo/target-shared/aarch64-apple-ios/debug/libnmp_app_podcast.dylib"
        [ -f "$SHARED" ] && cp "$SHARED" "$DYLIB"
    fi

    # Fresh derivedData so stale objects from a prior failed link can't cause
    # phantom duplicate-symbol errors. generic/platform=iOS doesn't need the
    # device connected at build time.
    echo "==> Building Xcode (device)..."
    rm -rf "$DD"
    xcodebuild build \
        -workspace Podcastr.xcworkspace \
        -scheme Podcastr \
        -configuration Debug \
        -destination "generic/platform=iOS" \
        -skipPackagePluginValidation \
        -allowProvisioningUpdates \
        -derivedDataPath "$DD" \
        2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED|✅|❌" || true

    APP="$DD/Build/Products/Debug-iphoneos/Podcastr.app"
    [ -d "$APP" ] || { echo "❌ Build produced no app at $APP"; exit 1; }

    echo "==> Installing on device $DEVICE..."
    xcrun devicectl device install app --device "$DEVICE" "$APP"

    echo "==> Launching..."
    xcrun devicectl device process launch --device "$DEVICE" io.f7z.podcast

    # "Launched" alone isn't proof — a dyld load failure exits within ~2s.
    sleep 6
    if xcrun devicectl device info processes --device "$DEVICE" 2>/dev/null | grep -qi podcastr; then
        echo "✅ Done — app alive on Pablo's iPhone"
    else
        echo "❌ App launched but is NOT running — likely a dyld crash."
        echo "   Check: otool -L \"$APP/Podcastr.debug.dylib\" | grep nmp"
        echo "   (look for an absolute /Users/.../target/... path instead of @rpath)"
        exit 1
    fi
