// GENERATED. DO NOT EDIT BY HAND.
//
// Regenerate with nmp-codegen --registry <app>/action-builders.json --platform kotlin.
//
// Source of truth: app-local action-builders registry JSON passed via
// `--registry`. NOT NMP's built-in `ACTION_BUILDERS` table.

package org.nmp.android

import com.google.flatbuffers.FlatBufferBuilder

object GeneratedActionBuilders {
    enum class PublishSignerProvenance(val token: String) {
        APP_MANAGED("app_managed"),
        USER_SELECTED("user_selected"),
        PROTOCOL_PINNED("protocol_pinned"),
        DIAGNOSTIC("diagnostic"),
    }

    sealed class PublishSignerSelection {
        object Active : PublishSignerSelection()
        data class Registered(
            val pubkey: String,
            val provenance: PublishSignerProvenance = PublishSignerProvenance.APP_MANAGED,
        ) : PublishSignerSelection()
    }

    enum class PublishRouteClass(val token: String) {
        MANUAL_OVERRIDE("manual_override"),
        GROUP_HOST_PIN("group_host_pin"),
        VERIFIED_PRIVATE_INBOX("verified_private_inbox"),
        IMPORTED_OR_PRESIGNED("imported_or_presigned"),
        DIAGNOSTIC("diagnostic"),
    }

    sealed class PublishTargetSelection {
        object Auto : PublishTargetSelection()
        data class Explicit(
            val relays: List<String>,
            val routeClass: PublishRouteClass,
        ) : PublishTargetSelection()
    }

    /// The single recognised envelope schema version — mirrors
    /// `nmp_core::dispatch_envelope::DISPATCH_ENVELOPE_SCHEMA_VERSION`.
    const val DISPATCH_ENVELOPE_SCHEMA_VERSION: Int = 1

    /// Stamp `(correlationId, actionNamespace, schemaVersion, payload)` into a
    /// `DispatchEnvelope` and return the finished bytes (file identifier `NMPD`).
    /// The byte-for-byte twin of `encode_dispatch_envelope` in `nmp-core`.
    private fun encodeDispatchEnvelope(
        correlationId: String,
        actionNamespace: String,
        payload: ByteArray,
    ): ByteArray {
        val fbb = FlatBufferBuilder()
        val correlationOffset = fbb.createString(correlationId)
        val namespaceOffset = fbb.createString(actionNamespace)
        val payloadOffset = fbb.createByteVector(payload)
        fbb.startTable(4)
        fbb.addOffset(0, correlationOffset, 0)   // slot 0: correlation_id
        fbb.addOffset(1, namespaceOffset, 0)     // slot 1: action_namespace
        fbb.addInt(2, DISPATCH_ENVELOPE_SCHEMA_VERSION, 0) // slot 2: schema_version
        fbb.addOffset(3, payloadOffset, 0)       // slot 3: payload
        val root = fbb.endTable()
        fbb.finish(root, "NMPD")
        return fbb.sizedByteArray()
    }

    /// Map a relay role string to the RelayMarker ubyte (Both=0, Read=1, Write=2, Indexer=3),
    /// mirroring `RelayMarker::from_role_string` in `nmp-router` EXACTLY — including rejection.
    /// Unknown tokens or no-flag input (e.g. empty string) encode as 255 (out-of-range sentinel)
    /// so the Rust decoder (`marker_from_wire`) fails closed instead of silently becoming Both.
    /// Role strings may be comma-separated (e.g. `"both,indexer"`); comparisons are case-insensitive.
    private fun relayMarkerByte(role: String): Byte {
        var hasBoth = false; var hasRead = false; var hasWrite = false; var hasIndexer = false
        var invalid = false
        for (part in role.split(",").map { it.trim().lowercase() }) {
            when (part) {
                "" -> {}
                "both" -> hasBoth = true
                "read" -> hasRead = true
                "write" -> hasWrite = true
                "indexer" -> hasIndexer = true
                else -> invalid = true
            }
        }
        if (invalid) return 255.toByte()
        return (when {
            hasBoth || (hasRead && hasWrite) -> 0
            hasRead -> 1
            hasWrite -> 2
            hasIndexer -> 3
            else -> 255
        }).toByte()
    }

    /// Dispatch a root podcast action body through the app-local typed byte doorway.
    /// Builds the `podcast` `DispatchEnvelope` bytes for the byte doorway.
    fun podcastJson(
        correlationId: String,
        json: String,
    ): ByteArray {
        val fbb = FlatBufferBuilder()
        val jsonOffset = fbb.createString(json)
        fbb.startTable(2)
        fbb.addInt(0, 1, 0) // slot 0: schema_version
        fbb.addOffset(1, jsonOffset, 0) // slot 1: json
        val payloadRoot = fbb.endTable()
        fbb.finish(payloadRoot, "PJSN")
        val payload = fbb.sizedByteArray()
        return encodeDispatchEnvelope(
            correlationId = correlationId,
            actionNamespace = "podcast",
            payload = payload,
        )
    }

