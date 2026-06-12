//! FULL and ENRICH-ONLY compile modes — prompts, parsers, and LLM round-trips.
//!
//! This module is included via `#[path]` from [`super::ai_chapters_llm`]; it
//! uses `super::*` to access the shared types (`SynthError`, `SynthesizedChapter`,
//! `CompileResult`, `EnrichOnlyResult`, `SynthesizedAdSpan`) and constants
//! (`CHAPTERS_MODEL`, `REQUEST_TIMEOUT`) defined there.
//!
//! Splitting here keeps `ai_chapters_llm.rs` under the 500-line limit while
//! keeping the chapter-synthesis and compile-modes code logically co-located.

use super::*;

// ── FULL compile mode (chapters + summaries + ads) ──────────────────────────

/// System prompt for FULL mode: the episode has no publisher chapters yet.
/// The model produces chapter boundaries, per-chapter summaries, and ad spans
/// in one shot. Ported verbatim from Swift `AIChapterCompiler.systemPromptFull`.
pub(crate) const SYSTEM_PROMPT_FULL: &str = "\
You analyse podcast episode transcripts and return chapter boundaries, \
chapter summaries, and advertisement spans in a single JSON response. \
Always respond with ONLY this JSON object (no prose, no markdown fences):\n\
{\n\
  \"chapters\": [\n\
    { \"start\": <seconds>, \"title\": \"<short title>\", \"summary\": \"<1-2 sentence summary>\" }\n\
  ],\n\
  \"ads\": [\n\
    { \"start\": <seconds>, \"end\": <seconds>, \"kind\": \"preroll\"|\"midroll\"|\"postroll\" }\n\
  ]\n\
}\n\
Chapter rules:\n\
  - Produce between 4 and 12 chapters total.\n\
  - \"start\" is seconds from the beginning of the episode, integer or float.\n\
  - The first chapter must start at 0.\n\
  - Chapters must be strictly monotonic by \"start\".\n\
  - Titles are short (max 6 words), descriptive, no quotes, no episode numbers.\n\
  - \"summary\" is 1-2 sentences describing what the chapter covers.\n\
  - Skip ad reads — don't create a chapter for them.\n\
  - Prefer topic shifts over speaker changes.\n\
Ad rules:\n\
  - Only mark spans that are clearly advertisements (host-read or pre-recorded sponsor copy).\n\
  - Do NOT mark guest plugs, book recommendations, or off-topic asides.\n\
  - \"start\"/\"end\" are seconds; \"end\" must be greater than \"start\".\n\
  - Ranges must be non-overlapping and strictly increasing by \"start\".\n\
  - \"kind\": \"preroll\" if before any topical content; \"postroll\" if after; otherwise \"midroll\".\n\
  - Return an empty \"ads\" array if the episode has no ads.";

/// Build the user prompt for FULL mode.
pub(crate) fn full_user_prompt(
    episode_title: &str,
    transcript_excerpt: &str,
    duration_secs: f64,
) -> String {
    format!(
        "Episode duration: {dur} seconds.\nTitle: {title}\nTranscript (timestamped):\n{transcript}",
        dur = duration_secs as u64,
        title = episode_title,
        transcript = transcript_excerpt
    )
}

/// Parse the FULL-mode LLM response into chapters + ads.
///
/// Chapter rules (ported from Swift `parseFull`):
///   - Skips chapters with empty titles.
///   - Clamps `start` to `[0, duration_cap]`.
///   - Requires strictly-increasing starts (drops non-monotonic).
///   - Forces first chapter's start to 0.
///   - Minimum 4 chapters, maximum 12.
///
/// Ad rules (ported from Swift `validateAds`):
///   - Accepts both `start`/`end` and `start_seconds`/`end_seconds` keys.
///   - Requires `end > start`.
///   - Requires non-overlapping spans (`start >= prev_end`).
///   - Returns empty vec on parse failure (doesn't abort the chapter result).
///
/// Returns `None` when the chapter count is below the minimum threshold.
pub(crate) fn parse_full(
    response: &str,
    duration_cap: Option<f64>,
) -> Option<CompileResult> {
    let json_str = crate::llm::extract_json_object(response)?;
    let v: serde_json::Value = serde_json::from_str(json_str).ok()?;

    // --- chapters ---
    let chapters_arr = v["chapters"].as_array()?;
    let cap = duration_cap.unwrap_or(f64::MAX);
    let mut prev: f64 = -1.0;
    let mut chapters: Vec<SynthesizedChapter> = Vec::new();
    for item in chapters_arr {
        let title = item["title"].as_str().unwrap_or("").trim().to_owned();
        if title.is_empty() {
            continue;
        }
        let raw_start = item["start"].as_f64().unwrap_or(-1.0);
        let clamped = raw_start.max(0.0).min(cap);
        if clamped <= prev {
            continue;
        }
        prev = clamped;
        let summary = item["summary"]
            .as_str()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_owned);
        chapters.push(SynthesizedChapter {
            title,
            start_secs: clamped,
            summary,
        });
        if chapters.len() >= 12 {
            break;
        }
    }
    if chapters.len() < 4 {
        return None;
    }
    // Force first chapter to start at 0.
    if let Some(first) = chapters.first_mut() {
        first.start_secs = 0.0;
    }

    // --- ads ---
    let ads = parse_ads(v["ads"].as_array().map(Vec::as_slice).unwrap_or(&[]), duration_cap);

    Some(CompileResult { chapters, ads })
}

