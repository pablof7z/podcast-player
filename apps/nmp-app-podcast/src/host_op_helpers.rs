//! Free-function helpers extracted from
//! [`crate::host_op_handler::PodcastHostOpHandler`] so the main file
//! stays under the 500-line hard limit. None of these touch the
//! handler's state — they're pure transforms exercised by the
//! handler's methods.
//! Free-function helpers used by [`crate::host_op_handler`].
//!
//! Extracted into its own file so `host_op_handler.rs` stays under the 500-line
//! hard cap. These functions are pure (no kernel state, no FFI) so unit tests
//! live alongside.
//! Pure helpers used by [`crate::host_op_handler::PodcastHostOpHandler`].
//!
//! Split out of `host_op_handler.rs` so that file can absorb the
//! TTS-handling dispatch wiring without crossing the 500-LOC ceiling.
//! Behaviour is unchanged — every function moved here was previously a
//! private free function in `host_op_handler.rs`.

use podcast_core::Episode;

use crate::ffi::projections::PodcastSummary;

/// Preserve per-episode `position_secs` across a feed refresh.
///
/// `fresh` is the parser's output; `existing` is what the store
/// currently has. Matched by `Episode::id`. Note that the wider
/// pipeline currently regenerates `EpisodeId` as a random `Uuid` on
/// every parse (see `Episode::new`), which means this match rarely
/// fires in practice — tracked as a follow-up; this helper keeps the
/// shape stable so the fix lands in one place.
pub(crate) fn merge_episodes(fresh: Vec<Episode>, existing: Vec<Episode>) -> Vec<Episode> {
/// Merge a freshly-parsed episode list onto an existing one, carrying forward
/// per-episode `position_secs` so a feed refresh doesn't erase resume points.
pub fn merge_episodes(fresh: Vec<Episode>, existing: Vec<Episode>) -> Vec<Episode> {
/// Merge fresh feed episodes with the existing in-store copies, keeping
/// the previously-recorded `position_secs` so refreshes don't reset
/// listener progress.
pub(crate) fn merge_episodes(fresh: Vec<Episode>, existing: Vec<Episode>) -> Vec<Episode> {
    fresh
        .into_iter()
        .map(|mut ep| {
            if let Some(prev) = existing.iter().find(|e| e.id == ep.id) {
                ep.position_secs = prev.position_secs;
            }
            ep
        })
        .collect()
}

/// `application/x-www-form-urlencoded`-style encoder used to build
/// the iTunes Search API query string. Kept local so we don't pull
/// in a heavy dependency for one call site.
pub(crate) fn url_encode(s: &str) -> String {
/// Minimal `application/x-www-form-urlencoded` style percent-encoder for the
/// iTunes search `term=` parameter. Standalone so we don't pull in a heavier
/// `percent-encoding` dependency just for this one call site.
pub fn url_encode(s: &str) -> String {
    s.chars()
        .flat_map(|c| match c {
            'A'..='Z' | 'a'..='z' | '0'..='9' | '-' | '_' | '.' | '~' => {
                vec![c]
            }
/// RFC 3986 unreserved-char URL-encoder used to build the iTunes search
/// query string. Spaces become `+`; everything else outside the unreserved
/// set is percent-encoded.
pub(crate) fn url_encode(s: &str) -> String {
    s.chars()
        .flat_map(|c| match c {
            'A'..='Z' | 'a'..='z' | '0'..='9' | '-' | '_' | '.' | '~' => vec![c],
            ' ' => vec!['+'],
            other => {
                let mut buf = [0u8; 4];
                let bytes = other.encode_utf8(&mut buf);
                bytes.bytes().flat_map(|b| {
                    let hi = char::from_digit((b >> 4) as u32, 16).unwrap_or('0');
                    let lo = char::from_digit((b & 0xf) as u32, 16).unwrap_or('0');
                    vec!['%', hi.to_ascii_uppercase(), lo.to_ascii_uppercase()]
                }).collect()
                bytes
                    .bytes()
                    .flat_map(|b| {
                        let hi = char::from_digit((b >> 4) as u32, 16).unwrap_or('0');
                        let lo = char::from_digit((b & 0xf) as u32, 16).unwrap_or('0');
                        vec!['%', hi.to_ascii_uppercase(), lo.to_ascii_uppercase()]
                    })
                    .collect()
            }
        })
        .collect()
}

/// Parse the iTunes Search API JSON payload into `PodcastSummary` rows.
/// Returns an empty Vec on any decode failure (D6).
pub(crate) fn parse_itunes_results(body: &str) -> Vec<PodcastSummary> {
/// Returns an empty `Vec` on any decode failure (D6).
pub fn parse_itunes_results(body: &str) -> Vec<PodcastSummary> {
    #[derive(serde::Deserialize)]
    struct ItunesResponse {
        results: Vec<ItunesResult>,
    }
    #[derive(serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct ItunesResult {
        collection_id: Option<i64>,
        collection_name: Option<String>,
        feed_url: Option<String>,
        artwork_url600: Option<String>,
        artist_name: Option<String>,
    }
    let Ok(resp) = serde_json::from_str::<ItunesResponse>(body) else {
        return vec![];
    };
    resp.results
        .into_iter()
        .filter_map(|r| {
            Some(PodcastSummary {
                id: r.collection_id?.to_string(),
                title: r.collection_name.unwrap_or_default(),
                episode_count: 0,
                unplayed_count: 0,
                artwork_url: r.artwork_url600,
                feed_url: r.feed_url,
                author: r.artist_name,
                auto_download: false,
                episodes: vec![],
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn url_encode_passes_through_alnum() {
        assert_eq!(url_encode("abcXYZ123"), "abcXYZ123");
    }

    #[test]
    fn url_encode_encodes_space_as_plus() {
        assert_eq!(url_encode("hello world"), "hello+world");
    }

    #[test]
    fn url_encode_percent_encodes_unicode() {
        assert_eq!(url_encode("é"), "%C3%A9");
    }

    #[test]
    fn parse_itunes_results_handles_empty_payload() {
        assert!(parse_itunes_results("{\"results\":[]}").is_empty());
        assert!(parse_itunes_results("not json").is_empty());
    }

    #[test]
    fn parse_itunes_results_extracts_one_row() {
        let body = r#"{"results":[{"collectionId":42,"collectionName":"Show","feedUrl":"https://x/y.rss","artworkUrl600":"https://x/art.png","artistName":"Host"}]}"#;
        let rows = parse_itunes_results(body);
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "42");
        assert_eq!(rows[0].title, "Show");
        assert_eq!(rows[0].author.as_deref(), Some("Host"));
    }

    #[test]
    fn parse_itunes_results_skips_rows_without_collection_id() {
        let body = r#"{"results":[{"collectionName":"NoId"}]}"#;
        assert!(parse_itunes_results(body).is_empty());
    }
}
