//! Podcast-specific action payloads (FlatBuffers ADR-0064 contract).
//!
//! The current app-owned action modules still deserialize JSON bodies, but the
//! native boundary no longer passes raw JSON. Hosts build a generated
//! `DispatchEnvelope` whose payload is this FlatBuffers table; Rust verifies the
//! file identifier + schema version before handing the JSON string to the
//! app-owned action module.

#[allow(
    clippy::all,
    dead_code,
    deprecated,
    missing_docs,
    non_camel_case_types,
    non_snake_case,
    unsafe_code,
    unused_imports
)]
#[path = "wire/generated/podcast_json_action_generated.rs"]
mod podcast_json_action_generated;

use nmp_core::substrate::{ActionPayload, ActionPayloadDecodeError};
use podcast_json_action_generated::podcastr::action as podcast_json_fb;

/// A generic FlatBuffers-backed payload for podcast actions.
/// Carries a schema version and opaque JSON body.
#[derive(Clone, Debug)]
pub struct PodcastJsonPayload {
    pub schema_version: u32,
    pub body_json: String,
}

impl ActionPayload for PodcastJsonPayload {
    const SCHEMA_ID: &'static str = "podcast.json_passthrough";
    const SCHEMA_VERSION: u32 = 1;

    fn decode(bytes: &[u8]) -> Result<Self, ActionPayloadDecodeError> {
        if bytes.len() < 8 || !podcast_json_fb::podcast_json_payload_buffer_has_identifier(bytes) {
            return Err(malformed("missing PJSN file identifier"));
        }

        let root = podcast_json_fb::root_as_podcast_json_payload(bytes)
            .map_err(|e| malformed(format!("not a valid PodcastJsonPayload buffer: {e}")))?;

        let schema_version = root.schema_version();
        if schema_version != Self::SCHEMA_VERSION {
            return Err(ActionPayloadDecodeError::SchemaVersionMismatch {
                found: schema_version,
                expected: Self::SCHEMA_VERSION,
            });
        }

        Ok(PodcastJsonPayload {
            schema_version,
            body_json: root.json().to_string(),
        })
    }

    fn encode(&self) -> Vec<u8> {
        let mut fbb = flatbuffers::FlatBufferBuilder::new();
        let json = fbb.create_string(&self.body_json);
        let payload = podcast_json_fb::PodcastJsonPayload::create(
            &mut fbb,
            &podcast_json_fb::PodcastJsonPayloadArgs {
                schema_version: self.schema_version,
                json: Some(json),
            },
        );
        podcast_json_fb::finish_podcast_json_payload_buffer(&mut fbb, payload);
        fbb.finished_data().to_vec()
    }
}

fn malformed(reason: impl Into<String>) -> ActionPayloadDecodeError {
    ActionPayloadDecodeError::Malformed {
        reason: reason.into(),
    }
}

/// Decode a `PodcastJsonPayload` buffer into a concrete action type `A`.
///
/// This is the canonical `ActionModule::decode_payload` body for all
/// podcast-namespace modules: decode the typed buffer as a
/// [`PodcastJsonPayload`], then JSON-deserialize `body_json` into `A`.
/// Always returns `Some(_)` — podcast modules are typed-payload-capable
/// (ADR-0064 / S3 #1751).
pub fn decode_podcast_payload<A: serde::de::DeserializeOwned>(
    bytes: &[u8],
) -> Option<Result<A, ActionPayloadDecodeError>> {
    Some(
        <PodcastJsonPayload as ActionPayload>::decode(bytes).and_then(|p| {
            serde_json::from_str::<A>(&p.body_json).map_err(|e| {
                ActionPayloadDecodeError::Malformed {
                    reason: format!("failed to deserialize action: {e}"),
                }
            })
        }),
    )
}

/// Macro to implement `ActionPayload` for a podcast action type.
/// Deserializes `body_json` from `PodcastJsonPayload` into the target type.
#[macro_export]
macro_rules! impl_podcast_action_payload {
    ($action_ty:ty, $schema_id:literal, $version:expr) => {
        impl $crate::nmp_core::substrate::ActionPayload for $action_ty {
            const SCHEMA_ID: &'static str = $schema_id;
            const SCHEMA_VERSION: u32 = $version;

            fn decode(
                bytes: &[u8],
            ) -> Result<Self, $crate::nmp_core::substrate::ActionPayloadDecodeError> {
                let payload = $crate::action_payload::PodcastJsonPayload::decode(bytes)?;
                serde_json::from_str::<Self>(&payload.body_json).map_err(|e| {
                    $crate::nmp_core::substrate::ActionPayloadDecodeError::Malformed {
                        reason: format!("failed to deserialize action JSON: {}", e),
                    }
                })
            }

            fn encode(&self) -> Vec<u8> {
                let body_json = serde_json::to_string(self).unwrap_or_default();
                let payload = $crate::action_payload::PodcastJsonPayload {
                    schema_version: Self::SCHEMA_VERSION,
                    body_json,
                };
                payload.encode()
            }
        }
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn podcast_json_payload_round_trips_as_flatbuffers_payload() {
        let payload = PodcastJsonPayload {
            schema_version: PodcastJsonPayload::SCHEMA_VERSION,
            body_json: r#"{"op":"pause"}"#.to_string(),
        };

        let bytes = payload.encode();
        assert!(
            podcast_json_fb::podcast_json_payload_buffer_has_identifier(&bytes),
            "payload must carry the PJSN FlatBuffers identifier"
        );

        let decoded = PodcastJsonPayload::decode(&bytes).expect("PJSN payload decodes");
        assert_eq!(decoded.schema_version, PodcastJsonPayload::SCHEMA_VERSION);
        assert_eq!(decoded.body_json, r#"{"op":"pause"}"#);
    }

    #[test]
    fn legacy_version_prefixed_json_payload_is_rejected() {
        let mut legacy = PodcastJsonPayload::SCHEMA_VERSION.to_le_bytes().to_vec();
        legacy.extend_from_slice(br#"{"op":"pause"}"#);

        let err = PodcastJsonPayload::decode(&legacy).expect_err("legacy payload must reject");
        assert!(
            matches!(err, ActionPayloadDecodeError::Malformed { .. }),
            "legacy raw JSON payload must fail the FlatBuffers identifier gate"
        );
    }
}
