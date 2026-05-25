import org.gradle.internal.os.OperatingSystem

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "io.f7z.podcast"
    compileSdk = 34

    defaultConfig {
        applicationId = "io.f7z.podcast"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    composeOptions { kotlinCompilerExtensionVersion = "1.5.14" }

    // `.so` files are produced by cargo-ndk into `src/main/jniLibs/<abi>` —
    // the same layout NMP's Chirp Android uses.
    sourceSets["main"].jniLibs.srcDirs("src/main/jniLibs")
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.06.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.2")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
}

// ── cargo-ndk task ───────────────────────────────────────────────────────────
//
// Cross-compile the SAME `nmp-app-podcast` crate the iOS app links, packed as
// `libnmp_app_podcast.so` for the two shipped Android ABIs. Output lands
// directly in `jniLibs/<abi>/` for both targets.
//
// The crate's `cdylib` target embeds the JNI shim from
// `apps/nmp-app-podcast/src/android.rs` (gated `#[cfg(target_os = "android")]`)
// — the `Java_io_f7z_podcast_KernelBridge_*` symbols `KernelBridge.kt` binds.
//
// Manual invocation (matches what `preBuild` runs):
//
//   cd ../..  # repo root
//   ANDROID_NDK_HOME=$HOME/Library/Android/sdk/ndk/<version> \
//     cargo ndk -t arm64-v8a -t x86_64 \
//       --manifest-path apps/nmp-app-podcast/Cargo.toml \
//       -o android/Podcast/app/src/main/jniLibs \
//       build --release
val cargoNdk by tasks.registering(Exec::class) {
    // Run cargo from the workspace root (4 levels up: app → Podcast → android → repo).
    workingDir = rootProject.projectDir.parentFile.parentFile
    val cargo = "${System.getProperty("user.home")}/.cargo/bin/cargo"
    val bin = if (OperatingSystem.current().isWindows) "$cargo.exe" else cargo
    commandLine(
        bin, "ndk",
        "--manifest-path", "apps/nmp-app-podcast/Cargo.toml",
        "-t", "arm64-v8a", "-t", "x86_64",
        "-o", "android/Podcast/app/src/main/jniLibs",
        "build", "--release",
    )
}

tasks.named("preBuild") { dependsOn(cargoNdk) }
