use podcast_core::Chapter;
use uuid::Uuid;

const AUTOSNIP_LOOKBACK_SECS: f64 = 90.0;
const AUTOSNIP_LEAD_SECS: f64 = 15.0;
const AUTOSNIP_FALLBACK_LOOKBACK_SECS: f64 = 30.0;
const AUTOSNIP_FALLBACK_LEAD_SECS: f64 = 30.0;
const AUTOSNIP_TARGET_MIN_SECS: f64 = 30.0;
const AUTOSNIP_TARGET_MAX_SECS: f64 = 60.0;
const AUTOSNIP_AFTER_TAP_GRACE_SECS: f64 = 5.0;
const QUOTE_TARGET_MIN_SECS: f64 = 10.0;
const QUOTE_TARGET_MAX_SECS: f64 = 25.0;
const QUOTE_AFTER_TAP_GRACE_SECS: f64 = 2.0;

#[derive(Debug, PartialEq)]
pub(crate) struct AutoSnipBounds {
    pub(crate) start_secs: f64,
    pub(crate) end_secs: f64,
    pub(crate) transcript_text: String,
    pub(crate) speaker: Option<String>,
    pub(crate) status: String,
}

pub(crate) struct ClipText {
    pub(crate) transcript_text: String,
    pub(crate) speaker: Option<String>,
}

pub(crate) fn fallback_auto_snip_bounds(pos: f64, duration: Option<f64>) -> (f64, f64) {
    let raw_start = pos - AUTOSNIP_FALLBACK_LOOKBACK_SECS;
    let raw_end = pos + AUTOSNIP_FALLBACK_LEAD_SECS;
    let start = raw_start.max(0.0);
    let end = match duration {
        Some(d) if d > 0.0 => raw_end.min(d),
        _ => raw_end,
    };
    (start, end)
}

pub(crate) fn resolve_auto_snip_bounds(
    entries: &[podcast_transcripts::TranscriptEntry],
    playhead_secs: f64,
    duration: Option<f64>,
) -> Option<AutoSnipBounds> {
    resolve_transcript_bounds(
        entries,
        playhead_secs,
        duration,
        AUTOSNIP_TARGET_MIN_SECS,
        AUTOSNIP_TARGET_MAX_SECS,
        AUTOSNIP_AFTER_TAP_GRACE_SECS,
        "transcript_refined",
    )
}

pub(crate) fn resolve_quote_bounds(
    entries: &[podcast_transcripts::TranscriptEntry],
    playhead_secs: f64,
    duration: Option<f64>,
) -> Option<AutoSnipBounds> {
    resolve_transcript_bounds(
        entries,
        playhead_secs,
        duration,
        QUOTE_TARGET_MIN_SECS,
        QUOTE_TARGET_MAX_SECS,
        QUOTE_AFTER_TAP_GRACE_SECS,
        "quote_resolved",
    )
}

pub(crate) fn resolve_manual_clip_bounds(
    entries: &[podcast_transcripts::TranscriptEntry],
    start_secs: f64,
    end_secs: f64,
    duration: Option<f64>,
) -> Option<AutoSnipBounds> {
    let mut selected: Vec<&podcast_transcripts::TranscriptEntry> = entries
        .iter()
        .filter(|entry| {
            entry.end_secs > entry.start_secs
                && entry.end_secs > start_secs
                && entry.start_secs < end_secs
                && !entry.text.trim().is_empty()
        })
        .collect();
    if selected.is_empty() {
        return None;
    }
    selected.sort_by(|a, b| a.start_secs.total_cmp(&b.start_secs));
    let start_secs = selected.first()?.start_secs.max(0.0);
    let end_secs = clamp_to_duration(selected.last()?.end_secs, duration);
    if end_secs <= start_secs {
        return None;
    }
    Some(AutoSnipBounds {
        start_secs,
        end_secs,
        transcript_text: selected
            .iter()
            .map(|entry| entry.text.trim())
            .collect::<Vec<_>>()
            .join(" "),
        speaker: dominant_speaker(&selected),
        status: "manual".to_owned(),
    })
}

