// ─────────────────────────────────────────────────────────────────────────────
// THIS FILE IS GENERATED. DO NOT EDIT BY HAND.
//
// Regenerate via:
//   cargo run -p nmp-codegen -- gen read-projections --registry apps/nmp-app-podcast/read-projections.json \
//       --platform swift-typed-decoders
//
// Source of truth: app-local read-projections registry `apps/nmp-app-podcast/read-projections.json`.
// Each enum below is the generated mechanical half of one typed sidecar
// decoder: key+schemaId lookup over [TypedProjectionEnvelope], unchecked
// getRoot(byteBuffer:) into the flatc Swift reader, then hand-written
// TypedProjectionGlue mapping into the app domain type.
// ─────────────────────────────────────────────────────────────────────────────

import FlatBuffers
import Foundation

// MARK: - TypedLibraryDecoder
// Projection `podcast.library` → typed sidecar `podcast.library` (PJPR). Domain type: `LibraryDomainFrame?`.
enum TypedLibraryDecoder {
    /// `TypedProjection.key` the producer publishes for this projection.
    static let key = "podcast.library"
    /// `TypedPayload.schema_id` carried on the sidecar buffer.
    static let schemaId = "podcast.library"
    /// FlatBuffers `file_identifier` for `podcastr_projection_PodcastProjectionJsonFrame`.
    static let fileIdentifier = "PJPR"

    /// Decode the typed `podcast.library` sidecar from the snapshot's typed-projection
    /// envelopes into the Chirp domain value. Returns `nil` when the sidecar is absent,
    /// carries the wrong schema, or is not a well-formed buffer.
    static func decode(from projections: [TypedProjectionEnvelope]) -> LibraryDomainFrame? {
        guard let projection = projections.first(where: {
            $0.key == key && $0.schemaId == schemaId
        }), !projection.payload.isEmpty else {
            return nil
        }
        return decode(bytes: projection.payload)
    }

    /// Decode a raw `PJPR` FlatBuffers buffer into the Chirp domain value.
    static func decode(bytes: Data) -> LibraryDomainFrame? {
        guard !bytes.isEmpty else { return nil }
        var buffer = ByteBuffer(data: bytes)
        let reader: podcastr_projection_PodcastProjectionJsonFrame = getRoot(byteBuffer: &buffer)
        // Hand-written glue (NOT generated): map the `flatc --swift` reader
        // struct to the Chirp domain type. See `TypedProjectionGlue.library`.
        return TypedProjectionGlue.library(reader)
    }
}

// MARK: - TypedPlaybackDecoder
// Projection `podcast.playback` → typed sidecar `podcast.playback` (PJPR). Domain type: `PlaybackDomainFrame?`.
enum TypedPlaybackDecoder {
    /// `TypedProjection.key` the producer publishes for this projection.
    static let key = "podcast.playback"
    /// `TypedPayload.schema_id` carried on the sidecar buffer.
    static let schemaId = "podcast.playback"
    /// FlatBuffers `file_identifier` for `podcastr_projection_PodcastProjectionJsonFrame`.
    static let fileIdentifier = "PJPR"

    /// Decode the typed `podcast.playback` sidecar from the snapshot's typed-projection
    /// envelopes into the Chirp domain value. Returns `nil` when the sidecar is absent,
    /// carries the wrong schema, or is not a well-formed buffer.
    static func decode(from projections: [TypedProjectionEnvelope]) -> PlaybackDomainFrame? {
        guard let projection = projections.first(where: {
            $0.key == key && $0.schemaId == schemaId
        }), !projection.payload.isEmpty else {
            return nil
        }
        return decode(bytes: projection.payload)
    }

    /// Decode a raw `PJPR` FlatBuffers buffer into the Chirp domain value.
    static func decode(bytes: Data) -> PlaybackDomainFrame? {
        guard !bytes.isEmpty else { return nil }
        var buffer = ByteBuffer(data: bytes)
        let reader: podcastr_projection_PodcastProjectionJsonFrame = getRoot(byteBuffer: &buffer)
        // Hand-written glue (NOT generated): map the `flatc --swift` reader
        // struct to the Chirp domain type. See `TypedProjectionGlue.playback`.
        return TypedProjectionGlue.playback(reader)
    }
}