    /// Dispatch a podcast.agent action body through the app-local typed byte doorway.
    /// Builds the `podcast.agent` `DispatchEnvelope` bytes for the byte doorway.
    fun podcastAgentJson(
        correlationId: String,
        json: String,
    ): ByteArray {
        val fbb = FlatBufferBuilder()
        val jsonOffset = fbb.createString(json)
        fbb.startTable(2)
        fbb.addInt(0, 1, 0) // slot 0: schema_version
        fbb.addOffset(1, jsonOffset, 0) // slot 1: json
        val payloadRoot = fbb.endTable()
        fbb.finish(payloadRoot, "PJSN")
        val payload = fbb.sizedByteArray()
        return encodeDispatchEnvelope(
            correlationId = correlationId,
            actionNamespace = "podcast.agent",
            payload = payload,
        )
    }

    /// Dispatch a podcast.categorize action body through the app-local typed byte doorway.
    /// Builds the `podcast.categorize` `DispatchEnvelope` bytes for the byte doorway.
    fun podcastCategorizeJson(
        correlationId: String,
        json: String,
    ): ByteArray {
        val fbb = FlatBufferBuilder()
        val jsonOffset = fbb.createString(json)
        fbb.startTable(2)
        fbb.addInt(0, 1, 0) // slot 0: schema_version
        fbb.addOffset(1, jsonOffset, 0) // slot 1: json
        val payloadRoot = fbb.endTable()
        fbb.finish(payloadRoot, "PJSN")
        val payload = fbb.sizedByteArray()
        return encodeDispatchEnvelope(
            correlationId = correlationId,
            actionNamespace = "podcast.categorize",
            payload = payload,
        )
    }

    /// Dispatch a podcast.chapters action body through the app-local typed byte doorway.
    /// Builds the `podcast.chapters` `DispatchEnvelope` bytes for the byte doorway.
    fun podcastChaptersJson(
        correlationId: String,
        json: String,
    ): ByteArray {
        val fbb = FlatBufferBuilder()
        val jsonOffset = fbb.createString(json)
        fbb.startTable(2)
        fbb.addInt(0, 1, 0) // slot 0: schema_version
        fbb.addOffset(1, jsonOffset, 0) // slot 1: json
        val payloadRoot = fbb.endTable()
        fbb.finish(payloadRoot, "PJSN")
        val payload = fbb.sizedByteArray()
        return encodeDispatchEnvelope(
            correlationId = correlationId,
            actionNamespace = "podcast.chapters",
            payload = payload,
        )
    }

    /// Dispatch a podcast.clip action body through the app-local typed byte doorway.
    /// Builds the `podcast.clip` `DispatchEnvelope` bytes for the byte doorway.
    fun podcastClipJson(
        correlationId: String,
        json: String,
    ): ByteArray {
        val fbb = FlatBufferBuilder()
        val jsonOffset = fbb.createString(json)
        fbb.startTable(2)
        fbb.addInt(0, 1, 0) // slot 0: schema_version
        fbb.addOffset(1, jsonOffset, 0) // slot 1: json
        val payloadRoot = fbb.endTable()
        fbb.finish(payloadRoot, "PJSN")
        val payload = fbb.sizedByteArray()
        return encodeDispatchEnvelope(
            correlationId = correlationId,
            actionNamespace = "podcast.clip",
            payload = payload,
        )
    }

    /// Dispatch a podcast.identity action body through the app-local typed byte doorway.
    /// Builds the `podcast.identity` `DispatchEnvelope` bytes for the byte doorway.
    fun podcastIdentityJson(
        correlationId: String,
        json: String,
    ): ByteArray {
        val fbb = FlatBufferBuilder()
        val jsonOffset = fbb.createString(json)
        fbb.startTable(2)
        fbb.addInt(0, 1, 0) // slot 0: schema_version
        fbb.addOffset(1, jsonOffset, 0) // slot 1: json
        val payloadRoot = fbb.endTable()
        fbb.finish(payloadRoot, "PJSN")
        val payload = fbb.sizedByteArray()
        return encodeDispatchEnvelope(
            correlationId = correlationId,
            actionNamespace = "podcast.identity",
            payload = payload,
        )
    }

