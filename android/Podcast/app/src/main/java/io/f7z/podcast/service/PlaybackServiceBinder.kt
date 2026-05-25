package io.f7z.podcast.service

import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import java.util.concurrent.atomic.AtomicReference

/**
 * Thin in-process holder that publishes the [`ExoPlayer`] + [`MediaSession`]
 * owned by [`PodcastPlaybackService`] to other components (the capability
 * executor, the activity).
 *
 * **Why an object holder, not a `ServiceConnection` + `IBinder`?**
 *
 * `PodcastPlaybackService` runs in the same process as the activity and
 * the kernel (manifest does not declare `android:process`); they share
 * the JVM heap. A `ServiceConnection.onServiceConnected` round-trip would
 * add a frame of latency for zero isolation gain. The system clients
 * (Bluetooth, Wear, Android Auto) cross the process boundary through
 * `MediaSession` itself — that surface is independent of this in-process
 * holder.
 *
 * **Doctrine:**
 *
 *  * D5/D8 — no business state. Publishes references, never decisions.
 *  * D6 — `current()` returns `null` if the service hasn't published yet
 *    (e.g. the activity bound to a capability before the service started).
 *    Callers degrade silently — the next snapshot tick re-renders once
 *    the player is alive.
 *
 * **Threading:** `AtomicReference` is overkill if everything ran on the
 * main thread, but `Player.Listener` callbacks fire on the application
 * thread and the activity's `LaunchedEffect` coroutines bind on dispatch
 * threads. The atomic keeps the publish/observe race safe without a
 * monitor.
 */
internal object PlaybackServiceBinder {

    /**
     * Snapshot of what `PodcastPlaybackService.onCreate` published. Both
     * fields go from `null` → set → `null` exactly once per service
     * lifetime.
     */
    data class Handle(val player: Player, val session: MediaSession)

    private val ref: AtomicReference<Handle?> = AtomicReference(null)

    /**
     * Called by `PodcastPlaybackService.onCreate` once the player and
     * session are ready for foreign attachment. The `MediaSession` is
     * unused today (its system surface comes for free); kept on the
     * handle so a future `PlayerNotificationManager` wire-up can pick it
     * up without re-plumbing.
     */
    fun publish(player: ExoPlayer, session: MediaSession?) {
        ref.set(if (session != null) Handle(player, session) else null)
    }

    /**
     * Returns the live handle, or `null` if the service has not yet
     * called [`publish`] (or has already called [`clear`]). Read-only;
     * callers that need to mutate the player invoke methods on
     * `handle.player` directly.
     */
    fun current(): Handle? = ref.get()

    /**
     * Called by `PodcastPlaybackService.onDestroy` to drop the references
     * — releases held listeners, lets the JVM reclaim the player.
     */
    fun clear() {
        ref.set(null)
    }
}