fn resolve_transcript_bounds(
    entries: &[podcast_transcripts::TranscriptEntry],
    playhead_secs: f64,
    duration: Option<f64>,
    target_min_secs: f64,
    target_max_secs: f64,
    after_tap_grace_secs: f64,
    status: &str,
) -> Option<AutoSnipBounds> {
    let lo = (playhead_secs - AUTOSNIP_LOOKBACK_SECS).max(0.0);
    let hi = clamp_to_duration(playhead_secs + AUTOSNIP_LEAD_SECS, duration);
    let mut window: Vec<&podcast_transcripts::TranscriptEntry> = entries
        .iter()
        .filter(|entry| {
            let end = entry.end_secs;
            end > entry.start_secs
                && end >= lo
                && entry.start_secs <= hi
                && !entry.text.trim().is_empty()
        })
        .collect();
    window.sort_by(|a, b| a.start_secs.total_cmp(&b.start_secs));
    if window.is_empty() {
        return None;
    }
    let anchor = window
        .iter()
        .rposition(|entry| entry.start_secs <= playhead_secs)
        .unwrap_or(0);
    let mut start = anchor;
    let mut end = anchor;
    while end + 1 < window.len()
        && window[end].end_secs < playhead_secs + after_tap_grace_secs
    {
        let next_end = window[end + 1].end_secs;
        if next_end - window[start].start_secs > target_max_secs {
            break;
        }
        end += 1;
    }
    while start > 0 {
        let current_end = window[end].end_secs;
        let candidate_start = window[start - 1].start_secs;
        if current_end - candidate_start > target_max_secs {
            break;
        }
        start -= 1;
        if current_end - window[start].start_secs >= target_min_secs {
            break;
        }
    }
    let start_secs = window[start].start_secs.max(0.0);
    let end_secs = clamp_to_duration(window[end].end_secs, duration);
    if end_secs <= start_secs {
        return None;
    }
    let selected = &window[start..=end];
    Some(AutoSnipBounds {
        start_secs,
        end_secs,
        transcript_text: selected
            .iter()
            .map(|entry| entry.text.trim())
            .collect::<Vec<_>>()
            .join(" "),
        speaker: dominant_speaker(selected),
        status: status.to_owned(),
    })
}

pub(crate) fn usable_clip_id(candidate: Option<String>) -> String {
    candidate
        .filter(|id| Uuid::parse_str(id).is_ok())
        .unwrap_or_else(|| Uuid::new_v4().to_string())
}

/// Snap a manual clip `[start_secs, end_secs]` to the nearest transcript
/// utterance boundaries in `entries`.
///
/// Returns `Some((snapped_start, snapped_end))` when entries are available;
/// returns `None` when no entries are provided or the list is empty or the
/// snapped range is degenerate (end <= start).
///
/// ## Snapping rules
///
/// - **Start**: find the *last* entry whose `start_secs` is ≤ `start_secs`
///   (backward bias). If `start_secs` is before all entries, snap to the
///   first entry's start.
/// - **End**: find the *first* entry whose `end_secs` is ≥ `end_secs`
///   (forward bias). If `end_secs` is past all entries, snap to the last
///   entry's end.
/// - The resulting end is clamped to `duration` when provided.
/// - If the snapped range is degenerate (`snap_end <= snap_start`), `None`
///   is returned.
///
/// This is the pure, testable core of the utterance-boundary snapping policy
/// used by both auto-snip refinement and manual clip creation.
pub(crate) fn transcript_refine(
    start_secs: f64,
    end_secs: f64,
    entries: Option<&[podcast_transcripts::TranscriptEntry]>,
    duration: Option<f64>,
) -> Option<(f64, f64)> {
    let entries = entries?;
    if entries.is_empty() {
        return None;
    }
    // Sort a local view by start_secs so unsorted input still works.
    let mut sorted: Vec<&podcast_transcripts::TranscriptEntry> = entries.iter().collect();
    sorted.sort_by(|a, b| a.start_secs.total_cmp(&b.start_secs));

    // Snap start: last entry with start_secs <= input start (backward bias).
    let snap_start = sorted
        .iter()
        .rfind(|e| e.start_secs <= start_secs)
        .map(|e| e.start_secs)
        .unwrap_or_else(|| sorted[0].start_secs); // before all entries → first

    // Snap end: first entry with end_secs >= input end (forward bias).
    let snap_end_raw = sorted
        .iter()
        .find(|e| e.end_secs >= end_secs)
        .map(|e| e.end_secs)
        .unwrap_or_else(|| sorted.last().unwrap().end_secs); // past all entries → last

    let snap_end = clamp_to_duration(snap_end_raw, duration);
    if snap_end <= snap_start {
        return None;
    }
    Some((snap_start, snap_end))
}

