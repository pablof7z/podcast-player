// M2.F second-platform proof. Standalone Gradle project that links the SAME
// `nmp-app-podcast` Rust crate the iOS app consumes — built as a cdylib by
// cargo-ndk into `app/src/main/jniLibs/<abi>/libnmp_app_podcast.so`.
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "PodcastAndroid"
include(":app")