// ── ENRICH-ONLY mode (publisher chapters exist; add summaries + ads) ─────────

/// System prompt for ENRICH-ONLY mode. Ported from Swift
/// `AIChapterCompiler.systemPromptEnrichOnly`.
pub(crate) const SYSTEM_PROMPT_ENRICH_ONLY: &str = "\
You analyse podcast episode transcripts. The episode already has chapter \
boundaries supplied by the publisher (numbered below). Your job is to:\n\
  1. Write a 1-2 sentence summary for each existing chapter.\n\
  2. Identify advertisement spans inside the episode.\n\
Always respond with ONLY this JSON object (no prose, no markdown fences):\n\
{\n\
  \"summaries\": [\n\
    { \"index\": <int>, \"summary\": \"<1-2 sentence summary>\" }\n\
  ],\n\
  \"ads\": [\n\
    { \"start\": <seconds>, \"end\": <seconds>, \"kind\": \"preroll\"|\"midroll\"|\"postroll\" }\n\
  ]\n\
}\n\
Summary rules:\n\
  - One entry per chapter; \"index\" is the chapter number from the list below.\n\
  - 1-2 sentences describing what the chapter covers.\n\
  - Do NOT change titles or invent new chapters.\n\
Ad rules:\n\
  - Only mark spans that are clearly advertisements (host-read or pre-recorded sponsor copy).\n\
  - Do NOT mark guest plugs, book recommendations, or off-topic asides.\n\
  - \"start\"/\"end\" are seconds; \"end\" must be greater than \"start\".\n\
  - Ranges must be non-overlapping and strictly increasing by \"start\".\n\
  - \"kind\": \"preroll\" if before any topical content; \"postroll\" if after; otherwise \"midroll\".\n\
  - Return an empty \"ads\" array if the episode has no ads.";

/// Build the user prompt for ENRICH-ONLY mode.
pub(crate) fn enrich_only_user_prompt(
    episode_title: &str,
    transcript_excerpt: &str,
    duration_secs: f64,
    existing_chapters: &[(f64, &str)],
) -> String {
    let chapter_lines: Vec<String> = existing_chapters
        .iter()
        .enumerate()
        .map(|(idx, (start, title))| format!("[{}] {}s — {}", idx, *start as u64, title))
        .collect();
    format!(
        "Episode duration: {dur} seconds.\nTitle: {title}\n\
         Existing chapters (use these exact indices in your \"summaries\" output):\n\
         {chapters}\n\
         Transcript (timestamped):\n{transcript}",
        dur = duration_secs as u64,
        title = episode_title,
        chapters = chapter_lines.join("\n"),
        transcript = transcript_excerpt
    )
}

/// Parse the ENRICH-ONLY-mode LLM response into `(summaries_by_index, ads)`.
///
/// Ported from Swift `parseEnrichOnly`. Returns an empty `summaries` map (but
/// still parses ads) when the `summaries` array is absent or malformed.
pub(crate) fn parse_enrich_only(
    response: &str,
    duration_cap: Option<f64>,
) -> EnrichOnlyResult {
    let Some(json_str) = crate::llm::extract_json_object(response) else {
        return EnrichOnlyResult {
            summaries: Default::default(),
            ads: Vec::new(),
        };
    };
    let Ok(v) = serde_json::from_str::<serde_json::Value>(json_str) else {
        return EnrichOnlyResult {
            summaries: Default::default(),
            ads: Vec::new(),
        };
    };

    let mut summaries = std::collections::HashMap::new();
    if let Some(arr) = v["summaries"].as_array() {
        for item in arr {
            let Some(index) = item["index"].as_u64() else {
                continue;
            };
            let s = item["summary"].as_str().unwrap_or("").trim();
            if !s.is_empty() {
                summaries.insert(index as usize, s.to_owned());
            }
        }
    }

    let ads = parse_ads(v["ads"].as_array().map(Vec::as_slice).unwrap_or(&[]), duration_cap);

    EnrichOnlyResult { summaries, ads }
}

