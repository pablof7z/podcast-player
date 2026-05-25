package io.f7z.podcast

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Mirror of the JSON the Rust `nmp_app_podcast_snapshot` entry point emits.
 * Today (M0/M2.A) the payload is a stub:
 *
 *   ```json
 *   {"running":true,"rev":0,"schema_version":1}
 *   ```
 *
 * The library projection (`LibraryProjection` in `podcast-core`) is wired up
 * in M2.A but not yet serialized through the FFI. When it is, this struct
 * gains a `library: List<PodcastSummary>` field and the placeholder UI in
 * `MainActivity.kt` will start rendering real subscriptions.
 */
@Serializable
data class PodcastSnapshot(
    val running: Boolean = false,
    val rev: Long = 0,
    @SerialName("schema_version") val schemaVersion: Int = 0,
    /** Will hold `LibraryProjection` rows in a later milestone. */
    val library: List<PodcastSummary> = emptyList(),
)

/**
 * One row of the future library projection. Matches the shape the iOS shell
 * already decodes from `LibraryDisplayProjection`. Kept here so the Compose
 * UI compiles against a stable contract even though the Rust serializer is
 * still emitting stubs.
 */
@Serializable
data class PodcastSummary(
    val id: String,
    val title: String,
    @SerialName("episode_count") val episodeCount: Int = 0,
    @SerialName("unplayed_count") val unplayedCount: Int = 0,
)

/** Lazy JSON parser shared by the snapshot consumer. */
object SnapshotCodec {
    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
    }

    fun decode(raw: String?): PodcastSnapshot? =
        raw?.let { runCatching { json.decodeFromString<PodcastSnapshot>(it) }.getOrNull() }
}
