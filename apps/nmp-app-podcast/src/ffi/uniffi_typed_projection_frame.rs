use nmp_core::WireProjectionState;

#[derive(uniffi::Enum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum PodcastProjectionPresence {
    Changed,
    Cleared,
}

impl From<WireProjectionState> for PodcastProjectionPresence {
    fn from(value: WireProjectionState) -> Self {
        match value {
            WireProjectionState::Changed => Self::Changed,
            WireProjectionState::Cleared => Self::Cleared,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct PodcastTypedProjectionEnvelope {
    pub key: String,
    pub schema_id: String,
    pub schema_version: u32,
    pub file_identifier: String,
    pub payload: Vec<u8>,
    pub projection_rev: u64,
    pub state: PodcastProjectionPresence,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct PodcastTypedProjectionFrame {
    pub session_id: u64,
    pub snapshot_epoch: u64,
    pub envelopes: Vec<PodcastTypedProjectionEnvelope>,
}

pub(crate) fn decode_typed_projection_frame(frame: &[u8]) -> Option<PodcastTypedProjectionFrame> {
    let envelope = nmp_core::decode_snapshot_envelope(frame).ok()?;
    let rows = nmp_core::decode_snapshot_typed_projections(frame).ok()?;
    let envelopes = rows
        .into_iter()
        .filter(|row| row.schema_id.starts_with("podcast."))
        .map(|row| PodcastTypedProjectionEnvelope {
            key: row.key,
            schema_id: row.schema_id,
            schema_version: row.schema_version,
            file_identifier: row.file_identifier,
            payload: row.payload,
            projection_rev: row.projection_rev,
            state: row.state.into(),
        })
        .collect();
    Some(PodcastTypedProjectionFrame {
        session_id: envelope.session_id,
        snapshot_epoch: envelope.snapshot_epoch,
        envelopes,
    })
}
