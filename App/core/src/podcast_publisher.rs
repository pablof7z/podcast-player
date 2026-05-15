//! NIP-74 podcast publishing — port of
//! `App/Sources/Services/NostrPodcastPublisher.swift`.
//!
//! Both kinds are addressable (NIP-33): each `d` tag uniquely identifies the
//! show / episode across updates.
//!
//! Wire format parity with Swift `NostrPodcastPublisher`:
//!
//! **Show (kind:30074)**:
//!   - `d`, `title`, `author`, `summary` (description, only if non-empty),
//!     `image` (if present), `t` (one per category)
//!   - the description is also stored as the event `content` (same as Swift)
//!
//! **Episode (kind:30075)**:
//!   - `d`, `title`, `a = 30074:<pubkey>:<show_d_tag>`
//!   - `summary` (only if non-empty)
//!   - `duration` top-level (if present, seconds as string)
//!   - `imeta`: `url <audio>` always; `m <mime>`, `x <sha256>`, `size <bytes>`,
//!     `duration <sec>` each only when supplied
//!   - `chapters [url, "application/json+chapters"]` (if present)
//!   - `transcript [url, "text/vtt"]` (if present)
//!
//! The Rust API does not (yet) accept `published_at` or `image` for episodes;
//! Swift emits both. They can be added as further optional params without
//! breaking callers.
//!
//! Multi-relay delivery: `Client::send_event` natively broadcasts to every
//! relay in the pool with the WRITE flag. We succeed if at least one relay
//! accepts the event; otherwise we surface a `Relay` error.

use nostr_sdk::prelude::*;

use crate::client::PodcastrCore;
use crate::errors::CoreError;
use crate::models::SignedEvent;

const KIND_SHOW: u16 = 30074;
const KIND_EPISODE: u16 = 30075;

#[uniffi::export(async_runtime = "tokio")]
impl PodcastrCore {
    /// Publish (or replace) a NIP-74 kind:30074 podcast show event.
    ///
    /// `d_tag` is the addressable identifier — callers typically use
    /// `"podcast:guid:<uuid>"` to match the Swift convention.
    pub async fn publish_podcast_show(
        &self,
        d_tag: String,
        title: String,
        author: String,
        description: String,
        image_url: Option<String>,
        categories: Vec<String>,
    ) -> Result<SignedEvent, CoreError> {
        let mut builder = EventBuilder::new(Kind::Custom(KIND_SHOW), description.clone())
            .tag(Tag::identifier(d_tag))
            .tag(parse_tag(["title", title.as_str()])?)
            .tag(parse_tag(["author", author.as_str()])?);

        if !description.is_empty() {
            builder = builder.tag(parse_tag(["summary", description.as_str()])?);
        }
        if let Some(image) = image_url.as_deref() {
            if !image.is_empty() {
                builder = builder.tag(parse_tag(["image", image])?);
            }
        }
        for category in &categories {
            if !category.is_empty() {
                builder = builder.tag(parse_tag(["t", category.as_str()])?);
            }
        }

        send_and_collect(self, builder).await
    }