// MARK: - TypedDownloadsDecoder
// Projection `podcast.downloads` → typed sidecar `podcast.downloads` (PJPR). Domain type: `DownloadsDomainFrame?`.
enum TypedDownloadsDecoder {
    /// `TypedProjection.key` the producer publishes for this projection.
    static let key = "podcast.downloads"
    /// `TypedPayload.schema_id` carried on the sidecar buffer.
    static let schemaId = "podcast.downloads"
    /// FlatBuffers `file_identifier` for `podcastr_projection_PodcastProjectionJsonFrame`.
    static let fileIdentifier = "PJPR"

    /// Decode the typed `podcast.downloads` sidecar from the snapshot's typed-projection
    /// envelopes into the Chirp domain value. Returns `nil` when the sidecar is absent,
    /// carries the wrong schema, or is not a well-formed buffer.
    static func decode(from projections: [TypedProjectionEnvelope]) -> DownloadsDomainFrame? {
        guard let projection = projections.first(where: {
            $0.key == key && $0.schemaId == schemaId
        }), !projection.payload.isEmpty else {
            return nil
        }
        return decode(bytes: projection.payload)
    }

    /// Decode a raw `PJPR` FlatBuffers buffer into the Chirp domain value.
    static func decode(bytes: Data) -> DownloadsDomainFrame? {
        guard !bytes.isEmpty else { return nil }
        var buffer = ByteBuffer(data: bytes)
        let reader: podcastr_projection_PodcastProjectionJsonFrame = getRoot(byteBuffer: &buffer)
        // Hand-written glue (NOT generated): map the `flatc --swift` reader
        // struct to the Chirp domain type. See `TypedProjectionGlue.downloads`.
        return TypedProjectionGlue.downloads(reader)
    }
}

// MARK: - TypedSettingsDecoder
// Projection `podcast.settings` → typed sidecar `podcast.settings` (PJPR). Domain type: `SettingsDomainFrame?`.
enum TypedSettingsDecoder {
    /// `TypedProjection.key` the producer publishes for this projection.
    static let key = "podcast.settings"
    /// `TypedPayload.schema_id` carried on the sidecar buffer.
    static let schemaId = "podcast.settings"
    /// FlatBuffers `file_identifier` for `podcastr_projection_PodcastProjectionJsonFrame`.
    static let fileIdentifier = "PJPR"

    /// Decode the typed `podcast.settings` sidecar from the snapshot's typed-projection
    /// envelopes into the Chirp domain value. Returns `nil` when the sidecar is absent,
    /// carries the wrong schema, or is not a well-formed buffer.
    static func decode(from projections: [TypedProjectionEnvelope]) -> SettingsDomainFrame? {
        guard let projection = projections.first(where: {
            $0.key == key && $0.schemaId == schemaId
        }), !projection.payload.isEmpty else {
            return nil
        }
        return decode(bytes: projection.payload)
    }

    /// Decode a raw `PJPR` FlatBuffers buffer into the Chirp domain value.
    static func decode(bytes: Data) -> SettingsDomainFrame? {
        guard !bytes.isEmpty else { return nil }
        var buffer = ByteBuffer(data: bytes)
        let reader: podcastr_projection_PodcastProjectionJsonFrame = getRoot(byteBuffer: &buffer)
        // Hand-written glue (NOT generated): map the `flatc --swift` reader
        // struct to the Chirp domain type. See `TypedProjectionGlue.settings`.
        return TypedProjectionGlue.settings(reader)
    }
}

// MARK: - TypedIdentityDecoder
// Projection `podcast.identity` → typed sidecar `podcast.identity` (PJPR). Domain type: `IdentityDomainFrame?`.
enum TypedIdentityDecoder {
    /// `TypedProjection.key` the producer publishes for this projection.
    static let key = "podcast.identity"
    /// `TypedPayload.schema_id` carried on the sidecar buffer.
    static let schemaId = "podcast.identity"
    /// FlatBuffers `file_identifier` for `podcastr_projection_PodcastProjectionJsonFrame`.
    static let fileIdentifier = "PJPR"

