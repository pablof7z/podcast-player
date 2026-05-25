package io.f7z.podcast

import android.app.Application

/**
 * Minimal `Application` class. Present mostly so the manifest has a stable
 * symbol to attach to and so M3+ has a hook for app-scope wiring (e.g. an
 * `ActivityLifecycleCallbacks` that maps foreground/background into
 * `nmp_app_lifecycle_*`).
 */
class PodcastApp : Application()
