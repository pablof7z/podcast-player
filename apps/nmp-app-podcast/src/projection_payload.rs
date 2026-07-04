//! Podcast-specific read projection payloads.
//!
//! App-owned `podcast.*` projections use NMP typed sidecar transport. The
//! payload body is still the app's JSON domain frame, but the transport payload
//! itself is a FlatBuffers buffer with a stable schema id, version, and file
//! identifier so native shells can consume it through generated typed decoders.

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
#[path = "wire/generated/podcast_json_projection_generated.rs"]
mod podcast_json_projection_generated;

use nmp_core::substrate::ActionPayloadDecodeError;
use podcast_json_projection_generated::podcastr::projection as podcast_projection_fb;

#[derive(Clone, Debug)]
pub struct PodcastProjectionJsonFrame {
    pub schema_version: u32,
    pub body_json: String,
}

impl PodcastProjectionJsonFrame {
    pub const FILE_IDENTIFIER: &'static str = "PJPR";
    pub const SCHEMA_VERSION: u32 = 1;

    pub fn decode(bytes: &[u8]) -> Result<Self, ActionPayloadDecodeError> {
        if bytes.len() < 8
            || !podcast_projection_fb::podcast_projection_json_frame_buffer_has_identifier(bytes)
        {
            return Err(malformed("missing PJPR file identifier"));
        }

        let root = podcast_projection_fb::root_as_podcast_projection_json_frame(bytes)
            .map_err(|e| malformed(format!("not a valid PodcastProjectionJsonFrame: {e}")))?;

        let schema_version = root.schema_version();
        if schema_version != Self::SCHEMA_VERSION {
            return Err(ActionPayloadDecodeError::SchemaVersionMismatch {
                found: schema_version,
                expected: Self::SCHEMA_VERSION,
            });
        }

        Ok(Self {
            schema_version,
            body_json: root.json().to_string(),
        })
    }

    pub fn encode(&self) -> Vec<u8> {
        let mut fbb = flatbuffers::FlatBufferBuilder::new();
        let json = fbb.create_string(&self.body_json);
        let payload = podcast_projection_fb::PodcastProjectionJsonFrame::create(
            &mut fbb,
            &podcast_projection_fb::PodcastProjectionJsonFrameArgs {
                schema_version: self.schema_version,
                json: Some(json),
            },
        );
        podcast_projection_fb::finish_podcast_projection_json_frame_buffer(&mut fbb, payload);
        fbb.finished_data().to_vec()
    }
}

fn malformed(reason: impl Into<String>) -> ActionPayloadDecodeError {
    ActionPayloadDecodeError::Malformed {
        reason: reason.into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn podcast_projection_json_frame_round_trips_as_flatbuffer_payload() {
        let payload = PodcastProjectionJsonFrame {
            schema_version: PodcastProjectionJsonFrame::SCHEMA_VERSION,
            body_json: r#"{"rev":7,"library":[]}"#.to_string(),
        };

        let bytes = payload.encode();
        assert!(
            podcast_projection_fb::podcast_projection_json_frame_buffer_has_identifier(&bytes),
            "payload must carry the PJPR FlatBuffers identifier"
        );

        let decoded = PodcastProjectionJsonFrame::decode(&bytes).expect("PJPR projection decodes");
        assert_eq!(
            decoded.schema_version,
            PodcastProjectionJsonFrame::SCHEMA_VERSION
        );
        assert_eq!(decoded.body_json, r#"{"rev":7,"library":[]}"#);
    }
}
