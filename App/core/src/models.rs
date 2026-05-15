//! UniFFI record types exposed to Swift.
//!
//! Keep these stable — Swift call sites depend on field names. Add new
//! optional fields, never reorder or rename.

#[derive(Debug, Clone, uniffi::Record)]
pub struct SignedEvent {
    pub id: String,
    pub pubkey: String,
    pub created_at: i64,
    pub kind: u32,
    pub tags: Vec<Vec<String>>,
    pub content: String,
    pub sig: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct EventDraft {
    pub kind: u32,
    pub content: String,
    pub tags: Vec<Vec<String>>,
    pub created_at: Option<i64>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct GeneratedKeypair {
    pub npub: String,
    pub nsec: String,
    pub pubkey_hex: String,
    pub privkey_hex: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ProfileRecord {
    pub pubkey: String,
    pub name: Option<String>,
    pub display_name: Option<String>,
    pub picture: Option<String>,
    pub about: Option<String>,
    pub nip05: Option<String>,
    pub lud16: Option<String>,
    pub created_at: i64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct NoteAuthorRecord {
    pub pubkey: String,
    pub display_name: String,
    pub picture: Option<String>,
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum CommentAnchor {
    Episode { guid: String },
    Clip { uuid: String },
}

impl CommentAnchor {
    /// NIP-73 external content identifier (`i`/`I` tag value).
    ///
    /// Wire format MUST match `App/Sources/Domain/EpisodeComment.swift`
    /// (`CommentTarget.nip73Identifier`) so Fountain and other generic
    /// NIP-22 clients can address the same episode/clip by the same key:
    ///   * Episode: `"podcast:item:guid:<guid>"` (Podcasting 2.0 GUID form)
    ///   * Clip:    `"podcastr:clip:<uuid>"` (Podcastr-specific, lowercase)
    pub fn nip73_identifier(&self) -> String {
        match self {
            CommentAnchor::Episode { guid } => format!("podcast:item:guid:{guid}"),
            CommentAnchor::Clip { uuid } => format!("podcastr:clip:{}", uuid.to_lowercase()),
        }
    }

    /// NIP-73 `k`/`K` tag value — the `protocol:type` prefix of the
    /// identifier. Matches `CommentTarget.nip73Kind` in Swift.
    pub fn nip73_kind(&self) -> String {
        match self {
            CommentAnchor::Episode { .. } => "podcast:item:guid".to_string(),
            CommentAnchor::Clip { .. } => "podcastr:clip".to_string(),
        }
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct CommentRecord {
    pub event_id: String,
    pub author_pubkey: String,
    pub content: String,
    pub created_at: i64,
    /// NIP-73 identifier the comment is anchored to.
    pub anchor_identifier: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ThreadEventRecord {
    pub event_id: String,
    pub pubkey: String,
    pub content: String,
    pub created_at: i64,
    pub kind: u32,
    pub tags: Vec<Vec<String>>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct PodcastShowRecord {
    pub coordinate: String,
    pub pubkey: String,
    pub d_tag: String,
    pub title: String,
    pub author: String,
    pub description: String,
    pub image_url: Option<String>,
    pub categories: Vec<String>,
    pub created_at: i64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct PodcastEpisodeRecord {
    pub event_id: String,
    pub pubkey: String,
    pub d_tag: String,
    pub show_coordinate: String,
    pub title: String,
    pub description: String,
    pub audio_url: String,
    pub mime_type: Option<String>,
    pub sha256: Option<String>,
    pub size: Option<u64>,
    pub duration: Option<u64>,
    pub chapters_url: Option<String>,
    pub transcript_url: Option<String>,
    pub created_at: i64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct PeerMessageRecord {
    pub event_id: String,
    pub from_pubkey: String,
    pub to_pubkey: String,
    pub content: String,
    pub created_at: i64,
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum RelayStatus {
    Initialized,
    Pending,
    Connecting,
    Connected,
    Disconnected,
    Terminated,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct RelayDiagnostic {
    pub url: String,
    pub status: RelayStatus,
    pub ping_ms: Option<u64>,
}
