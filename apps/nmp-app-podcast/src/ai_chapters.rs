//! AI chapter compilation — synthesizes transcript-grounded chapters and ad
//! spans from the cached transcript. The kernel owns all chapter + ad policy
//! (D0); Swift only dispatches and renders projected results.
//!
//! ## Two compile modes
//!
//! Ported from the deleted `App/Sources/Services/AIChapterCompiler.swift`:
//!
//! * **FULL** — the episode has no publisher chapters yet. The LLM produces
//!   4–12 chapter boundaries with 1–2 sentence summaries AND ad spans in one
//!   shot.
//! * **ENRICH-ONLY** — the episode already has publisher (RSS / P2.0) chapters.
//!   The LLM adds per-chapter summaries (matched by index) and detects ad spans;
//!   boundaries are left untouched.
//!
//! ## Idempotency gate
//!
//! The compile is skipped when `store.ad_detection_ran(episode_id)` is `true`.
//! This matches the Swift `episode.adSegments != nil` gate: once the combined
//! chapter + ad pass has run and committed a result (even an empty ad array),
//! the action is a no-op. The gate resets on process restart for episodes where
//! detection found no ads (empty vecs are not persisted to disk), which is
//! acceptable — the re-run is cheap.
//!
//! ## Design notes
//!
//! * **D0.** Rust decides chapter boundaries, summaries, and ad-span policy.
//!   Swift dispatches `podcast.chapters.compile` and renders projected results.
//! * **D6.** Errors degrade silently through the `{"ok":false,"error":…}`
//!   envelope; the iOS shell renders error toasts.
//! * **D7.** Publisher (RSS / Podcasting 2.0) chapters are never overwritten
//!   — ENRICH-ONLY mode only adds summaries to existing chapters.
//! * **Reactive.** No polling; chapters + ads land in the store when the
//!   background LLM task completes and bump rev/signal for the next push frame.
//! * **Offline fallback.** When the model is unreachable, FULL mode degrades
//!   to equal-length stub chapters (no ad detection — the model must be
//!   reachable to detect ads). ENRICH-ONLY falls back to no-op for summaries.

use std::sync::atomic::AtomicU64;
use std::sync::{Arc, Mutex};

use podcast_core::ChapterSource;
use tokio::runtime::Runtime;

use crate::snapshot_signal::SnapshotUpdateSignal;
use crate::store::PodcastStore;

// Internal implementation (synthesis ladders, persistence, helpers).
#[path = "ai_chapters_impl.rs"]
mod impl_;

pub(crate) use impl_::build_stub_chapters;

/// Number of equally-spaced chapters used by the offline stub fallback.
const STUB_CHAPTER_COUNT: usize = 5;

/// Maximum characters of transcript fed to the model.
const TRANSCRIPT_EXCERPT_CHARS: usize = 28_000;

#[derive(Debug, PartialEq)]
pub(crate) enum CompileOutcome {
    /// New AI chapters were synthesized and persisted.
    Compiled { chapter_count: usize },
    /// Episode already had ad detection run (idempotency gate).
    AlreadyDone,
    /// No cached transcript — the caller must dispatch
    /// `podcast.fetch_transcript` first.
    NoTranscript,
    /// Episode duration is unknown so we can't compute segment offsets.
    NoDuration,
    /// Episode id didn't resolve to any episode in the store.
    EpisodeNotFound,
}

/// Public host-op entry point. Mirrors the shape of
/// [`crate::chapter::handle_fetch_chapters`] so the host-op handler can
/// dispatch both with the same call shape.
pub(crate) fn handle_compile_chapters(
    store: &Arc<Mutex<PodcastStore>>,
    rev: &Arc<AtomicU64>,
    runtime: &Arc<Runtime>,
    episode_id: String,
) -> serde_json::Value {
    handle_compile_chapters_inner(store, rev, runtime, episode_id, None)
}

pub(crate) fn handle_compile_chapters_with_signal(
    store: &Arc<Mutex<PodcastStore>>,
    rev: &Arc<AtomicU64>,
    runtime: &Arc<Runtime>,
    episode_id: String,
    snapshot_signal: SnapshotUpdateSignal,
) -> serde_json::Value {
    handle_compile_chapters_inner(store, rev, runtime, episode_id, Some(snapshot_signal))
}

