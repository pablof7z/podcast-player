//! `imeta` tag parsing helpers (NIP-92).
//!
//! Split out from `parse/episode.rs` so the file-LOC budget stays under
//! AGENTS.md's 300-LOC soft limit. The `imeta` payload is generic across
//! kinds — moving it here keeps the episode parser readable and lets
//! future kinds (e.g. NIP-94 audio uploads) reuse the helper.

/// Fields extracted from a single `imeta` tag.
#[derive(Default, Debug, Clone, PartialEq, Eq)]
pub(crate) struct ImetaFields {
    pub url: Option<String>,
    pub mime: Option<String>,
    pub sha256: Option<String>,
    pub size: Option<u64>,
}

/// Parse the trailing components of an `imeta` tag.
///
/// Per NIP-92, the `imeta` payload after the tag name is a sequence of
/// space-separated `key value` pairs; the publisher emits `url`, `m`,
/// `x`, `size`, and optionally `duration`. We tolerate extra trailing
/// content by taking the first whitespace token as the key and the rest
/// of the line as the value (matches Swift `hasPrefix("url ")` parsing).
pub(crate) fn parse_imeta_fields(imeta: &[String]) -> ImetaFields {
    let mut out = ImetaFields::default();
    for entry in imeta.iter().skip(1) {
        let (key, value) = match entry.split_once(' ') {
            Some(parts) => parts,
            None => continue,
        };
        match key {
            "url" => out.url = Some(value.to_string()),
            "m" => out.mime = Some(value.to_string()),
            "x" => out.sha256 = Some(value.to_string()),
            "size" => out.size = value.parse().ok(),
            _ => {}
        }
    }
    out
}

#[cfg(test)]
#[path = "imeta_tests.rs"]
mod tests;
