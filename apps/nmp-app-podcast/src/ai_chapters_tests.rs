//! Tests for [`super::ai_chapters`] — stub chapter compilation and gating logic.
//!
//! Extracted from `ai_chapters.rs` to keep that file under the 500-line hard limit.

use super::*;
use podcast_core::{Chapter, Episode, Podcast};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use tokio::runtime::Runtime;

use crate::ai_chapters_llm::SynthesizedChapter;
use super::impl_::chapter_from_synthesized;

fn test_runtime() -> Arc<Runtime> {
    Arc::new(Runtime::new().expect("runtime"))
}

fn test_rev() -> Arc<AtomicU64> {
    Arc::new(AtomicU64::new(0))
}

fn make_episode_with_duration(duration: Option<f64>) -> (Podcast, Episode) {
    let podcast = Podcast::new("Show");
    let mut episode = Episode::new(
        podcast.id,
        "https://example.com/feed.xml",
        "guid-1",
        "Ep",
        url::Url::parse("https://example.com/audio.mp3").unwrap(),
        chrono::Utc::now(),
    );
    episode.duration_secs = duration;
    (podcast, episode)
}

// ── build_stub_chapters ───────────────────────────────────────────────────────

#[test]
fn build_stub_chapters_evenly_distributes_starts() {
    let chapters = build_stub_chapters(3600.0, 4, ChapterSource::Stub);
    assert_eq!(chapters.len(), 4);
    assert_eq!(chapters[0].start_secs, 0.0);
    assert_eq!(chapters[1].start_secs, 900.0);
    assert_eq!(chapters[2].start_secs, 1800.0);
    assert_eq!(chapters[3].start_secs, 2700.0);
    assert!(chapters.iter().all(|c| c.is_ai_generated));
    assert_eq!(chapters[0].title, "Chapter 1");
    assert_eq!(chapters[3].title, "Chapter 4");
}

#[test]
fn build_stub_chapters_stamps_requested_source() {
    let stub = build_stub_chapters(60.0, 2, ChapterSource::Stub);
    assert!(stub.iter().all(|c| c.source == ChapterSource::Stub));
}

#[test]
fn build_stub_chapters_handles_count_one() {
    let chapters = build_stub_chapters(120.0, 1, ChapterSource::Stub);
    assert_eq!(chapters.len(), 1);
    assert_eq!(chapters[0].start_secs, 0.0);
    assert!(chapters[0].is_ai_generated);
}

#[test]
fn build_stub_chapters_treats_zero_count_as_one() {
    let chapters = build_stub_chapters(60.0, 0, ChapterSource::Stub);
    assert_eq!(chapters.len(), 1);
}

// ── chapter_from_synthesized ──────────────────────────────────────────────────

#[test]
fn chapter_from_synthesized_marks_llm_provenance() {
    let synth = SynthesizedChapter {
        title: "Real topic shift".into(),
        start_secs: 42.0,
        summary: Some("A brief summary.".into()),
    };
    let chapter = chapter_from_synthesized(&synth);
    assert_eq!(chapter.source, ChapterSource::Llm);
    assert!(chapter.is_ai_generated);
    assert_eq!(chapter.title, "Real topic shift");
    assert_eq!(chapter.start_secs, 42.0);
    assert_eq!(chapter.summary.as_deref(), Some("A brief summary."));
}

#[test]
fn chapter_from_synthesized_no_summary() {
    let synth = SynthesizedChapter {
        title: "Opener".into(),
        start_secs: 0.0,
        summary: None,
    };
    let chapter = chapter_from_synthesized(&synth);
    assert!(chapter.summary.is_none());
}

// ── Gate: idempotency (ad_detection_ran) ─────────────────────────────────────

#[test]
fn compile_is_idempotent_once_ad_detection_ran() {
    // After ad detection has committed (even empty), the action must be a
    // no-op — the "already_done" gate fires.
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let (podcast, episode) = make_episode_with_duration(Some(600.0));
    let ep_id = episode.id.0.to_string();
    store.lock().unwrap().subscribe(podcast, vec![episode]);
    store
        .lock()
        .unwrap()
        .set_transcript(ep_id.clone(), "some transcript".to_owned());
    // Simulate a prior run: commit empty ad segments.
    store
        .lock()
        .unwrap()
        .set_ad_segments_for(ep_id.clone(), Vec::new());

    let rt = test_runtime();
    let rev = test_rev();
    let result = handle_compile_chapters(&store, &rev, &rt, ep_id);
    assert_eq!(result["ok"], true);
    assert_eq!(result["status"], "already_done");
    assert_eq!(rev.load(Ordering::Relaxed), 0, "no rev bump on already_done");
}