fn handle_compile_chapters_inner(
    store: &Arc<Mutex<PodcastStore>>,
    rev: &Arc<AtomicU64>,
    runtime: &Arc<Runtime>,
    episode_id: String,
    snapshot_signal: Option<SnapshotUpdateSignal>,
) -> serde_json::Value {
    // Gate checks run synchronously (fast, no I/O) so errors surface immediately.
    let inputs = match store.lock() {
        Ok(s) => read_episode_inputs(&s, &episode_id),
        Err(_) => return serde_json::json!({"ok": false, "error": "store poisoned"}),
    };
    let (duration_secs, transcript, episode_title, mode) = match inputs {
        EpisodeInputs::Missing => {
            return serde_json::json!({"ok": false, "error": format!("episode not found: {episode_id}")})
        }
        EpisodeInputs::AlreadyDone => {
            return serde_json::json!({"ok": true, "status": "already_done"})
        }
        EpisodeInputs::Ready { duration_secs, transcript, episode_title, mode } => {
            let Some(transcript) = transcript else {
                return serde_json::json!({"ok": false, "error": "no_transcript"});
            };
            let duration_secs = match duration_secs {
                Some(d) if d > 0.0 => d,
                _ => return serde_json::json!({"ok": false, "error": "no_duration"}),
            };
            (duration_secs, transcript, episode_title, mode)
        }
    };

    // Spawn LLM synthesis off the actor thread. The actor returns immediately;
    // chapters + ads land in the store when the background task completes.
    let store_c = Arc::clone(store);
    let store_c2 = Arc::clone(store);
    let rev_c = Arc::clone(rev);
    let runtime_c = Arc::clone(runtime);
    let episode_id_c = episode_id.clone();

    runtime.spawn(async move {
        let outcome = tokio::task::spawn_blocking(move || match mode {
            CompileMode::Full => impl_::compile_full(
                &episode_title,
                &transcript,
                duration_secs,
                &runtime_c,
                &store_c,
            ),
            CompileMode::EnrichOnly { existing_chapters } => impl_::compile_enrich_only(
                &episode_title,
                &transcript,
                duration_secs,
                existing_chapters,
                &runtime_c,
                &store_c,
            ),
        })
        .await
        // A join error (panic in the blocking worker) degrades to a stub.
        .unwrap_or_else(|_| {
            BackgroundOutcome::FullChapters {
                chapters: build_stub_chapters(duration_secs, STUB_CHAPTER_COUNT, ChapterSource::Stub),
                ads: Vec::new(),
            }
        });

        impl_::persist_outcome(outcome, &episode_id_c, &store_c2, &snapshot_signal, &rev_c);
    });

    serde_json::json!({"ok": true, "status": "compiling", "episode_id": episode_id})
}

// ── Compile modes ────────────────────────────────────────────────────────────

/// Which compile path to use for this episode.
enum CompileMode {
    /// No publisher chapters — synthesize boundaries + summaries + ads.
    Full,
    /// Publisher chapters exist — add summaries and detect ads only.
    EnrichOnly {
        /// `(start_secs, title)` pairs from the publisher's chapter list,
        /// used to build the numbered prompt for the LLM.
        existing_chapters: Vec<(f64, String)>,
    },
}

/// Result from the background synthesis task.
enum BackgroundOutcome {
    /// New AI chapters + detected ad spans (FULL mode result).
    FullChapters {
        chapters: Vec<podcast_core::Chapter>,
        ads: Vec<podcast_core::AdSegment>,
    },
    /// Summaries applied to existing publisher chapters + detected ads
    /// (ENRICH-ONLY mode result). `chapters` here are the publisher
    /// chapters with summaries overlaid; boundaries are unchanged.
    EnrichedChapters {
        chapters: Vec<podcast_core::Chapter>,
        ads: Vec<podcast_core::AdSegment>,
    },
    /// FULL model answered but was unparseable through retry. Don't fabricate
    /// equal slices. A `chapters.attempt` event was already emitted.
    GaveUp(String),
}

enum EpisodeInputs {
    Missing,
    /// Ad detection has already run for this episode (idempotency gate).
    AlreadyDone,
    Ready {
        duration_secs: Option<f64>,
        transcript: Option<String>,
        episode_title: String,
        mode: CompileMode,
    },
}

fn read_episode_inputs(store: &PodcastStore, episode_id: &str) -> EpisodeInputs {
    // Idempotency gate: if we've already committed an ad detection result
    // (even an empty one), skip the compile.
    if store.ad_detection_ran(episode_id) {
        return EpisodeInputs::AlreadyDone;
    }

    // Resolve the episode. `episode_chapters_state` returns `None` when the
    // episode doesn't exist in the store.
    let Some((_, has_chapters)) = store.episode_chapters_state(episode_id) else {
        return EpisodeInputs::Missing;
    };

    let duration_secs = store.episode_duration_secs(episode_id);
    let transcript = store
        .transcript_for(episode_id)
        .filter(|t| !t.trim().is_empty())
        .map(str::to_owned);
    let episode_title = store
        .episode_titles_and_duration(episode_id)
        .map(|(ep_title, _pod_title, _dur)| ep_title)
        .unwrap_or_default();

    let mode = if has_chapters {
        // Publisher chapters exist — enrich with summaries + detect ads.
        let existing = store
            .episode_chapters(episode_id)
            .unwrap_or_default()
            .into_iter()
            .map(|c| (c.start_secs, c.title.clone()))
            .collect();
        CompileMode::EnrichOnly { existing_chapters: existing }
    } else {
        CompileMode::Full
    };

    EpisodeInputs::Ready { duration_secs, transcript, episode_title, mode }
}

#[cfg(test)]
#[path = "ai_chapters_tests.rs"]
mod tests;
