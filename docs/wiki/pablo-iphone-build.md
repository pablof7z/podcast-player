---
title: Pablo iPhone Build
slug: pablo-iphone-build
topic: project-setup
summary: "The app builds and runs directly on Pablo's iPhone (UDID: 3C438D9B-2021-5A30-93DB-910F7754F9A2) via a wired connection, without using TestFlight."
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-15
updated: 2026-06-12
verified: 2026-05-15
compiled-from: conversation
sources:
  - session:a6b98d9b-32b6-49e0-9bda-3204ca8808bb
  - session:f3b466c6-7791-44b3-b004-aae2066a9019
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
  - session:e1cfd663-230d-4f78-9078-0c9ed8b6a4bb
  - session:8bfa1b91-b40c-44b3-acb9-245b36f4c841
  - session:c43d5e77-d667-4e71-a574-47aaab5b6a7a
  - session:6706236b-c94a-4458-aa7b-6f71098aa55b
  - session:56e47844-b4ff-4402-9528-c704eade1d7b
  - session:713480e4-3c98-439e-a897-2f41d37acbfd
  - session:7e35e451-81d2-4832-8c6e-34d44fc29e12
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
---

# Pablo iPhone Build

## Device Deployment

The app builds and runs directly on Pablo's iPhone (UDID: 3C438D9B-2021-5A30-93DB-910F7754F9A2) via a wired connection, without using TestFlight. (Previously: without using TestFlight.) The device deployment was built from merged main (commit 843ef7f3) containing both PR #351 and PR #352, with automatic signing using the Apple Development cert for Pablo Fernandez and the io.f7z.podcast provisioning profile. The ios-shake-feedback Package.swift is switched from 21-DOT-DEV/swift-secp256k1 to GigaBitcoin/recp256k1.swift, and `import secp256k1` is changed to `import P256K`, to fix a pre-existing duplicate-symbol conflict that surfaced during SPM fresh resolution. The ios-shake-feedback module is initialized as a fresh git repo with a single commit capturing the Package.swift and ShakeFeedbackCrypto.swift changes. Xcode build configurations use sdk-conditional OTHER_LDFLAGS: device builds (sdk=iphoneos*) point at the explicit .dylib path for libnmp_app_podcast, while simulator builds keep the -lnmp_app_podcast flag. The Rust dylib (libnmp_app_podcast.dylib) must be kept as a dynamic framework rather than a static .a, because LiteRTLM's -all_load flag causes duplicate-symbol conflicts between two Rust static libs that both embed the Rust std. The dylib install name must be set to @rpath/libnmp_app_podcast.dylib via install_name_tool, and the dylib must be copied into the app bundle's Frameworks directory and signed with the development certificate by an Xcode build phase. An Xcode build phase script (Embed Rust Dylib) was added to Project.swift to copy and codesign the dylib into the app bundle using the real development certificate, because Xcode's own signing step covers embedded frameworks but not manually placed files. The justfile command pablo-iphone-deploy was restored and now keeps the Rust dylib, delegating its @rpath install name rewrite, embedding, and codesigning to Project.swift's build phases. It uses a fresh derivedData directory (`/tmp/dd-iphone-deploy`, wiped each run) to prevent stale objects from causing phantom duplicate symbols, and `-destination 'generic/platform=iOS'` instead of `id=$DEVICE` so the device does not need to be connected at build time, along with `-allowProvisioningUpdates`. The recipe reads the app path directly from the derivedData products directory instead of parsing `-showBuildSettings` with awk (which injected a stray newline causing the NSURL `%0A` path bug). After launch, it waits 6 seconds and confirms the process is still running, failing loudly with an `otool -L` diagnostic hint if it dyld-crashed. An XCUITest drives the real Agent UI on a physical iPhone (taps Open Agent, types a message, sends, reads the reply or error), and it has passed with the on-device Gemma replying 'Hey Pablo — ready when you are.' to the typed message.

<!-- citations: [^e1cfd-10] [^a6b98-9] [^f3b46-23] [^14943-15] [^8bfa1-4] [^c43d5-11] [^67062-8] [^56e47-8] [^71348-1] [^7e35e-10] -->
## Simulator Build Fix

The build.rs chkstk stub compilation for the simulator target was fixed to use xcrun and match the correct target triple aarch64-apple-ios-sim instead of the previously mismatched check for aarch64-sim. <!-- [^e1cfd-11] -->

CI iOS sim destination discovery now uses runtime UDID lookup (preferring the *ci simulator, falling back to any iPhone) instead of a hardcoded iPhone 17 name, preventing future Xcode/simulator bumps from breaking the test gate. <!-- [^c1691-29] -->
