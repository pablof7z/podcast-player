@file:OptIn(ExperimentalUnsignedTypes::class)

package io.f7z.podcast

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlinx.serialization.DeserializationStrategy
import org.nmp.android.TypedProjectionEnvelope
import podcastr.projection.PodcastProjectionJsonFrame

/**
 * App-owned decoder for the `podcast.*` typed read projections.
 *
 * NMP owns the typed envelope, projection revs, and merge cache. Podcast Player
 * owns the PJPR body schema: a tiny FlatBuffers wrapper around the existing
 * app-domain JSON frame.
 */
object TypedProjectionDomainCodec {
    fun decodeDomainFrames(projections: List<TypedProjectionEnvelope>): PodcastDomainFrames? {
        val frames = PodcastDomainFrames(
            library = decode(DomainSchema.LIBRARY, projections, LibraryDomainFrame.serializer()),
            playback = decode(DomainSchema.PLAYBACK, projections, PlaybackDomainFrame.serializer()),
            downloads = decode(DomainSchema.DOWNLOADS, projections, DownloadsDomainFrame.serializer()),
            settings = decode(DomainSchema.SETTINGS, projections, SettingsDomainFrame.serializer()),
            identity = decode(DomainSchema.IDENTITY, projections, IdentityDomainFrame.serializer()),
            widget = decode(DomainSchema.WIDGET, projections, WidgetDomainFrame.serializer()),
            social = decode(DomainSchema.SOCIAL, projections, SocialDomainFrame.serializer()),
            voice = decode(DomainSchema.VOICE, projections, VoiceDomainFrame.serializer()),
            misc = decode(DomainSchema.MISC, projections, MiscDomainFrame.serializer()),
        )
        return if (frames.hasAnyDomain) frames else null
    }

    private fun <T> decode(
        key: String,
        projections: List<TypedProjectionEnvelope>,
        deserializer: DeserializationStrategy<T>,
    ): T? {
        val projection = projections.firstOrNull {
            it.key == key &&
                it.schemaId == key &&
                it.schemaVersion == SCHEMA_VERSION &&
                it.fileIdentifier == FILE_IDENTIFIER &&
                it.payload.isNotEmpty()
        } ?: return null

        return runCatching {
            val buffer = ByteBuffer.wrap(projection.payload).order(ByteOrder.LITTLE_ENDIAN)
            if (!PodcastProjectionJsonFrame.PodcastProjectionJsonFrameBufferHasIdentifier(buffer)) {
                return null
            }
            val frame = PodcastProjectionJsonFrame.getRootAsPodcastProjectionJsonFrame(buffer)
            if (frame.schemaVersion() != SCHEMA_VERSION.toLong()) {
                return null
            }
            SnapshotCodec.json.decodeFromString(deserializer, frame.json())
        }.getOrNull()
    }

    private const val FILE_IDENTIFIER = "PJPR"
    private val SCHEMA_VERSION: UInt = 1u
}