/// Snap `pos_secs` to the chapter boundaries of the episode, returning
/// `(start, end, Option<chapter_title>)`.
///
/// - When `chapters` is `None` or `Some(&[])`, falls back to the ±30 s
///   window (same as `fallback_auto_snip_bounds`).
/// - When chapters are present, the chapter containing `pos_secs` is used.
///   The `end` is the start of the NEXT chapter (or `duration` for the last
///   chapter). `title` is `Some(chapter.title)` for a matched chapter, `None`
///   for the fallback path.
pub(crate) fn chapter_snap(
    pos_secs: f64,
    chapters: Option<&[Chapter]>,
    duration: Option<f64>,
) -> (f64, f64, Option<String>) {
    let chapters = match chapters {
        Some(chs) if !chs.is_empty() => chs,
        _ => {
            let (s, e) = fallback_auto_snip_bounds(pos_secs, duration);
            return (s, e, None);
        }
    };
    // Sort by start_secs so unsorted input still works.
    let mut sorted: Vec<_> = chapters.iter().collect();
    sorted.sort_by(|a, b| a.start_secs.total_cmp(&b.start_secs));

    // When pos_secs is before the first chapter, produce a pre-chapter segment
    // [0, first_chapter.start_secs] with no title.
    if pos_secs < sorted[0].start_secs {
        let end_secs = clamp_to_duration(sorted[0].start_secs, duration);
        return (0.0, end_secs, None);
    }

    // Find the last chapter whose start_secs <= pos_secs.
    let idx = sorted
        .iter()
        .rposition(|c| c.start_secs <= pos_secs)
        .unwrap_or(0);

    let ch = sorted[idx];
    let start_secs = ch.start_secs.max(0.0);
    let end_secs = if idx + 1 < sorted.len() {
        let next_start = sorted[idx + 1].start_secs;
        clamp_to_duration(next_start, duration)
    } else {
        // Last chapter: use episode duration.
        match duration {
            Some(d) if d > start_secs => d,
            _ => clamp_to_duration(pos_secs + AUTOSNIP_FALLBACK_LEAD_SECS, duration),
        }
    };
    // Guard against degenerate range (e.g. last chapter starts at duration).
    // Fall back to ±30 s when the derived range is empty.
    if end_secs <= start_secs {
        let (s, e) = fallback_auto_snip_bounds(pos_secs, duration);
        return (s, e, None);
    }

    let title = if ch.title.is_empty() {
        None
    } else {
        Some(ch.title.clone())
    };
    (start_secs, end_secs, title)
}

fn clamp_to_duration(value: f64, duration: Option<f64>) -> f64 {
    match duration {
        Some(d) if d > 0.0 => value.min(d),
        _ => value,
    }
}

fn dominant_speaker(entries: &[&podcast_transcripts::TranscriptEntry]) -> Option<String> {
    let first = entries.first()?.speaker.as_ref()?;
    if entries.iter().all(|entry| entry.speaker.as_ref() == Some(first)) {
        Some(first.clone())
    } else {
        None
    }
}
