@file:OptIn(ExperimentalUnsignedTypes::class)

package io.f7z.podcast

import com.google.flatbuffers.FlatBufferBuilder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import org.nmp.android.TypedProjectionEnvelope

object DomainFrameFixtures {
    fun decodeDomainFrames(raw: String?): PodcastDomainFrames? {
        raw ?: return null
        return runCatching {
            val outerObj = SnapshotCodec.json.parseToJsonElement(raw) as? JsonObject ?: return null
            val tag = outerObj["t"]?.jsonPrimitive?.contentOrNull ?: return null
            if (tag != "snapshot") return null
            val projections = outerObj["v"]?.jsonObject
                ?.get("projections")
                ?.jsonObject
                ?: return null

            val envelopes = projections.mapNotNull { (key, value) ->
                if (!key.startsWith("podcast.")) return@mapNotNull null
                val rev = runCatching {
                    value.jsonObject["rev"]?.jsonPrimitive?.longOrNull?.toULong()
                }.getOrNull() ?: 1uL
                TypedProjectionEnvelope(
                    key = key,
                    schemaId = key,
                    schemaVersion = 1u,
                    fileIdentifier = "PJPR",
                    payload = encodePjpr(value.toString()),
                    projectionRev = rev,
                    state = 0u.toUByte(),
                )
            }
            val frames = TypedProjectionDomainCodec.decodeDomainFrames(envelopes)
            val resolvedProfiles = SnapshotCodec.decodeResolvedProfiles(raw)
            frames
                ?.copy(resolvedProfiles = frames.resolvedProfiles + resolvedProfiles)
                ?: PodcastDomainFrames(resolvedProfiles = resolvedProfiles).takeIf { it.hasAnyDomain }
        }.getOrNull()
    }

    private fun encodePjpr(json: String): ByteArray {
        val fbb = FlatBufferBuilder()
        val jsonOffset = fbb.createString(json)
        fbb.startTable(2)
        fbb.addInt(0, 1, 0)
        fbb.addOffset(1, jsonOffset, 0)
        val root = fbb.endTable()
        fbb.required(root, 6)
        fbb.finish(root, "PJPR")
        return fbb.sizedByteArray()
    }
}