    /// Decode the typed `podcast.identity` sidecar from the snapshot's typed-projection
    /// envelopes into the Chirp domain value. Returns `nil` when the sidecar is absent,
    /// carries the wrong schema, or is not a well-formed buffer.
    static func decode(from projections: [TypedProjectionEnvelope]) -> IdentityDomainFrame? {
        guard let projection = projections.first(where: {
            $0.key == key && $0.schemaId == schemaId
        }), !projection.payload.isEmpty else {
            return nil
        }
        return decode(bytes: projection.payload)
    }

    /// Decode a raw `PJPR` FlatBuffers buffer into the Chirp domain value.
    static func decode(bytes: Data) -> IdentityDomainFrame? {
        guard !bytes.isEmpty else { return nil }
        var buffer = ByteBuffer(data: bytes)
        let reader: podcastr_projection_PodcastProjectionJsonFrame = getRoot(byteBuffer: &buffer)
        // Hand-written glue (NOT generated): map the `flatc --swift` reader
        // struct to the Chirp domain type. See `TypedProjectionGlue.identity`.
        return TypedProjectionGlue.identity(reader)
    }
}

// MARK: - TypedWidgetDecoder
// Projection `podcast.widget` → typed sidecar `podcast.widget` (PJPR). Domain type: `WidgetDomainFrame?`.
enum TypedWidgetDecoder {
    /// `TypedProjection.key` the producer publishes for this projection.
    static let key = "podcast.widget"
    /// `TypedPayload.schema_id` carried on the sidecar buffer.
    static let schemaId = "podcast.widget"
    /// FlatBuffers `file_identifier` for `podcastr_projection_PodcastProjectionJsonFrame`.
    static let fileIdentifier = "PJPR"

    /// Decode the typed `podcast.widget` sidecar from the snapshot's typed-projection
    /// envelopes into the Chirp domain value. Returns `nil` when the sidecar is absent,
    /// carries the wrong schema, or is not a well-formed buffer.
    static func decode(from projections: [TypedProjectionEnvelope]) -> WidgetDomainFrame? {
        guard let projection = projections.first(where: {
            $0.key == key && $0.schemaId == schemaId
        }), !projection.payload.isEmpty else {
            return nil
        }
        return decode(bytes: projection.payload)
    }

    /// Decode a raw `PJPR` FlatBuffers buffer into the Chirp domain value.
    static func decode(bytes: Data) -> WidgetDomainFrame? {
        guard !bytes.isEmpty else { return nil }
        var buffer = ByteBuffer(data: bytes)
        let reader: podcastr_projection_PodcastProjectionJsonFrame = getRoot(byteBuffer: &buffer)
        // Hand-written glue (NOT generated): map the `flatc --swift` reader
        // struct to the Chirp domain type. See `TypedProjectionGlue.widget`.
        return TypedProjectionGlue.widget(reader)
    }
}

// MARK: - TypedSocialDecoder
// Projection `podcast.social` → typed sidecar `podcast.social` (PJPR). Domain type: `SocialDomainFrame?`.
enum TypedSocialDecoder {
    /// `TypedProjection.key` the producer publishes for this projection.
    static let key = "podcast.social"
    /// `TypedPayload.schema_id` carried on the sidecar buffer.
    static let schemaId = "podcast.social"
    /// FlatBuffers `file_identifier` for `podcastr_projection_PodcastProjectionJsonFrame`.
    static let fileIdentifier = "PJPR"

    /// Decode the typed `podcast.social` sidecar from the snapshot's typed-projection
    /// envelopes into the Chirp domain value. Returns `nil` when the sidecar is absent,
    /// carries the wrong schema, or is not a well-formed buffer.
    static func decode(from projections: [TypedProjectionEnvelope]) -> SocialDomainFrame? {
        guard let projection = projections.first(where: {
            $0.key == key && $0.schemaId == schemaId
        }), !projection.payload.isEmpty else {
            return nil
        }
        return decode(bytes: projection.payload)
    }

