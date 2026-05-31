use super::*;
use chrono::Utc;
use podcast_core::{Chapter, ChapterSource, PodcastId};
use url::Url;
fn ep(title: &str, position: f64) -> Episode {
    let mut e = Episode::new(
        PodcastId::generate(),
        "https://example.com/feed.xml",
        title,
        title,
        Url::parse("https://example.com/audio.mp3").unwrap(),
        Utc::now(),
    );
    e.position_secs = position;
    e
}

/// An AI-generated chapter stamped with the LLM provenance the
/// `ai_chapters` synthesis path emits.
fn ai_chapter(title: &str, start: f64) -> Chapter {
    let mut c = Chapter::new(title, start);
    c.is_ai_generated = true;
    c.source = ChapterSource::Llm;
    c
}

/// A publisher (RSS / Podcasting 2.0) chapter — the default provenance.
fn publisher_chapter(title: &str, start: f64) -> Chapter {
    Chapter::new(title, start)
}
#[test]
fn merge_preserves_existing_position_for_matching_ids() {
    let existing = vec![ep("A", 42.0), ep("B", 100.0)];
    let mut fresh = existing.iter().map(|e| {
        let mut e2 = e.clone();
        e2.position_secs = 0.0;
        e2
    }).collect::<Vec<_>>();
    fresh.push(ep("C", 0.0));
    let merged = merge_episodes(fresh, existing);
    assert_eq!(merged[0].position_secs, 42.0);
    assert_eq!(merged[1].position_secs, 100.0);
    assert_eq!(merged[2].position_secs, 0.0);
}
#[test]
fn merge_returns_empty_when_fresh_is_empty() {
    let existing = vec![ep("A", 42.0)];
    assert!(merge_episodes(vec![], existing).is_empty());
}

/// AI-generated chapters live only in the store (the RSS feed never ships
/// them), so a refresh that re-parses the feed must carry them forward —
/// otherwise they flash empty until the next snapshot rebuild. This is the
/// regression `m4-chapters-rust-persistence` guards against.
#[test]
fn merge_preserves_ai_chapters_when_fresh_has_none() {
    let mut existing_ep = ep("A", 42.0);
    existing_ep.chapters = Some(vec![ai_chapter("Intro", 0.0), ai_chapter("Topic", 120.0)]);
    let existing = vec![existing_ep.clone()];

    // The freshly-parsed RSS episode carries no chapters (the common case).
    let mut fresh_ep = existing_ep.clone();
    fresh_ep.chapters = None;

    let merged = merge_episodes(vec![fresh_ep], existing);
    let chapters = merged[0]
        .chapters
        .as_ref()
        .expect("AI chapters should survive a feed refresh");
    assert_eq!(chapters.len(), 2);
    assert!(chapters.iter().all(|c| c.is_ai_generated));
    assert!(chapters.iter().all(|c| c.source == ChapterSource::Llm));
    assert_eq!(chapters[0].title, "Intro");
    assert_eq!(chapters[1].title, "Topic");
}

/// D7: publisher (RSS) chapters always win. When a refresh brings fresh
/// publisher chapters they must replace any prior AI-generated ones rather
/// than being shadowed by the carry-forward.
#[test]
fn merge_prefers_fresh_publisher_chapters_over_prior_ai() {
    let mut existing_ep = ep("A", 42.0);
    existing_ep.chapters = Some(vec![ai_chapter("Old AI", 0.0)]);
    let existing = vec![existing_ep.clone()];

    let mut fresh_ep = existing_ep.clone();
    fresh_ep.chapters = Some(vec![publisher_chapter("Real Chapter", 0.0)]);

    let merged = merge_episodes(vec![fresh_ep], existing);
    let chapters = merged[0].chapters.as_ref().expect("fresh chapters present");
    assert_eq!(chapters.len(), 1);
    assert_eq!(chapters[0].title, "Real Chapter");
    assert!(!chapters[0].is_ai_generated);
    assert_eq!(chapters[0].source, ChapterSource::Publisher);
}

/// An empty `Some(vec![])` from the parser is treated the same as `None`:
/// it carries no chapters, so prior AI chapters survive.
#[test]
fn merge_treats_fresh_empty_chapters_as_none() {
    let mut existing_ep = ep("A", 42.0);
    existing_ep.chapters = Some(vec![ai_chapter("Intro", 0.0)]);
    let existing = vec![existing_ep.clone()];

    let mut fresh_ep = existing_ep.clone();
    fresh_ep.chapters = Some(vec![]);

    let merged = merge_episodes(vec![fresh_ep], existing);
    let chapters = merged[0]
        .chapters
        .as_ref()
        .expect("AI chapters should survive an empty fresh chapter list");
    assert_eq!(chapters.len(), 1);
    assert_eq!(chapters[0].title, "Intro");
}

/// A brand-new episode (no prior store entry) keeps whatever the feed gave
/// it — including no chapters at all.
#[test]
fn merge_leaves_new_episode_chapters_untouched() {
    let existing: Vec<Episode> = Vec::new();
    let fresh_ep = ep("New", 0.0);
    let merged = merge_episodes(vec![fresh_ep], existing);
    assert!(merged[0].chapters.is_none());
}