    /// Dispatch a podcast.inbox action body through the app-local typed byte doorway.
    /// Builds the `podcast.inbox` `DispatchEnvelope` bytes for the byte doorway.
    fun podcastInboxJson(
        correlationId: String,
        json: String,
    ): ByteArray {
        val fbb = FlatBufferBuilder()
        val jsonOffset = fbb.createString(json)
        fbb.startTable(2)
        fbb.addInt(0, 1, 0) // slot 0: schema_version
        fbb.addOffset(1, jsonOffset, 0) // slot 1: json
        val payloadRoot = fbb.endTable()
        fbb.finish(payloadRoot, "PJSN")
        val payload = fbb.sizedByteArray()
        return encodeDispatchEnvelope(
            correlationId = correlationId,
            actionNamespace = "podcast.inbox",
            payload = payload,
        )
    }

    /// Dispatch a podcast.knowledge action body through the app-local typed byte doorway.
    /// Builds the `podcast.knowledge` `DispatchEnvelope` bytes for the byte doorway.
    fun podcastKnowledgeJson(
        correlationId: String,
        json: String,
    ): ByteArray {
        val fbb = FlatBufferBuilder()
        val jsonOffset = fbb.createString(json)
        fbb.startTable(2)
        fbb.addInt(0, 1, 0) // slot 0: schema_version
        fbb.addOffset(1, jsonOffset, 0) // slot 1: json
        val payloadRoot = fbb.endTable()
        fbb.finish(payloadRoot, "PJSN")
        val payload = fbb.sizedByteArray()
        return encodeDispatchEnvelope(
            correlationId = correlationId,
            actionNamespace = "podcast.knowledge",
            payload = payload,
        )
    }

    /// Dispatch a podcast.memory action body through the app-local typed byte doorway.
    /// Builds the `podcast.memory` `DispatchEnvelope` bytes for the byte doorway.
    fun podcastMemoryJson(
        correlationId: String,
        json: String,
    ): ByteArray {
        val fbb = FlatBufferBuilder()
        val jsonOffset = fbb.createString(json)
        fbb.startTable(2)
        fbb.addInt(0, 1, 0) // slot 0: schema_version
        fbb.addOffset(1, jsonOffset, 0) // slot 1: json
        val payloadRoot = fbb.endTable()
        fbb.finish(payloadRoot, "PJSN")
        val payload = fbb.sizedByteArray()
        return encodeDispatchEnvelope(
            correlationId = correlationId,
            actionNamespace = "podcast.memory",
            payload = payload,
        )
    }

    /// Dispatch a podcast.picks action body through the app-local typed byte doorway.
    /// Builds the `podcast.picks` `DispatchEnvelope` bytes for the byte doorway.
    fun podcastPicksJson(
        correlationId: String,
        json: String,
    ): ByteArray {
        val fbb = FlatBufferBuilder()
        val jsonOffset = fbb.createString(json)
        fbb.startTable(2)
        fbb.addInt(0, 1, 0) // slot 0: schema_version
        fbb.addOffset(1, jsonOffset, 0) // slot 1: json
        val payloadRoot = fbb.endTable()
        fbb.finish(payloadRoot, "PJSN")
        val payload = fbb.sizedByteArray()
        return encodeDispatchEnvelope(
            correlationId = correlationId,
            actionNamespace = "podcast.picks",
            payload = payload,
        )
    }

    /// Dispatch a podcast.player action body through the app-local typed byte doorway.
    /// Builds the `podcast.player` `DispatchEnvelope` bytes for the byte doorway.
    fun podcastPlayerJson(
        correlationId: String,
        json: String,
    ): ByteArray {
        val fbb = FlatBufferBuilder()
        val jsonOffset = fbb.createString(json)
        fbb.startTable(2)
        fbb.addInt(0, 1, 0) // slot 0: schema_version
        fbb.addOffset(1, jsonOffset, 0) // slot 1: json
        val payloadRoot = fbb.endTable()
        fbb.finish(payloadRoot, "PJSN")
        val payload = fbb.sizedByteArray()
        return encodeDispatchEnvelope(
            correlationId = correlationId,
            actionNamespace = "podcast.player",
            payload = payload,
        )
    }

    /// Dispatch a podcast.publish action body through the app-local typed byte doorway.
    /// Builds the `podcast.publish` `DispatchEnvelope` bytes for the byte doorway.
    fun podcastPublishJson(
        correlationId: String,
        json: String,
    ): ByteArray {
        val fbb = FlatBufferBuilder()
        val jsonOffset = fbb.createString(json)
        fbb.startTable(2)
        fbb.addInt(0, 1, 0) // slot 0: schema_version
        fbb.addOffset(1, jsonOffset, 0) // slot 1: json
        val payloadRoot = fbb.endTable()
        fbb.finish(payloadRoot, "PJSN")
        val payload = fbb.sizedByteArray()
        return encodeDispatchEnvelope(
            correlationId = correlationId,
            actionNamespace = "podcast.publish",
            payload = payload,
        )
    }

