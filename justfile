PABLO_IPHONE := "3C438D9B-2021-5A30-93DB-910F7754F9A2"

# Deploy to Pablo's iPhone: rebuild Rust, build Swift (embed phase signs the dylib), install, launch
pablo-iphone-deploy:
    #!/usr/bin/env bash
    set -euo pipefail
    DEVICE="{{PABLO_IPHONE}}"

    echo "==> Rebuilding Rust for aarch64-apple-ios..."
    cargo build --target aarch64-apple-ios -p nmp-app-podcast

    # The linker prefers .dylib over .a, which avoids duplicate-symbol conflicts
    # with shake_feedback_core.a when LiteRTLM's -all_load is active. The dylib's
    # install name is fixed to @rpath so the device loader can find it at runtime.
    # The Xcode "Embed Rust Dylib" build phase copies + signs it via the real cert.
    echo "==> Fixing dylib install name..."
    install_name_tool -id "@rpath/libnmp_app_podcast.dylib" \
        target/aarch64-apple-ios/debug/libnmp_app_podcast.dylib
    # Remove the deps copy so the linker resolves to only the top-level dylib.
    rm -f target/aarch64-apple-ios/debug/deps/libnmp_app_podcast.dylib

    echo "==> Building Xcode (device)..."
    xcodebuild build \
        -workspace Podcastr.xcworkspace \
        -scheme Podcastr \
        -configuration Debug \
        -destination "id=$DEVICE" \
        -skipPackagePluginValidation \
        2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED|✅|❌" || true

    PRODUCTS_DIR=$(xcodebuild -workspace Podcastr.xcworkspace -scheme Podcastr \
        -configuration Debug -showBuildSettings 2>/dev/null \
        | grep '^ *BUILT_PRODUCTS_DIR' | awk 'NR==1{print $3}')
    APP="$PRODUCTS_DIR/Podcastr.app"

    echo "==> Installing on device $DEVICE..."
    xcrun devicectl device install app --device "$DEVICE" "$APP"

    echo "==> Launching..."
    xcrun devicectl device process launch --device "$DEVICE" io.f7z.podcast

    echo "✅ Done — app running on Pablo's iPhone"
