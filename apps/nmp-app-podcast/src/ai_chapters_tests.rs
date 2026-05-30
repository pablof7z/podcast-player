//! Tests for [`super::ai_chapters`] — stub chapter compilation and gating logic.
//!
//! Extracted from `ai_chapters.rs` to keep that file under the 500-line hard limit.

use super::*;
use podcast_core::{Episode, Podcast};
use tokio::runtime::Runtime;

/// Single-threaded runtime for the gating tests. The LLM-first `compile` path
/// only reaches the network when an episode passes every gate AND a transcript
/// is present; the gating tests below stop short of that, so this runtime is
/// inert for them. The one happy-path test that does pass all gates
/// (`compile_emits_compiling_status_and_persists_chapters`) asserts only the
/// behaviour that holds for both the LLM and stub branches (status, rev bump,
/// persistence, chapter_count >= 1) so it stays deterministic regardless of
/// whether Ollama is reachable.
fn test_runtime() -> Runtime {
    Runtime::new().expect("runtime")
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

#[test]
fn build_stub_chapters_evenly_distributes_starts() {
    let chapters = build_stub_chapters(3600.0, 4);
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
fn build_stub_chapters_handles_count_one() {
    let chapters = build_stub_chapters(120.0, 1);
    assert_eq!(chapters.len(), 1);
    assert_eq!(chapters[0].start_secs, 0.0);
    assert!(chapters[0].is_ai_generated);
}

#[test]
fn build_stub_chapters_treats_zero_count_as_one() {
    // Defensive: zero would cause a divide-by-zero in the loop; we clamp to 1.
    let chapters = build_stub_chapters(60.0, 0);
    assert_eq!(chapters.len(), 1);
}

#[test]
fn compile_emits_compiling_status_and_persists_chapters() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let (podcast, episode) = make_episode_with_duration(Some(600.0));
    let ep_id = episode.id.0.to_string();
    store.lock().unwrap().subscribe(podcast, vec![episode]);
    store.lock().unwrap().set_transcript(ep_id.clone(), "hello world".to_owned());

    let rt = test_runtime();
    let rev = AtomicU64::new(0);
    let result = handle_compile_chapters(&store, &rev, &rt, ep_id.clone());
    assert_eq!(result["ok"], true);
    assert_eq!(result["status"], "compiling");
    // Count comes from the LLM when Ollama is reachable, else the stub; both
    // branches yield at least one chapter. The exact stub count is asserted
    // deterministically in the `build_stub_chapters_*` unit tests above.
    assert!(
        result["chapter_count"].as_u64().unwrap_or(0) >= 1,
        "got: {}",
        result["chapter_count"]
    );
    assert_eq!(rev.load(Ordering::Relaxed), 1);

    let (_url, loaded) = store
        .lock()
        .unwrap()
        .episode_chapters_state(&ep_id)
        .expect("episode present");
    assert!(loaded, "compiled chapters must be persisted");
}

#[test]
fn compile_is_idempotent_when_episode_has_chapters() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let (podcast, mut episode) = make_episode_with_duration(Some(600.0));
    let ep_id = episode.id.0.to_string();
    episode.chapters = Some(vec![Chapter::new("Existing", 0.0)]);
    store.lock().unwrap().subscribe(podcast, vec![episode]);
    store.lock().unwrap().set_transcript(ep_id.clone(), "hi".to_owned());

    let rt = test_runtime();
    let rev = AtomicU64::new(0);
    let result = handle_compile_chapters(&store, &rev, &rt, ep_id);
    assert_eq!(result["ok"], true);
    assert_eq!(result["status"], "already_has_chapters");
    // No mutation, no rev bump.
    assert_eq!(rev.load(Ordering::Relaxed), 0);
}

#[test]
fn compile_refuses_when_no_transcript() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let (podcast, episode) = make_episode_with_duration(Some(600.0));
    let ep_id = episode.id.0.to_string();
    store.lock().unwrap().subscribe(podcast, vec![episode]);

    let rt = test_runtime();
    let rev = AtomicU64::new(0);
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
    store.lock().unwrap().set_transcript(ep_id.clone(), "   \n  ".to_owned());

    let rt = test_runtime();
    let rev = AtomicU64::new(0);
    let result = handle_compile_chapters(&store, &rev, &rt, ep_id);
    assert_eq!(result["ok"], false);
    assert_eq!(result["error"], "no_transcript");
}

#[test]
fn compile_refuses_when_no_duration() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let (podcast, episode) = make_episode_with_duration(None);
    let ep_id = episode.id.0.to_string();
    store.lock().unwrap().subscribe(podcast, vec![episode]);
    store.lock().unwrap().set_transcript(ep_id.clone(), "hi".to_owned());

    let rt = test_runtime();
    let rev = AtomicU64::new(0);
    let result = handle_compile_chapters(&store, &rev, &rt, ep_id);
    assert_eq!(result["ok"], false);
    assert_eq!(result["error"], "no_duration");
}

#[test]
fn compile_reports_episode_not_found() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let rt = test_runtime();
    let rev = AtomicU64::new(0);
    let result = handle_compile_chapters(&store, &rev, &rt, "missing-episode".to_owned());
    assert_eq!(result["ok"], false);
    assert!(
        result["error"].as_str().unwrap_or_default().contains("episode not found"),
        "got: {}",
        result["error"]
    );
}