    /// Dispatch a podcast.queue action body through the app-local typed byte doorway.
    /// Builds the `podcast.queue` `DispatchEnvelope` bytes for the byte doorway.
    fun podcastQueueJson(
        correlationId: String,
        json: String,
    ): ByteArray {
        val fbb = FlatBufferBuilder()
        val jsonOffset = fbb.createString(json)
        fbb.startTable(2)
        fbb.addInt(0, 1, 0) // slot 0: schema_version
        fbb.addOffset(1, jsonOffset, 0) // slot 1: json
        val payloadRoot = fbb.endTable()
        fbb.finish(payloadRoot, "PJSN")
        val payload = fbb.sizedByteArray()
        return encodeDispatchEnvelope(
            correlationId = correlationId,
            actionNamespace = "podcast.queue",
            payload = payload,
        )
    }

    /// Dispatch a podcast.settings action body through the app-local typed byte doorway.
    /// Builds the `podcast.settings` `DispatchEnvelope` bytes for the byte doorway.
    fun podcastSettingsJson(
        correlationId: String,
        json: String,
    ): ByteArray {
        val fbb = FlatBufferBuilder()
        val jsonOffset = fbb.createString(json)
        fbb.startTable(2)
        fbb.addInt(0, 1, 0) // slot 0: schema_version
        fbb.addOffset(1, jsonOffset, 0) // slot 1: json
        val payloadRoot = fbb.endTable()
        fbb.finish(payloadRoot, "PJSN")
        val payload = fbb.sizedByteArray()
        return encodeDispatchEnvelope(
            correlationId = correlationId,
            actionNamespace = "podcast.settings",
            payload = payload,
        )
    }

    /// Dispatch a podcast.siri action body through the app-local typed byte doorway.
    /// Builds the `podcast.siri` `DispatchEnvelope` bytes for the byte doorway.
    fun podcastSiriJson(
        correlationId: String,
        json: String,
    ): ByteArray {
        val fbb = FlatBufferBuilder()
        val jsonOffset = fbb.createString(json)
        fbb.startTable(2)
        fbb.addInt(0, 1, 0) // slot 0: schema_version
        fbb.addOffset(1, jsonOffset, 0) // slot 1: json
        val payloadRoot = fbb.endTable()
        fbb.finish(payloadRoot, "PJSN")
        val payload = fbb.sizedByteArray()
        return encodeDispatchEnvelope(
            correlationId = correlationId,
            actionNamespace = "podcast.siri",
            payload = payload,
        )
    }

    /// Dispatch a podcast.social action body through the app-local typed byte doorway.
    /// Builds the `podcast.social` `DispatchEnvelope` bytes for the byte doorway.
    fun podcastSocialJson(
        correlationId: String,
        json: String,
    ): ByteArray {
        val fbb = FlatBufferBuilder()
        val jsonOffset = fbb.createString(json)
        fbb.startTable(2)
        fbb.addInt(0, 1, 0) // slot 0: schema_version
        fbb.addOffset(1, jsonOffset, 0) // slot 1: json
        val payloadRoot = fbb.endTable()
        fbb.finish(payloadRoot, "PJSN")
        val payload = fbb.sizedByteArray()
        return encodeDispatchEnvelope(
            correlationId = correlationId,
            actionNamespace = "podcast.social",
            payload = payload,
        )
    }

    /// Dispatch a podcast.tasks action body through the app-local typed byte doorway.
    /// Builds the `podcast.tasks` `DispatchEnvelope` bytes for the byte doorway.
    fun podcastTasksJson(
        correlationId: String,
        json: String,
    ): ByteArray {
        val fbb = FlatBufferBuilder()
        val jsonOffset = fbb.createString(json)
        fbb.startTable(2)
        fbb.addInt(0, 1, 0) // slot 0: schema_version
        fbb.addOffset(1, jsonOffset, 0) // slot 1: json
        val payloadRoot = fbb.endTable()
        fbb.finish(payloadRoot, "PJSN")
        val payload = fbb.sizedByteArray()
        return encodeDispatchEnvelope(
            correlationId = correlationId,
            actionNamespace = "podcast.tasks",
            payload = payload,
        )
    }

    /// Dispatch a podcast.voice action body through the app-local typed byte doorway.
    /// Builds the `podcast.voice` `DispatchEnvelope` bytes for the byte doorway.
    fun podcastVoiceJson(
        correlationId: String,
        json: String,
    ): ByteArray {
        val fbb = FlatBufferBuilder()
        val jsonOffset = fbb.createString(json)
        fbb.startTable(2)
        fbb.addInt(0, 1, 0) // slot 0: schema_version
        fbb.addOffset(1, jsonOffset, 0) // slot 1: json
        val payloadRoot = fbb.endTable()
        fbb.finish(payloadRoot, "PJSN")
        val payload = fbb.sizedByteArray()
        return encodeDispatchEnvelope(
            correlationId = correlationId,
            actionNamespace = "podcast.voice",
            payload = payload,
        )
    }
}
