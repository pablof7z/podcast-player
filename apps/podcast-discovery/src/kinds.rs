//! NIP-F4 event kind numbers.
//!
//! Pinned in one place so the parse + build sides cannot drift. The kind
//! numbers are the protocol contract — changing them is a breaking wire
//! change that requires an ADR.
//!
//! NIP-F4 uses per-podcast keypairs:
//!   - Kind 10154: show metadata (replaceable per author)
//!   - Kind 54:    episode event (replaceable per author + d-tag)
//!   - Kind 10064: author claim (agent key declares ownership of podcast keys)

/// Podcast show metadata — kind:10154 (replaceable).
///
/// Tag layout (NIP-F4):
/// `["title", ...]`, `["summary", ...]`, `["feed", <rss-url>]`,
/// `["image", <url>]`, `["language", <lang>]`, repeated `["t", <category>]`.
pub const KIND_SHOW: u32 = 10154;

/// Podcast episode — kind:54 (replaceable, d = episode guid).
///
/// Tag layout (NIP-F4):
/// `["d", "<guid>"]`, `["title", ...]`, `["published_at", <unix>]`,
/// `["a", "10154:<pubkey>"]`, optional `["summary", ...]`,
/// `["duration", <secs>]`, `["image", <url>]`,
/// `["imeta", "url <u>", "m <mime>", "x <sha256>", "size <bytes>", ...]`,
/// `["chapters", <url>, <mime>]`, `["transcript", <url>, <mime>]`.
pub const KIND_EPISODE: u32 = 54;

/// Podcast-owner author claim — kind:10064 (replaceable).
///
/// Lets an agent key declare ownership of a set of per-podcast pubkeys.
pub const KIND_AUTHOR_CLAIM: u32 = 10064;

#[cfg(test)]
#[path = "kinds_tests.rs"]
mod tests;
