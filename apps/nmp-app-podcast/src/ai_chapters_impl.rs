//! Internal implementation details for AI chapter compilation — synthesis
//! ladders, persistence helpers, and outcome-to-domain conversions.
//!
//! This module is included via `#[path]` from `ai_chapters.rs` to keep the
//! public API file under the 500-line project limit.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use podcast_core::{AdKind, AdSegment, Chapter, ChapterSource};
use tokio::runtime::Runtime;

use crate::ai_chapters_llm::{self, CompileResult, EnrichOnlyResult, PromptStyle, SynthesizedChapter};
use crate::snapshot_signal::SnapshotUpdateSignal;
use crate::store::PodcastStore;

use super::{BackgroundOutcome, STUB_CHAPTER_COUNT, TRANSCRIPT_EXCERPT_CHARS};

/// FULL-mode synthesis ladder (no publisher chapters). Mirrors the Swift
/// compiler's combined chapter+summary+ads round-trip. Falls back to equal-
/// length stubs when the model is definitively unreachable (offline), and gives
/// up (leaving the episode chapterless) when the model answers but is
/// unparseable through one retry.
pub(super) fn compile_full(
    episode_title: &str,
    transcript: &str,
    duration_secs: f64,
    runtime: &Arc<Runtime>,
    store: &Arc<Mutex<PodcastStore>>,
) -> BackgroundOutcome {
    let excerpt: String = transcript.chars().take(TRANSCRIPT_EXCERPT_CHARS).collect();

    // Attempt 1: FULL-mode combined prompt (chapters + summaries + ads).
    let first = ai_chapters_llm::synthesize_full(
        episode_title,
        &excerpt,
        duration_secs,
        runtime,
        store,
    );
    match first {
        Ok(result) => return full_outcome_from_compile_result(result),
        // Model definitively absent → stub chapters, no ads.
        Err(e) if e.is_unavailable() => {
            return BackgroundOutcome::FullChapters {
                chapters: build_stub_chapters(duration_secs, STUB_CHAPTER_COUNT, ChapterSource::Stub),
                ads: Vec::new(),
            }
        }
        // Parse failure → retry with the simple chapters-only prompt (legacy
        // path), then surface any chapters; ads detection is skipped on retry.
        Err(_) => {}
    }

    // Attempt 2: simpler chapters-only prompt (retry on parse failure).
    let retry = ai_chapters_llm::synthesize_chapters_styled(
        episode_title,
        &excerpt,
        duration_secs,
        STUB_CHAPTER_COUNT,
        PromptStyle::Simple,
        runtime,
        store,
    );
    match retry {
        Ok(synthesized) => BackgroundOutcome::FullChapters {
            chapters: chapters_from_llm(&synthesized),
            ads: Vec::new(),
        },
        Err(e) if e.is_unavailable() => BackgroundOutcome::FullChapters {
            chapters: build_stub_chapters(duration_secs, STUB_CHAPTER_COUNT, ChapterSource::Stub),
            ads: Vec::new(),
        },
        Err(e) => BackgroundOutcome::GaveUp(e.message().to_owned()),
    }
}

/// Convert a `CompileResult` (from the FULL LLM round-trip) into
/// `BackgroundOutcome::FullChapters`.
fn full_outcome_from_compile_result(result: CompileResult) -> BackgroundOutcome {
    let chapters = result
        .chapters
        .iter()
        .map(|c| {
            let mut ch = Chapter::new(c.title.clone(), c.start_secs);
            ch.is_ai_generated = true;
            ch.source = ChapterSource::Llm;
            ch.summary = c.summary.clone();
            ch
        })
        .collect();
    let ads = synthesized_ads_to_domain(result.ads);
    BackgroundOutcome::FullChapters { chapters, ads }
}

/// ENRICH-ONLY synthesis: publisher chapters exist; add summaries + detect ads.
pub(super) fn compile_enrich_only(
    episode_title: &str,
    transcript: &str,
    duration_secs: f64,
    existing_chapters: Vec<(f64, String)>,
    runtime: &Arc<Runtime>,
    store: &Arc<Mutex<PodcastStore>>,
) -> BackgroundOutcome {
    let excerpt: String = transcript.chars().take(TRANSCRIPT_EXCERPT_CHARS).collect();
    let existing_refs: Vec<(f64, &str)> = existing_chapters
        .iter()
        .map(|(s, t)| (*s, t.as_str()))
        .collect();

    match ai_chapters_llm::synthesize_enrich_only(
        episode_title,
        &excerpt,
        duration_secs,
        &existing_refs,
        runtime,
        store,
    ) {
        Ok(EnrichOnlyResult { summaries, ads }) => {
            // Re-hydrate existing chapters with LLM summaries by index.
            let enriched: Vec<Chapter> = existing_chapters
                .iter()
                .enumerate()
                .map(|(idx, (start_secs, title))| {
                    let mut ch = Chapter::new(title.clone(), *start_secs);
                    // Preserve publisher provenance — enrich only adds summaries.
                    ch.source = ChapterSource::Publisher;
                    if let Some(summary) = summaries.get(&idx) {
                        ch.summary = Some(summary.clone());
                    }
                    ch
                })
                .collect();
            let ads = synthesized_ads_to_domain(ads);
            BackgroundOutcome::EnrichedChapters { chapters: enriched, ads }
        }
        // Model unreachable → skip enrichment; still record "ran" by falling
        // through to an empty-ads persist so the gate doesn't loop.
        Err(_) => BackgroundOutcome::EnrichedChapters {
            chapters: existing_chapters
                .iter()
                .map(|(s, t)| Chapter::new(t.clone(), *s))
                .collect(),
            ads: Vec::new(),
        },
    }
}