// ── Ad-span validation (shared by both modes) ────────────────────────────────

/// Validate and normalise an ad-span array from a model response.
///
/// Rules ported from Swift `AIChapterCompiler.validateAds`:
///   - Accepts both `start`/`end` and `start_seconds`/`end_seconds` keys.
///   - Clamps to `[0, duration_cap]`.
///   - Requires `end > start` (drops spans where end ≤ start).
///   - Requires non-overlapping spans in monotonically-increasing order.
pub(crate) fn parse_ads(
    items: &[serde_json::Value],
    duration_cap: Option<f64>,
) -> Vec<SynthesizedAdSpan> {
    let cap = duration_cap.unwrap_or(f64::MAX);
    let mut prev_end: f64 = -1.0;
    let mut result = Vec::new();
    for item in items {
        let raw_start = item["start"]
            .as_f64()
            .or_else(|| item["start_seconds"].as_f64());
        let raw_end = item["end"]
            .as_f64()
            .or_else(|| item["end_seconds"].as_f64());
        let (Some(s), Some(e)) = (raw_start, raw_end) else {
            continue;
        };
        let start = s.max(0.0).min(cap);
        let end = e.max(0.0).min(cap);
        if end <= start {
            continue;
        }
        if start < prev_end {
            continue;
        }
        let kind = item["kind"]
            .as_str()
            .filter(|k| matches!(*k, "preroll" | "midroll" | "postroll"))
            .unwrap_or("midroll")
            .to_owned();
        result.push(SynthesizedAdSpan {
            start_secs: start,
            end_secs: end,
            kind,
        });
        prev_end = end;
    }
    result
}

// ── Combined compile round-trips ──────────────────────────────────────────────

/// Run one LLM round-trip for the FULL compile mode.
pub fn synthesize_full(
    episode_title: &str,
    transcript_excerpt: &str,
    duration_secs: f64,
    runtime: &std::sync::Arc<tokio::runtime::Runtime>,
    store: &std::sync::Arc<std::sync::Mutex<crate::store::PodcastStore>>,
) -> Result<CompileResult, SynthError> {
    let user_prompt = full_user_prompt(episode_title, transcript_excerpt, duration_secs);
    let raw = round_trip(SYSTEM_PROMPT_FULL, &user_prompt, runtime, store)?;
    parse_full(&raw, Some(duration_secs))
        .ok_or_else(|| SynthError::Parse("FULL parse rejected (<4 valid chapters)".into()))
}

/// Run one LLM round-trip for the ENRICH-ONLY compile mode.
pub fn synthesize_enrich_only(
    episode_title: &str,
    transcript_excerpt: &str,
    duration_secs: f64,
    existing_chapters: &[(f64, &str)],
    runtime: &std::sync::Arc<tokio::runtime::Runtime>,
    store: &std::sync::Arc<std::sync::Mutex<crate::store::PodcastStore>>,
) -> Result<EnrichOnlyResult, SynthError> {
    let user_prompt = enrich_only_user_prompt(
        episode_title,
        transcript_excerpt,
        duration_secs,
        existing_chapters,
    );
    let raw = round_trip(SYSTEM_PROMPT_ENRICH_ONLY, &user_prompt, runtime, store)?;
    Ok(parse_enrich_only(&raw, Some(duration_secs)))
}

/// Single LLM round-trip shared by both modes.
fn round_trip(
    system_prompt: &str,
    user_prompt: &str,
    runtime: &std::sync::Arc<tokio::runtime::Runtime>,
    store: &std::sync::Arc<std::sync::Mutex<crate::store::PodcastStore>>,
) -> Result<String, SynthError> {
    runtime.block_on(async {
        let chapters_cfg = store
            .lock()
            .ok()
            .map(|s| s.chapter_compilation_model().to_owned())
            .unwrap_or_default();
        let (backend, req) = crate::llm::resolve_request(
            store,
            &chapters_cfg,
            CHAPTERS_MODEL,
            system_prompt,
            user_prompt,
            Vec::new(),
        )
        .map_err(|e| SynthError::Unavailable(e.to_string()))?;

        match tokio::time::timeout(REQUEST_TIMEOUT, backend.complete(&req)).await {
            Ok(Ok(resp)) => Ok(resp),
            Ok(Err(e)) => Err(SynthError::Unavailable(e.to_string())),
            Err(_) => Err(SynthError::Unavailable(format!(
                "request exceeded {}s budget",
                REQUEST_TIMEOUT.as_secs()
            ))),
        }
    })
}