    /// Decode a raw `PJPR` FlatBuffers buffer into the Chirp domain value.
    static func decode(bytes: Data) -> SocialDomainFrame? {
        guard !bytes.isEmpty else { return nil }
        var buffer = ByteBuffer(data: bytes)
        let reader: podcastr_projection_PodcastProjectionJsonFrame = getRoot(byteBuffer: &buffer)
        // Hand-written glue (NOT generated): map the `flatc --swift` reader
        // struct to the Chirp domain type. See `TypedProjectionGlue.social`.
        return TypedProjectionGlue.social(reader)
    }
}

// MARK: - TypedVoiceDecoder
// Projection `podcast.voice` → typed sidecar `podcast.voice` (PJPR). Domain type: `VoiceDomainFrame?`.
enum TypedVoiceDecoder {
    /// `TypedProjection.key` the producer publishes for this projection.
    static let key = "podcast.voice"
    /// `TypedPayload.schema_id` carried on the sidecar buffer.
    static let schemaId = "podcast.voice"
    /// FlatBuffers `file_identifier` for `podcastr_projection_PodcastProjectionJsonFrame`.
    static let fileIdentifier = "PJPR"

    /// Decode the typed `podcast.voice` sidecar from the snapshot's typed-projection
    /// envelopes into the Chirp domain value. Returns `nil` when the sidecar is absent,
    /// carries the wrong schema, or is not a well-formed buffer.
    static func decode(from projections: [TypedProjectionEnvelope]) -> VoiceDomainFrame? {
        guard let projection = projections.first(where: {
            $0.key == key && $0.schemaId == schemaId
        }), !projection.payload.isEmpty else {
            return nil
        }
        return decode(bytes: projection.payload)
    }

    /// Decode a raw `PJPR` FlatBuffers buffer into the Chirp domain value.
    static func decode(bytes: Data) -> VoiceDomainFrame? {
        guard !bytes.isEmpty else { return nil }
        var buffer = ByteBuffer(data: bytes)
        let reader: podcastr_projection_PodcastProjectionJsonFrame = getRoot(byteBuffer: &buffer)
        // Hand-written glue (NOT generated): map the `flatc --swift` reader
        // struct to the Chirp domain type. See `TypedProjectionGlue.voice`.
        return TypedProjectionGlue.voice(reader)
    }
}

// MARK: - TypedMiscDecoder
// Projection `podcast.misc` → typed sidecar `podcast.misc` (PJPR). Domain type: `MiscDomainFrame?`.
enum TypedMiscDecoder {
    /// `TypedProjection.key` the producer publishes for this projection.
    static let key = "podcast.misc"
    /// `TypedPayload.schema_id` carried on the sidecar buffer.
    static let schemaId = "podcast.misc"
    /// FlatBuffers `file_identifier` for `podcastr_projection_PodcastProjectionJsonFrame`.
    static let fileIdentifier = "PJPR"

    /// Decode the typed `podcast.misc` sidecar from the snapshot's typed-projection
    /// envelopes into the Chirp domain value. Returns `nil` when the sidecar is absent,
    /// carries the wrong schema, or is not a well-formed buffer.
    static func decode(from projections: [TypedProjectionEnvelope]) -> MiscDomainFrame? {
        guard let projection = projections.first(where: {
            $0.key == key && $0.schemaId == schemaId
        }), !projection.payload.isEmpty else {
            return nil
        }
        return decode(bytes: projection.payload)
    }

    /// Decode a raw `PJPR` FlatBuffers buffer into the Chirp domain value.
    static func decode(bytes: Data) -> MiscDomainFrame? {
        guard !bytes.isEmpty else { return nil }
        var buffer = ByteBuffer(data: bytes)
        let reader: podcastr_projection_PodcastProjectionJsonFrame = getRoot(byteBuffer: &buffer)
        // Hand-written glue (NOT generated): map the `flatc --swift` reader
        // struct to the Chirp domain type. See `TypedProjectionGlue.misc`.
        return TypedProjectionGlue.misc(reader)
    }
}