    /// Publish (or replace) a NIP-74 kind:30075 podcast episode event.
    ///
    /// The `show_coordinate` is the parent show's NIP-33 coordinate
    /// (`30074:<pubkey>:<dTag>`) and is emitted as an `a` tag so episodes are
    /// discoverable via `#a` filters.
    #[allow(clippy::too_many_arguments)]
    pub async fn publish_podcast_episode(
        &self,
        d_tag: String,
        show_coordinate: String,
        title: String,
        description: String,
        audio_url: String,
        mime_type: Option<String>,
        sha256_hex: Option<String>,
        size: Option<u64>,
        duration: Option<u64>,
        chapters_url: Option<String>,
        transcript_url: Option<String>,
    ) -> Result<SignedEvent, CoreError> {
        if audio_url.is_empty() {
            return Err(CoreError::InvalidInput(
                "publish_podcast_episode: audio_url is empty".to_string(),
            ));
        }

        let mut builder = EventBuilder::new(Kind::Custom(KIND_EPISODE), description.clone())
            .tag(Tag::identifier(d_tag))
            .tag(parse_tag(["title", title.as_str()])?)
            .tag(parse_tag(["a", show_coordinate.as_str()])?);

        if !description.is_empty() {
            builder = builder.tag(parse_tag(["summary", description.as_str()])?);
        }
        if let Some(dur) = duration {
            builder = builder.tag(parse_tag(["duration", &dur.to_string()])?);
        }

        // imeta — Swift packs metadata as space-separated "key value" entries.
        let mut imeta: Vec<String> = vec!["imeta".to_string(), format!("url {audio_url}")];
        if let Some(mime) = mime_type.as_deref() {
            if !mime.is_empty() {
                imeta.push(format!("m {mime}"));
            }
        }
        if let Some(hash) = sha256_hex.as_deref() {
            if !hash.is_empty() {
                imeta.push(format!("x {hash}"));
            }
        }
        if let Some(bytes) = size {
            imeta.push(format!("size {bytes}"));
        }
        if let Some(dur) = duration {
            imeta.push(format!("duration {dur}"));
        }
        builder = builder.tag(Tag::parse(imeta).map_err(invalid_tag)?);

        if let Some(url) = chapters_url.as_deref() {
            if !url.is_empty() {
                builder = builder.tag(
                    Tag::parse(["chapters", url, "application/json+chapters"])
                        .map_err(invalid_tag)?,
                );
            }
        }
        if let Some(url) = transcript_url.as_deref() {
            if !url.is_empty() {
                builder = builder.tag(
                    Tag::parse(["transcript", url, "text/vtt"]).map_err(invalid_tag)?,
                );
            }
        }

        send_and_collect(self, builder).await
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn parse_tag<I, S>(tag: I) -> Result<Tag, CoreError>
where
    I: IntoIterator<Item = S>,
    S: Into<String>,
{
    Tag::parse(tag).map_err(invalid_tag)
}

fn invalid_tag<E: std::fmt::Display>(e: E) -> CoreError {
    CoreError::InvalidInput(format!("invalid tag: {e}"))
}

async fn send_and_collect(
    core: &PodcastrCore,
    builder: EventBuilder,
) -> Result<SignedEvent, CoreError> {
    let runtime = core.runtime();
    let client = runtime.client();

    // sign_event_builder requires a signer; surface a clean NotAuthenticated.
    let event = client
        .sign_event_builder(builder)
        .await
        .map_err(map_client_error)?;

    let output = client.send_event(&event).await.map_err(map_client_error)?;

    if output.success.is_empty() {
        // No relay accepted the event — surface the first relay-level error.
        let reason = output
            .failed
            .into_iter()
            .next()
            .map(|(url, err)| format!("{url}: {err}"))
            .unwrap_or_else(|| "no relay accepted event".to_string());
        return Err(CoreError::Relay(reason));
    }

    Ok(to_signed_event(&event))
}

fn map_client_error(err: nostr_sdk::client::Error) -> CoreError {
    // Pull out the unauthenticated case so Swift sees a clean variant.
    let msg = err.to_string();
    if msg.to_lowercase().contains("signer not configured")
        || msg.to_lowercase().contains("not configured")
        || msg.to_lowercase().contains("no signer")
    {
        CoreError::NotAuthenticated
    } else {
        CoreError::Relay(msg)
    }
}

fn to_signed_event(event: &Event) -> SignedEvent {
    SignedEvent {
        id: event.id.to_hex(),
        pubkey: event.pubkey.to_hex(),
        created_at: event.created_at.as_u64() as i64,
        kind: u16::from(event.kind) as u32,
        tags: event
            .tags
            .iter()
            .map(|t| t.as_slice().to_vec())
            .collect(),
        content: event.content.clone(),
        sig: event.sig.to_string(),
    }
}
