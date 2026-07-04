// GENERATED. DO NOT EDIT BY HAND.
//
// Regenerate via:
//   cargo run -p nmp-codegen -- gen action-builders --registry <app>/action-builders.json \
//       --platform swift --out <output>
//
// Source of truth: app-local action-builders registry JSON passed via
// `--registry`. NOT NMP's built-in `ACTION_BUILDERS` table.

import FlatBuffers
import Foundation

public enum GeneratedActionBuilders {
    public enum PublishSignerProvenance: String {
        case appManaged = "app_managed"
        case userSelected = "user_selected"
        case protocolPinned = "protocol_pinned"
        case diagnostic = "diagnostic"
    }

    public enum PublishSignerSelection {
        case active
        case registered(pubkey: String, provenance: PublishSignerProvenance)
    }

    public enum PublishRouteClass: String {
        case manualOverride = "manual_override"
        case groupHostPin = "group_host_pin"
        case verifiedPrivateInbox = "verified_private_inbox"
        case importedOrPresigned = "imported_or_presigned"
        case diagnostic = "diagnostic"
    }

    public enum PublishTargetSelection {
        case auto
        case explicit(relays: [String], routeClass: PublishRouteClass)
    }

    /// The single recognised envelope schema version — mirrors
    /// `nmp_core::dispatch_envelope::DISPATCH_ENVELOPE_SCHEMA_VERSION`.
    public static let dispatchEnvelopeSchemaVersion: UInt32 = 1

    /// Stamp `(correlationId, actionNamespace, schemaVersion, payload)` into a
    /// `DispatchEnvelope` and return the finished bytes (file identifier `NMPD`).
    /// The byte-for-byte twin of `encode_dispatch_envelope` in `nmp-core`.
    private static func encodeDispatchEnvelope(
        correlationId: String,
        actionNamespace: String,
        payload: [UInt8]
    ) -> [UInt8] {
        var fbb = FlatBufferBuilder()
        let correlationOffset = fbb.create(string: correlationId)
        let namespaceOffset = fbb.create(string: actionNamespace)
        let payloadOffset = fbb.createVector(payload)
        let start = fbb.startTable(with: 4)
        fbb.add(offset: correlationOffset, at: 4)   // slot 0: correlation_id
        fbb.add(offset: namespaceOffset, at: 6)     // slot 1: action_namespace
        fbb.add(element: dispatchEnvelopeSchemaVersion, def: UInt32(0), at: 8) // slot 2: schema_version
        fbb.add(offset: payloadOffset, at: 10)      // slot 3: payload
        let root = Offset(offset: fbb.endTable(at: start))
        fbb.finish(offset: root, fileId: "NMPD")
        return fbb.sizedByteArray
    }

