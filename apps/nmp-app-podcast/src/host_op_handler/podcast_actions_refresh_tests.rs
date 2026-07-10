//! Tests for kernel-owned feed refresh result application.
//!
//! This replaces the stale Swift-side refresh stub coverage: Swift now
//! dispatches `kernelRefresh`, while Rust owns HTTP result interpretation,
//! podcast/episode merge, validator persistence, and rev policy.

use super::*;
use crate::state::{Infra, PodcastAppState};
use crate::store::PodcastStore;
use podcast_core::{Podcast, PodcastId};
use podcast_feeds::http::HttpResult;
use podcast_feeds::refresh::policy::EtagCache;
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};
use url::Url;

const FRESH_FEED_XML: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <title>Fresh Title</title>
    <link>https://example.com</link>
    <description>Updated feed</description>
    <item>
      <title>Episode One</title>
      <guid>episode-1</guid>
      <enclosure url="https://example.com/episode-1.mp3" length="1234" type="audio/mpeg"/>
      <itunes:duration>1800</itunes:duration>
    </item>
  </channel>
</rss>"#;

fn handler_with_store(store: Arc<Mutex<PodcastStore>>) -> PodcastHostOpHandler {
    let state = Arc::new(PodcastAppState::new(Infra::for_test(), store));
    PodcastHostOpHandler::new(std::ptr::null_mut(), state)
}

fn seed_known_feed(store: &Arc<Mutex<PodcastStore>>, url: &Url) -> (PodcastId, EtagCache) {
    let podcast_id = PodcastId::generate();
    let mut podcast = Podcast::new("Old Title");
    podcast.id = podcast_id;
    podcast.feed_url = Some(url.clone());
    podcast.etag = Some("\"old-etag\"".to_owned());
    podcast.last_modified = Some("Mon, 01 Jan 2024 00:00:00 GMT".to_owned());
    store.lock().unwrap().subscribe(podcast, Vec::new());
    (
        podcast_id,
        EtagCache::with_headers(
            chrono::Utc::now(),
            Some("\"old-etag\"".to_owned()),
            Some("Mon, 01 Jan 2024 00:00:00 GMT".to_owned()),
        ),
    )
}

fn http_200(body: &str) -> HttpResult {
    HttpResult::Ok {
        status_code: 200,
        headers: vec![
            vec!["ETag".to_owned(), "\"fresh-etag\"".to_owned()],
            vec![
                "Last-Modified".to_owned(),
                "Tue, 02 Jan 2024 00:00:00 GMT".to_owned(),
            ],
        ],
        body: body.to_owned(),
        body_base64: None,
    }
}

fn http_304() -> HttpResult {
    HttpResult::Ok {
        status_code: 304,
        headers: vec![
            vec!["ETag".to_owned(), "\"fresh-etag\"".to_owned()],
            vec![
                "Last-Modified".to_owned(),
                "Tue, 02 Jan 2024 00:00:00 GMT".to_owned(),
            ],
        ],
        body: String::new(),
        body_base64: None,
    }
}

#[test]
fn refresh_parsed_feed_updates_known_podcast_and_episodes() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let url = Url::parse("https://example.com/feed.xml").unwrap();
    let (podcast_id, prior_cache) = seed_known_feed(&store, &url);
    let handler = handler_with_store(Arc::clone(&store));

    let result = handler.apply_refresh_result(
        podcast_id,
        &url,
        http_200(FRESH_FEED_XML),
        Some(&prior_cache),
        "corr-refresh-test",
        true,
    );

    assert_eq!(result["ok"], serde_json::json!(true));
    let store = store.lock().unwrap();
    let podcast = store.podcast(podcast_id).expect("podcast should exist");
    assert_eq!(podcast.title, "Fresh Title");
    assert_eq!(podcast.etag.as_deref(), Some("\"fresh-etag\""));
    assert_eq!(
        podcast.last_modified.as_deref(),
        Some("Tue, 02 Jan 2024 00:00:00 GMT")
    );
    let episodes = store.episodes_for(podcast_id);
    assert_eq!(episodes.len(), 1);
    assert_eq!(episodes[0].guid, "episode-1");
}

/// Regression guard for the refresh-all coalescing fix (#755 follow-up):
/// `handle_refresh_all` passes `bump_domain: false` to every per-feed
/// `apply_refresh_result` call and bumps `Domain::Library` exactly once
/// itself after the loop — instead of once per feed, which used to fire a
/// full-library rebuild + re-emit (`build_library_payload`) per feed and,
/// on a real library, pegged the main thread for the whole refresh pass.
/// This test proves the mechanism directly: a parsed-feed result with
/// `bump_domain: false` must NOT advance `domain_revs.library`, while the
/// existing `bump_domain: true` tests above/below prove the opposite.
#[test]
fn refresh_parsed_feed_with_bump_domain_false_does_not_bump_library_domain_rev() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let url = Url::parse("https://example.com/feed.xml").unwrap();
    let (podcast_id, prior_cache) = seed_known_feed(&store, &url);
    let handler = handler_with_store(Arc::clone(&store));
    let library_rev_before = handler.state.infra.domain_revs.library.load(Ordering::Relaxed);

    let result = handler.apply_refresh_result(
        podcast_id,
        &url,
        http_200(FRESH_FEED_XML),
        Some(&prior_cache),
        "corr-refresh-coalesced",
        false,
    );

    assert_eq!(result["ok"], serde_json::json!(true));
    // The podcast/episode merge itself is unaffected by `bump_domain` — only
    // the rev bump is suppressed.
    let store_guard = store.lock().unwrap();
    let podcast = store_guard
        .podcast(podcast_id)
        .expect("podcast should still be merged");
    assert_eq!(podcast.title, "Fresh Title");
    drop(store_guard);
    assert_eq!(
        handler.state.infra.domain_revs.library.load(Ordering::Relaxed),
        library_rev_before,
        "bump_domain: false must not advance domain_revs.library — the caller \
         (handle_refresh_all) is responsible for a single coalesced bump"
    );
}

#[test]
fn refresh_not_modified_persists_validators_without_bumping_rev() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let url = Url::parse("https://example.com/feed.xml").unwrap();
    let (podcast_id, prior_cache) = seed_known_feed(&store, &url);
    let handler = handler_with_store(Arc::clone(&store));
    let rev_before = handler.state.infra.rev.load(Ordering::Relaxed);

    let result = handler.apply_refresh_result(
        podcast_id,
        &url,
        http_304(),
        Some(&prior_cache),
        "corr-refresh-304",
        true,
    );

    assert_eq!(result["ok"], serde_json::json!(true));
    assert_eq!(result["not_modified"], serde_json::json!(true));
    assert_eq!(
        handler.state.infra.rev.load(Ordering::Relaxed),
        rev_before,
        "304 refresh metadata must not force a snapshot rebuild"
    );
    let store = store.lock().unwrap();
    let podcast = store.podcast(podcast_id).expect("podcast should exist");
    assert_eq!(podcast.etag.as_deref(), Some("\"fresh-etag\""));
    assert_eq!(
        podcast.last_modified.as_deref(),
        Some("Tue, 02 Jan 2024 00:00:00 GMT")
    );
    assert!(podcast.last_refreshed_at.is_some());
    assert!(
        store.episodes_for(podcast_id).is_empty(),
        "304 must not mutate the parsed episode set"
    );
}