// ── Gate: episode with publisher chapters triggers ENRICH-ONLY ────────────────

#[test]
fn compile_returns_compiling_for_episode_with_publisher_chapters() {
    // An episode that already has publisher chapters should still compile
    // (ENRICH-ONLY mode) — it is NOT a gate-out "already_done".
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let (podcast, mut episode) = make_episode_with_duration(Some(600.0));
    let ep_id = episode.id.0.to_string();
    episode.chapters = Some(vec![Chapter::new("Existing", 0.0)]);
    store.lock().unwrap().subscribe(podcast, vec![episode]);
    store
        .lock()
        .unwrap()
        .set_transcript(ep_id.clone(), "some transcript".to_owned());

    let rt = test_runtime();
    let rev = test_rev();
    let result = handle_compile_chapters(&store, &rev, &rt, ep_id);
    // The handler returns "compiling" immediately (async task spawned).
    assert_eq!(result["ok"], true);
    assert_eq!(result["status"], "compiling");
}

// ── Gate: missing episode ─────────────────────────────────────────────────────

#[test]
fn compile_reports_episode_not_found() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let rt = test_runtime();
    let rev = test_rev();
    let result = handle_compile_chapters(&store, &rev, &rt, "missing-episode".to_owned());
    assert_eq!(result["ok"], false);
    assert!(
        result["error"]
            .as_str()
            .unwrap_or_default()
            .contains("episode not found"),
        "got: {}",
        result["error"]
    );
}

// ── Gate: no transcript ───────────────────────────────────────────────────────

#[test]
fn compile_refuses_when_no_transcript() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let (podcast, episode) = make_episode_with_duration(Some(600.0));
    let ep_id = episode.id.0.to_string();
    store.lock().unwrap().subscribe(podcast, vec![episode]);

    let rt = test_runtime();
    let rev = test_rev();
    let result = handle_compile_chapters(&store, &rev, &rt, ep_id);
    assert_eq!(result["ok"], false);
    assert_eq!(result["error"], "no_transcript");
    assert_eq!(rev.load(Ordering::Relaxed), 0);
}

#[test]
fn compile_refuses_when_transcript_is_whitespace_only() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let (podcast, episode) = make_episode_with_duration(Some(600.0));
    let ep_id = episode.id.0.to_string();
    store.lock().unwrap().subscribe(podcast, vec![episode]);
    store
        .lock()
        .unwrap()
        .set_transcript(ep_id.clone(), "   \n  ".to_owned());

    let rt = test_runtime();
    let rev = test_rev();
    let result = handle_compile_chapters(&store, &rev, &rt, ep_id);
    assert_eq!(result["ok"], false);
    assert_eq!(result["error"], "no_transcript");
}

// ── Gate: no duration ─────────────────────────────────────────────────────────

#[test]
fn compile_refuses_when_no_duration() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let (podcast, episode) = make_episode_with_duration(None);
    let ep_id = episode.id.0.to_string();
    store.lock().unwrap().subscribe(podcast, vec![episode]);
    store
        .lock()
        .unwrap()
        .set_transcript(ep_id.clone(), "hi".to_owned());

    let rt = test_runtime();
    let rev = test_rev();
    let result = handle_compile_chapters(&store, &rev, &rt, ep_id);
    assert_eq!(result["ok"], false);
    assert_eq!(result["error"], "no_duration");
}

// ── Async compilation test (ignored — needs multi-thread headroom) ────────────

#[test]
#[ignore = "async background task — requires multi-thread runtime headroom; run manually"]
fn compile_emits_compiling_status_and_persists_chapters_and_ads() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let (podcast, episode) = make_episode_with_duration(Some(600.0));
    let ep_id = episode.id.0.to_string();
    store.lock().unwrap().subscribe(podcast, vec![episode]);
    store
        .lock()
        .unwrap()
        .set_transcript(ep_id.clone(), "hello world".to_owned());

    let rt = test_runtime();
    let rev = test_rev();
    let result = handle_compile_chapters(&store, &rev, &rt, ep_id.clone());
    assert_eq!(result["ok"], true);
    assert_eq!(result["status"], "compiling");
    assert_eq!(
        rev.load(Ordering::Relaxed),
        0,
        "rev must NOT be bumped synchronously"
    );

    // Drive the background task to completion.
    rt.block_on(async {
        tokio::time::sleep(std::time::Duration::from_millis(500)).await;
    });

    assert!(
        rev.load(Ordering::Relaxed) >= 1,
        "rev must be bumped after background compile"
    );
    // Ad detection gate must be set after compile.
    assert!(
        store.lock().unwrap().ad_detection_ran(&ep_id),
        "ad_detection_ran must be true after compile"
    );
}