    /// Map a relay role string to the RelayMarker ubyte (Both=0, Read=1, Write=2, Indexer=3),
    /// mirroring `RelayMarker::from_role_string` in `nmp-router` EXACTLY — including rejection.
    /// Unknown tokens or no-flag input (e.g. empty string) encode as 255 (out-of-range sentinel)
    /// so the Rust decoder (`marker_from_wire`) fails closed instead of silently becoming Both.
    /// Role strings may be comma-separated (e.g. `"both,indexer"`); comparisons are case-insensitive.
    private static func relayMarkerByte(_ role: String) -> UInt8 {
        var hasBoth = false; var hasRead = false; var hasWrite = false; var hasIndexer = false
        var invalid = false
        for part in role.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
            switch part {
            case "": break
            case "both": hasBoth = true
            case "read": hasRead = true
            case "write": hasWrite = true
            case "indexer": hasIndexer = true
            default: invalid = true
            }
        }
        if invalid { return 255 }
        if hasBoth || (hasRead && hasWrite) { return 0 }
        if hasRead { return 1 }
        if hasWrite { return 2 }
        if hasIndexer { return 3 }
        return 255
    }

    /// Dispatch a root podcast action body through the app-local typed byte doorway.
    /// Builds the `podcast` `DispatchEnvelope` bytes for the byte doorway.
    public static func podcastJson(
        correlationId: String,
        json: String
    ) -> [UInt8] {
        var fbb = FlatBufferBuilder()
        let jsonOffset = fbb.create(string: json)
        let payloadStart = fbb.startTable(with: 2)
        fbb.add(element: UInt32(1), def: UInt32(0), at: 4) // slot 0: schema_version
        fbb.add(offset: jsonOffset, at: 6) // slot 1: json
        let payloadRoot = Offset(offset: fbb.endTable(at: payloadStart))
        fbb.finish(offset: payloadRoot, fileId: "PJSN")
        let payload = fbb.sizedByteArray
        return encodeDispatchEnvelope(
            correlationId: correlationId,
            actionNamespace: "podcast",
            payload: payload
        )
    }

    /// Dispatch a podcast.agent action body through the app-local typed byte doorway.
    /// Builds the `podcast.agent` `DispatchEnvelope` bytes for the byte doorway.
    public static func podcastAgentJson(
        correlationId: String,
        json: String
    ) -> [UInt8] {
        var fbb = FlatBufferBuilder()
        let jsonOffset = fbb.create(string: json)
        let payloadStart = fbb.startTable(with: 2)
        fbb.add(element: UInt32(1), def: UInt32(0), at: 4) // slot 0: schema_version
        fbb.add(offset: jsonOffset, at: 6) // slot 1: json
        let payloadRoot = Offset(offset: fbb.endTable(at: payloadStart))
        fbb.finish(offset: payloadRoot, fileId: "PJSN")
        let payload = fbb.sizedByteArray
        return encodeDispatchEnvelope(
            correlationId: correlationId,
            actionNamespace: "podcast.agent",
            payload: payload
        )
    }

    /// Dispatch a podcast.categorize action body through the app-local typed byte doorway.
    /// Builds the `podcast.categorize` `DispatchEnvelope` bytes for the byte doorway.
    public static func podcastCategorizeJson(
        correlationId: String,
        json: String
    ) -> [UInt8] {
        var fbb = FlatBufferBuilder()
        let jsonOffset = fbb.create(string: json)
        let payloadStart = fbb.startTable(with: 2)
        fbb.add(element: UInt32(1), def: UInt32(0), at: 4) // slot 0: schema_version
        fbb.add(offset: jsonOffset, at: 6) // slot 1: json
        let payloadRoot = Offset(offset: fbb.endTable(at: payloadStart))
        fbb.finish(offset: payloadRoot, fileId: "PJSN")
        let payload = fbb.sizedByteArray
        return encodeDispatchEnvelope(
            correlationId: correlationId,
            actionNamespace: "podcast.categorize",
            payload: payload
        )
    }

    /// Dispatch a podcast.chapters action body through the app-local typed byte doorway.
    /// Builds the `podcast.chapters` `DispatchEnvelope` bytes for the byte doorway.
    public static func podcastChaptersJson(
        correlationId: String,
        json: String
    ) -> [UInt8] {
        var fbb = FlatBufferBuilder()
        let jsonOffset = fbb.create(string: json)
        let payloadStart = fbb.startTable(with: 2)
        fbb.add(element: UInt32(1), def: UInt32(0), at: 4) // slot 0: schema_version
        fbb.add(offset: jsonOffset, at: 6) // slot 1: json
        let payloadRoot = Offset(offset: fbb.endTable(at: payloadStart))
        fbb.finish(offset: payloadRoot, fileId: "PJSN")
        let payload = fbb.sizedByteArray
        return encodeDispatchEnvelope(
            correlationId: correlationId,
            actionNamespace: "podcast.chapters",
            payload: payload
        )
    }

    /// Dispatch a podcast.clip action body through the app-local typed byte doorway.
    /// Builds the `podcast.clip` `DispatchEnvelope` bytes for the byte doorway.
    public static func podcastClipJson(
        correlationId: String,
        json: String
    ) -> [UInt8] {
        var fbb = FlatBufferBuilder()
        let jsonOffset = fbb.create(string: json)
        let payloadStart = fbb.startTable(with: 2)
        fbb.add(element: UInt32(1), def: UInt32(0), at: 4) // slot 0: schema_version
        fbb.add(offset: jsonOffset, at: 6) // slot 1: json
        let payloadRoot = Offset(offset: fbb.endTable(at: payloadStart))
        fbb.finish(offset: payloadRoot, fileId: "PJSN")
        let payload = fbb.sizedByteArray
        return encodeDispatchEnvelope(
            correlationId: correlationId,
            actionNamespace: "podcast.clip",
            payload: payload
        )
    }

    /// Dispatch a podcast.identity action body through the app-local typed byte doorway.
    /// Builds the `podcast.identity` `DispatchEnvelope` bytes for the byte doorway.
    public static func podcastIdentityJson(
        correlationId: String,
        json: String
    ) -> [UInt8] {
        var fbb = FlatBufferBuilder()
        let jsonOffset = fbb.create(string: json)
        let payloadStart = fbb.startTable(with: 2)
        fbb.add(element: UInt32(1), def: UInt32(0), at: 4) // slot 0: schema_version
        fbb.add(offset: jsonOffset, at: 6) // slot 1: json
        let payloadRoot = Offset(offset: fbb.endTable(at: payloadStart))
        fbb.finish(offset: payloadRoot, fileId: "PJSN")
        let payload = fbb.sizedByteArray
        return encodeDispatchEnvelope(
            correlationId: correlationId,
            actionNamespace: "podcast.identity",
            payload: payload
        )
    }

    /// Dispatch a podcast.inbox action body through the app-local typed byte doorway.
    /// Builds the `podcast.inbox` `DispatchEnvelope` bytes for the byte doorway.
    public static func podcastInboxJson(
        correlationId: String,
        json: String
    ) -> [UInt8] {
        var fbb = FlatBufferBuilder()
        let jsonOffset = fbb.create(string: json)
        let payloadStart = fbb.startTable(with: 2)
        fbb.add(element: UInt32(1), def: UInt32(0), at: 4) // slot 0: schema_version
        fbb.add(offset: jsonOffset, at: 6) // slot 1: json
        let payloadRoot = Offset(offset: fbb.endTable(at: payloadStart))
        fbb.finish(offset: payloadRoot, fileId: "PJSN")
        let payload = fbb.sizedByteArray
        return encodeDispatchEnvelope(
            correlationId: correlationId,
            actionNamespace: "podcast.inbox",
            payload: payload
        )
    }

    /// Dispatch a podcast.knowledge action body through the app-local typed byte doorway.
    /// Builds the `podcast.knowledge` `DispatchEnvelope` bytes for the byte doorway.
    public static func podcastKnowledgeJson(
        correlationId: String,
        json: String
    ) -> [UInt8] {
        var fbb = FlatBufferBuilder()
        let jsonOffset = fbb.create(string: json)
        let payloadStart = fbb.startTable(with: 2)
        fbb.add(element: UInt32(1), def: UInt32(0), at: 4) // slot 0: schema_version
        fbb.add(offset: jsonOffset, at: 6) // slot 1: json
        let payloadRoot = Offset(offset: fbb.endTable(at: payloadStart))
        fbb.finish(offset: payloadRoot, fileId: "PJSN")
        let payload = fbb.sizedByteArray
        return encodeDispatchEnvelope(
            correlationId: correlationId,
            actionNamespace: "podcast.knowledge",
            payload: payload
        )
    }

    /// Dispatch a podcast.memory action body through the app-local typed byte doorway.
    /// Builds the `podcast.memory` `DispatchEnvelope` bytes for the byte doorway.
    public static func podcastMemoryJson(
        correlationId: String,
        json: String
    ) -> [UInt8] {
        var fbb = FlatBufferBuilder()
        let jsonOffset = fbb.create(string: json)
        let payloadStart = fbb.startTable(with: 2)
        fbb.add(element: UInt32(1), def: UInt32(0), at: 4) // slot 0: schema_version
        fbb.add(offset: jsonOffset, at: 6) // slot 1: json
        let payloadRoot = Offset(offset: fbb.endTable(at: payloadStart))
        fbb.finish(offset: payloadRoot, fileId: "PJSN")
        let payload = fbb.sizedByteArray
        return encodeDispatchEnvelope(
            correlationId: correlationId,
            actionNamespace: "podcast.memory",
            payload: payload
        )
    }

    /// Dispatch a podcast.picks action body through the app-local typed byte doorway.
    /// Builds the `podcast.picks` `DispatchEnvelope` bytes for the byte doorway.
    public static func podcastPicksJson(
        correlationId: String,
        json: String
    ) -> [UInt8] {
        var fbb = FlatBufferBuilder()
        let jsonOffset = fbb.create(string: json)
        let payloadStart = fbb.startTable(with: 2)
        fbb.add(element: UInt32(1), def: UInt32(0), at: 4) // slot 0: schema_version
        fbb.add(offset: jsonOffset, at: 6) // slot 1: json
        let payloadRoot = Offset(offset: fbb.endTable(at: payloadStart))
        fbb.finish(offset: payloadRoot, fileId: "PJSN")
        let payload = fbb.sizedByteArray
        return encodeDispatchEnvelope(
            correlationId: correlationId,
            actionNamespace: "podcast.picks",
            payload: payload
        )
    }

    /// Dispatch a podcast.player action body through the app-local typed byte doorway.
    /// Builds the `podcast.player` `DispatchEnvelope` bytes for the byte doorway.
    public static func podcastPlayerJson(
        correlationId: String,
        json: String
    ) -> [UInt8] {
        var fbb = FlatBufferBuilder()
        let jsonOffset = fbb.create(string: json)
        let payloadStart = fbb.startTable(with: 2)
        fbb.add(element: UInt32(1), def: UInt32(0), at: 4) // slot 0: schema_version
        fbb.add(offset: jsonOffset, at: 6) // slot 1: json
        let payloadRoot = Offset(offset: fbb.endTable(at: payloadStart))
        fbb.finish(offset: payloadRoot, fileId: "PJSN")
        let payload = fbb.sizedByteArray
        return encodeDispatchEnvelope(
            correlationId: correlationId,
            actionNamespace: "podcast.player",
            payload: payload
        )
    }

    /// Dispatch a podcast.publish action body through the app-local typed byte doorway.
    /// Builds the `podcast.publish` `DispatchEnvelope` bytes for the byte doorway.
    public static func podcastPublishJson(
        correlationId: String,
        json: String
    ) -> [UInt8] {
        var fbb = FlatBufferBuilder()
        let jsonOffset = fbb.create(string: json)
        let payloadStart = fbb.startTable(with: 2)
        fbb.add(element: UInt32(1), def: UInt32(0), at: 4) // slot 0: schema_version
        fbb.add(offset: jsonOffset, at: 6) // slot 1: json
        let payloadRoot = Offset(offset: fbb.endTable(at: payloadStart))
        fbb.finish(offset: payloadRoot, fileId: "PJSN")
        let payload = fbb.sizedByteArray
        return encodeDispatchEnvelope(
            correlationId: correlationId,
            actionNamespace: "podcast.publish",
            payload: payload
        )
    }

    /// Dispatch a podcast.queue action body through the app-local typed byte doorway.
    /// Builds the `podcast.queue` `DispatchEnvelope` bytes for the byte doorway.
    public static func podcastQueueJson(
        correlationId: String,
        json: String
    ) -> [UInt8] {
        var fbb = FlatBufferBuilder()
        let jsonOffset = fbb.create(string: json)
        let payloadStart = fbb.startTable(with: 2)
        fbb.add(element: UInt32(1), def: UInt32(0), at: 4) // slot 0: schema_version
        fbb.add(offset: jsonOffset, at: 6) // slot 1: json
        let payloadRoot = Offset(offset: fbb.endTable(at: payloadStart))
        fbb.finish(offset: payloadRoot, fileId: "PJSN")
        let payload = fbb.sizedByteArray
        return encodeDispatchEnvelope(
            correlationId: correlationId,
            actionNamespace: "podcast.queue",
            payload: payload
        )
    }

    /// Dispatch a podcast.settings action body through the app-local typed byte doorway.
    /// Builds the `podcast.settings` `DispatchEnvelope` bytes for the byte doorway.
    public static func podcastSettingsJson(
        correlationId: String,
        json: String
    ) -> [UInt8] {
        var fbb = FlatBufferBuilder()
        let jsonOffset = fbb.create(string: json)
        let payloadStart = fbb.startTable(with: 2)
        fbb.add(element: UInt32(1), def: UInt32(0), at: 4) // slot 0: schema_version
        fbb.add(offset: jsonOffset, at: 6) // slot 1: json
        let payloadRoot = Offset(offset: fbb.endTable(at: payloadStart))
        fbb.finish(offset: payloadRoot, fileId: "PJSN")
        let payload = fbb.sizedByteArray
        return encodeDispatchEnvelope(
            correlationId: correlationId,
            actionNamespace: "podcast.settings",
            payload: payload
        )
    }

    /// Dispatch a podcast.siri action body through the app-local typed byte doorway.
    /// Builds the `podcast.siri` `DispatchEnvelope` bytes for the byte doorway.
    public static func podcastSiriJson(
        correlationId: String,
        json: String
    ) -> [UInt8] {
        var fbb = FlatBufferBuilder()
        let jsonOffset = fbb.create(string: json)
        let payloadStart = fbb.startTable(with: 2)
        fbb.add(element: UInt32(1), def: UInt32(0), at: 4) // slot 0: schema_version
        fbb.add(offset: jsonOffset, at: 6) // slot 1: json
        let payloadRoot = Offset(offset: fbb.endTable(at: payloadStart))
        fbb.finish(offset: payloadRoot, fileId: "PJSN")
        let payload = fbb.sizedByteArray
        return encodeDispatchEnvelope(
            correlationId: correlationId,
            actionNamespace: "podcast.siri",
            payload: payload
        )
    }

    /// Dispatch a podcast.social action body through the app-local typed byte doorway.
    /// Builds the `podcast.social` `DispatchEnvelope` bytes for the byte doorway.
    public static func podcastSocialJson(
        correlationId: String,
        json: String
    ) -> [UInt8] {
        var fbb = FlatBufferBuilder()
        let jsonOffset = fbb.create(string: json)
        let payloadStart = fbb.startTable(with: 2)
        fbb.add(element: UInt32(1), def: UInt32(0), at: 4) // slot 0: schema_version
        fbb.add(offset: jsonOffset, at: 6) // slot 1: json
        let payloadRoot = Offset(offset: fbb.endTable(at: payloadStart))
        fbb.finish(offset: payloadRoot, fileId: "PJSN")
        let payload = fbb.sizedByteArray
        return encodeDispatchEnvelope(
            correlationId: correlationId,
            actionNamespace: "podcast.social",
            payload: payload
        )
    }

    /// Dispatch a podcast.tasks action body through the app-local typed byte doorway.
    /// Builds the `podcast.tasks` `DispatchEnvelope` bytes for the byte doorway.
    public static func podcastTasksJson(
        correlationId: String,
        json: String
    ) -> [UInt8] {
        var fbb = FlatBufferBuilder()
        let jsonOffset = fbb.create(string: json)
        let payloadStart = fbb.startTable(with: 2)
        fbb.add(element: UInt32(1), def: UInt32(0), at: 4) // slot 0: schema_version
        fbb.add(offset: jsonOffset, at: 6) // slot 1: json
        let payloadRoot = Offset(offset: fbb.endTable(at: payloadStart))
        fbb.finish(offset: payloadRoot, fileId: "PJSN")
        let payload = fbb.sizedByteArray
        return encodeDispatchEnvelope(
            correlationId: correlationId,
            actionNamespace: "podcast.tasks",
            payload: payload
        )
    }

    /// Dispatch a podcast.voice action body through the app-local typed byte doorway.
    /// Builds the `podcast.voice` `DispatchEnvelope` bytes for the byte doorway.
    public static func podcastVoiceJson(
        correlationId: String,
        json: String
    ) -> [UInt8] {
        var fbb = FlatBufferBuilder()
        let jsonOffset = fbb.create(string: json)
        let payloadStart = fbb.startTable(with: 2)
        fbb.add(element: UInt32(1), def: UInt32(0), at: 4) // slot 0: schema_version
        fbb.add(offset: jsonOffset, at: 6) // slot 1: json
        let payloadRoot = Offset(offset: fbb.endTable(at: payloadStart))
        fbb.finish(offset: payloadRoot, fileId: "PJSN")
        let payload = fbb.sizedByteArray
        return encodeDispatchEnvelope(
            correlationId: correlationId,
            actionNamespace: "podcast.voice",
            payload: payload
        )
    }
}