// ── Persistence + event emission ─────────────────────────────────────────────

pub(super) fn persist_outcome(
    outcome: BackgroundOutcome,
    episode_id: &str,
    store: &Arc<Mutex<PodcastStore>>,
    snapshot_signal: &Option<SnapshotUpdateSignal>,
    rev: &Arc<AtomicU64>,
) {
    use crate::store::events::{stage, EventDetail, EventSeverity};

    match outcome {
        BackgroundOutcome::FullChapters { chapters, ads } => {
            let chapter_count = chapters.len();
            let ad_count = ads.len();
            let is_stub = chapters
                .first()
                .map(|c| c.source == ChapterSource::Stub)
                .unwrap_or(false);
            if let Ok(mut s) = store.lock() {
                let model_name = s.chapter_compilation_model_name().to_owned();
                let model_id = s.chapter_compilation_model().to_owned();
                s.set_episode_chapters(episode_id, chapters);
                s.set_ad_segments_for(episode_id, ads);

                // chapters.ready event
                let mut details = vec![EventDetail::new("Count", chapter_count.to_string())];
                let (summary, source_label) = if is_stub {
                    (
                        "Chapters identified · equal-length fallback".to_owned(),
                        "Equal-length fallback (model unavailable)".to_owned(),
                    )
                } else {
                    details.push(EventDetail::new("Model", model_name.clone()));
                    details.push(EventDetail::new("Model ID", model_id));
                    (format!("Chapters identified · {model_name}"), "AI".to_owned())
                };
                details.push(EventDetail::new("Source", source_label));
                s.emit_event(
                    episode_id,
                    stage::CHAPTERS_READY,
                    EventSeverity::Success,
                    summary,
                    details,
                );

                // ads.ready event (only when model was reachable)
                if !is_stub {
                    s.emit_event(
                        episode_id,
                        stage::ADS_READY,
                        EventSeverity::Success,
                        format!("Ad spans detected · {} found", ad_count),
                        vec![EventDetail::new("Count", ad_count.to_string())],
                    );
                }
            }
            bump(snapshot_signal, rev);
        }

        BackgroundOutcome::EnrichedChapters { chapters, ads } => {
            let ad_count = ads.len();
            if let Ok(mut s) = store.lock() {
                s.set_episode_chapters(episode_id, chapters);
                s.set_ad_segments_for(episode_id, ads);

                s.emit_event(
                    episode_id,
                    stage::CHAPTERS_READY,
                    EventSeverity::Success,
                    "Publisher chapters enriched with AI summaries".to_owned(),
                    vec![],
                );
                s.emit_event(
                    episode_id,
                    stage::ADS_READY,
                    EventSeverity::Success,
                    format!("Ad spans detected · {} found", ad_count),
                    vec![EventDetail::new("Count", ad_count.to_string())],
                );
            }
            bump(snapshot_signal, rev);
        }

        BackgroundOutcome::GaveUp(err) => {
            eprintln!(
                "[ai_chapters] model reachable but unparseable for {episode_id} \
                 after retry ({err}); leaving episode chapterless"
            );
            // Still mark the gate so we don't retry forever.
            if let Ok(mut s) = store.lock() {
                s.set_ad_segments_for(episode_id, Vec::new());
            }
        }
    }
}

pub(super) fn bump(snapshot_signal: &Option<SnapshotUpdateSignal>, rev: &Arc<AtomicU64>) {
    if let Some(signal) = snapshot_signal {
        signal.bump();
    } else {
        rev.fetch_add(1, Ordering::Relaxed);
    }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Convert `SynthesizedAdSpan`s to domain `AdSegment`s.
pub(super) fn synthesized_ads_to_domain(
    ads: Vec<ai_chapters_llm::SynthesizedAdSpan>,
) -> Vec<AdSegment> {
    ads.into_iter()
        .map(|a| {
            let kind = match a.kind.as_str() {
                "preroll" => AdKind::Preroll,
                "postroll" => AdKind::Postroll,
                _ => AdKind::Midroll,
            };
            AdSegment::new(a.start_secs, a.end_secs, kind)
        })
        .collect()
}

/// Map LLM-synthesized chapters into `podcast_core::Chapter`s stamped with
/// [`ChapterSource::Llm`] provenance + the `is_ai_generated` flag.
pub(super) fn chapters_from_llm(synthesized: &[SynthesizedChapter]) -> Vec<Chapter> {
    synthesized.iter().map(chapter_from_synthesized).collect()
}

/// Convert one [`SynthesizedChapter`] into a `podcast_core::Chapter`.
pub(super) fn chapter_from_synthesized(c: &SynthesizedChapter) -> Chapter {
    let mut chapter = Chapter::new(c.title.clone(), c.start_secs);
    chapter.is_ai_generated = true;
    chapter.source = ChapterSource::Llm;
    chapter.summary = c.summary.clone();
    chapter
}

/// Slice the episode duration into `count` evenly-spaced AI chapters, stamped
/// with the given [`ChapterSource`] provenance.
pub(crate) fn build_stub_chapters(
    duration_secs: f64,
    count: usize,
    source: ChapterSource,
) -> Vec<Chapter> {
    let count = count.max(1);
    let step = duration_secs / count as f64;
    (0..count)
        .map(|i| {
            let mut chapter = Chapter::new(format!("Chapter {}", i + 1), i as f64 * step);
            chapter.is_ai_generated = true;
            chapter.source = source;
            chapter
        })
        .collect()
}
