// Project-level build script. Pins versions for the only two plugins the app
// module needs — the Android Gradle Plugin and Kotlin (with serialization for
// the Rust snapshot JSON decode). Kept lean: the heavy lifting lives in the
// `:app` module.
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "1.9.24" apply false
}
