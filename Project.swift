import ProjectDescription

// MARK: - Configure these before running `tuist generate`

let appName = "Podcastr"
let appDisplayName = "Podcastr"
let appleTeamID = "456SHKPP26"
let deploymentTarget: DeploymentTargets = .iOS("26.0")

// MARK: - Derived identifiers

// `appBundleID` is fixed (not derived from `appName`) so renaming the working
// title doesn't invalidate the existing provisioning profile / TestFlight /
// App Store record tied to `io.f7z.podcast`.
let appBundleID = "io.f7z.podcast"
// App Group identifier is hardcoded (does not follow the bundle-ID derivation
// pattern) so the working title can change without re-provisioning the group.
let appGroupID = "group.com.podcastr.app"
let widgetBundleID = "\(appBundleID).widget"

// MARK: - Project

let project = Project(
    name: appName,
    organizationName: "f7z",
    options: .options(
        automaticSchemesOptions: .disabled,
        developmentRegion: "en"
    ),
    packages: [
        .remote(
            url: "https://github.com/GigaBitcoin/secp256k1.swift",
            requirement: .upToNextMajor(from: "0.23.1")
        ),
        // Lane 6 — RAG: on-device vector store via sqlite-vec.
        // Hosts both the `vec0` virtual table for embeddings and `fts5` for
        // hybrid lexical search in a single SQLite file.
        .remote(
            url: "https://github.com/jkrukowski/SQLiteVec",
            requirement: .upToNextMinor(from: "0.0.14")
        ),
        // Kingfisher — memory + disk image cache. Backs `CachedAsyncImage`
        // so artwork URLs (subscription / episode covers, iTunes Search
        // results, etc.) fetch at most once per session instead of
        // re-downloading every appearance like SwiftUI's stock `AsyncImage`.
        .remote(
            url: "https://github.com/onevcat/Kingfisher",
            requirement: .upToNextMajor(from: "8.0.0")
        ),
        .local(path: "../ios-shake-feedback"),
    ],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "DEVELOPMENT_TEAM": "\(appleTeamID)",
            "CODE_SIGN_STYLE": "Automatic",
            // Disabled because the Podcastr target's pre-build script invokes
            // `cargo build`, which writes to `App/core/target/` — outside any
            // sandbox I/O declaration. Re-enabling would block the Rust core
            // build step and produce stale UniFFI bindings.
            "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
        ]
    ),
    targets: [
        .target(
            name: appName,
            destinations: [.iPhone, .iPad],
            product: .app,
            bundleId: appBundleID,
            deploymentTargets: deploymentTarget,
            infoPlist: .file(path: "App/Resources/Info.plist"),
            sources: ["App/Sources/**"],
            resources: [
                "App/Resources/Assets.xcassets",
                "App/Resources/whats-new.json",
            ],
            entitlements: .file(path: "App/Resources/Podcastr.entitlements"),
            scripts: [
                // Rebuild the Rust core static library and regenerate the
                // UniFFI Swift bindings + C header + modulemap on every build.
                // `basedOnDependencyAnalysis: false` forces Xcode to run the
                // script every time — without it, Xcode caches based on
                // declared inputs and would happily compile against stale
                // bindings whenever any Rust source under `App/core/src/`
                // changes.
                .pre(
                    script: """
                    bash "${SRCROOT}/App/core/scripts/generate-swift-bindings.sh"
                    """,
                    name: "Generate Swift bindings + build Rust static lib",
                    basedOnDependencyAnalysis: false
                ),
            ],
            dependencies: [
                .package(product: "P256K"),
                .package(product: "SQLiteVec"),
                .package(product: "Kingfisher"),
                .package(product: "ShakeFeedbackKit"),
                .target(name: "\(appName)Widget"),
            ],
            settings: .settings(
                base: [
                    "APP_BUNDLE_IDENTIFIER": "\(appBundleID)",
                    "APP_GROUP_IDENTIFIER": "\(appGroupID)",
                    "PRODUCT_BUNDLE_IDENTIFIER": "$(APP_BUNDLE_IDENTIFIER)",
                    "CFBundleDisplayName": "\(appDisplayName)",
                    "GENERATE_INFOPLIST_FILE": "NO",
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                    "TARGETED_DEVICE_FAMILY": "1,2",
                    "PROVISIONING_PROFILE_SPECIFIER": "$(CI_APP_PROFILE_SPECIFIER)",

                    // --- Rust core (UniFFI) wiring ---
                    //
                    // `App/Vendor/` holds the generated `podcastr_coreFFI.h`
                    // and `module.modulemap` that lets Swift `import` the
                    // C symbols emitted by uniffi-bindgen. Both Clang
                    // (HEADER_SEARCH_PATHS) and the Swift importer
                    // (SWIFT_INCLUDE_PATHS) need to see it.
                    "HEADER_SEARCH_PATHS": [
                        "$(inherited)",
                        "$(SRCROOT)/App/Vendor",
                    ],
                    "SWIFT_INCLUDE_PATHS": [
                        "$(inherited)",
                        "$(SRCROOT)/App/Vendor",
                    ],
                    // Path to the platform-specific Rust static library.
                    // `generate-swift-bindings.sh` produces these exact paths:
                    //   iphonesimulator -> universal arm64+x86_64 via `lipo`
                    //   iphoneos        -> aarch64-apple-ios
                    "LIBRARY_SEARCH_PATHS[sdk=iphonesimulator*]": [
                        "$(inherited)",
                        "$(SRCROOT)/App/core/target/universal-ios-sim/release",
                    ],
                    "LIBRARY_SEARCH_PATHS[sdk=iphoneos*]": [
                        "$(inherited)",
                        "$(SRCROOT)/App/core/target/aarch64-apple-ios/release",
                    ],
                    // Link the static lib by absolute path (matches the
                    // highlighter pattern). Using the full path rather than
                    // `-lpodcastr_core` gives the linker a clear error if the
                    // pre-build script hasn't produced the file yet.
                    "OTHER_LDFLAGS[sdk=iphonesimulator*]": [
                        "$(inherited)",
                        "$(SRCROOT)/App/core/target/universal-ios-sim/release/libpodcastr_core.a",
                    ],
                    "OTHER_LDFLAGS[sdk=iphoneos*]": [
                        "$(inherited)",
                        "$(SRCROOT)/App/core/target/aarch64-apple-ios/release/libpodcastr_core.a",
                    ],
                ]
            )
        ),
        // MARK: - Widget extension
        .target(
            name: "\(appName)Widget",
            destinations: [.iPhone, .iPad],
            product: .appExtension,
            bundleId: widgetBundleID,
            deploymentTargets: deploymentTarget,
            infoPlist: .file(path: "App/Widget/Resources/Info.plist"),
            sources: ["App/Widget/Sources/**"],
            resources: [],
            entitlements: .file(path: "App/Widget/Resources/PodcastrWidget.entitlements"),
            dependencies: [],
            settings: .settings(
                base: [
                    "APP_BUNDLE_IDENTIFIER": "\(widgetBundleID)",
                    "APP_GROUP_IDENTIFIER": "\(appGroupID)",
                    "PRODUCT_BUNDLE_IDENTIFIER": "$(APP_BUNDLE_IDENTIFIER)",
                    "CFBundleDisplayName": "\(appDisplayName)",
                    "GENERATE_INFOPLIST_FILE": "NO",
                    "TARGETED_DEVICE_FAMILY": "1,2",
                    "SWIFT_VERSION": "6.0",
                    "SWIFT_STRICT_CONCURRENCY": "complete",
                    "PROVISIONING_PROFILE_SPECIFIER": "$(CI_WIDGET_PROFILE_SPECIFIER)",
                ]
            )
        ),
        .target(
            name: "\(appName)Tests",
            destinations: [.iPhone],
            product: .unitTests,
            bundleId: "\(appBundleID).tests",
            deploymentTargets: deploymentTarget,
            sources: ["AppTests/Sources/**"],
            dependencies: [.target(name: appName)],
            settings: .settings(
                base: [
                    "GENERATE_INFOPLIST_FILE": "YES",
                    "PRODUCT_BUNDLE_IDENTIFIER": "\(appBundleID).tests",
                    "BUNDLE_LOADER": "$(TEST_HOST)",
                    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/\(appName).app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/\(appName)",
                ]
            )
        ),
    ],
    schemes: [
        .scheme(
            name: appName,
            buildAction: .buildAction(targets: [.target(appName), .target("\(appName)Widget")]),
            testAction: .targets([.testableTarget(target: .target("\(appName)Tests"))]),
            runAction: .runAction(configuration: .debug),
            archiveAction: .archiveAction(configuration: .release),
            profileAction: .profileAction(configuration: .release),
            analyzeAction: .analyzeAction(configuration: .debug)
        )
    ]
)
