use crate::ffi::projections::PodcastSummary;

//! iTunes Search API helpers shared by [`crate::host_op_handler`].
//!
//! Extracted into its own module so `host_op_handler.rs` stays under the
//! 500-line hard cap. No state — pure functions over strings.

use crate::ffi::projections::PodcastSummary;

/// Percent-encode `s` for use in an `https://itunes.apple.com/search?term=…`
/// query string. RFC 3986 unreserved characters pass through; space becomes
/// `+`; everything else is `%HH` UTF-8.
pub(crate) fn url_encode(s: &str) -> String {
    s.chars()
        .flat_map(|c| match c {
            'A'..='Z' | 'a'..='z' | '0'..='9' | '-' | '_' | '.' | '~' => vec![c],
            ' ' => vec!['+'],
            other => {
                let mut buf = [0u8; 4];
                other
                    .encode_utf8(&mut buf)
                let bytes = other.encode_utf8(&mut buf);
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

/// Parse the iTunes Search API JSON payload into [`PodcastSummary`] rows.
///
/// Returns an empty `Vec` on any decode failure (D6). Used by
/// `PodcastAction::SearchItunes` to populate `PodcastHandle.search_results`
/// without throwing across the FFI.
pub(crate) fn parse_itunes_results(body: &str) -> Vec<PodcastSummary> {
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
                episodes: vec![],
            })
        })
        .collect()
}
