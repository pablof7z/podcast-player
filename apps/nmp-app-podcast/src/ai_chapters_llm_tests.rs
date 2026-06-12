//! Tests for [`super::ai_chapters_llm`] — JSON parsing + array extraction.
//!
//! The live `synthesize_chapters` round-trip is not exercised here (it needs a
//! running Ollama instance); we test the deterministic parse/extract seam that
//! the round-trip funnels its response through.

use super::{
    extract_json_array, parse_ads, parse_chapters, parse_enrich_only, parse_full,
    synthesize_chapters, SynthError, SynthesizedChapter,
};
use crate::store::PodcastStore;
use std::sync::{Arc, Mutex};

// ── parse_chapters (legacy chapters-only array format) ────────────────────────

#[test]
fn parse_valid_json_chapters() {
    let json =
        r#"[{"title":"Intro and welcome","start_secs":0.0},{"title":"Deep dive on Rust","start_secs":120.5}]"#;
    let chapters = parse_chapters(json).expect("valid JSON should parse");
    assert_eq!(
        chapters,
        vec![
            SynthesizedChapter {
                title: "Intro and welcome".into(),
                start_secs: 0.0,
                summary: None,
            },
            SynthesizedChapter {
                title: "Deep dive on Rust".into(),
                start_secs: 120.5,
                summary: None,
            },
        ]
    );
}

#[test]
fn parse_with_preamble_ignores_extra_text() {
    let response = r#"Sure! Here are your chapters:
[{"title":"Opening remarks","start_secs":0.0},{"title":"Guest interview","start_secs":300.0}]
Hope that helps!"#;
    let extracted = extract_json_array(response).expect("array present");
    assert!(extracted.starts_with('['));
    assert!(extracted.ends_with(']'));

    let chapters = parse_chapters(response).expect("array embedded in prose should parse");
    assert_eq!(chapters.len(), 2);
    assert_eq!(chapters[0].title, "Opening remarks");
    assert_eq!(chapters[1].start_secs, 300.0);
}

#[test]
fn parse_rejects_unusable_responses() {
    assert!(parse_chapters("I cannot help with that.").is_err());
    assert!(parse_chapters(r#"[{"name":"oops"}]"#).is_err());
    assert!(parse_chapters("[]").is_err());
    assert!(parse_chapters(r#"[{"title":"x","start_secs":}]"#).is_err());
}

// ── parse_full (FULL mode: chapters + summaries + ads) ────────────────────────

#[test]
fn parse_full_valid_payload() {
    let raw = r#"{
        "chapters": [
            { "start": 0, "title": "Introduction", "summary": "The host introduces the guests." },
            { "start": 120, "title": "Deep Dive", "summary": "Team discusses distributed systems." },
            { "start": 300, "title": "Q and A", "summary": "Listener questions answered." },
            { "start": 480, "title": "Wrap Up", "summary": "Final thoughts shared." }
        ],
        "ads": [
            { "start": 60, "end": 90, "kind": "midroll" }
        ]
    }"#;
    let result = parse_full(raw, Some(600.0)).expect("valid FULL payload should parse");
    assert_eq!(result.chapters.len(), 4);
    assert_eq!(result.chapters[0].title, "Introduction");
    assert_eq!(result.chapters[0].start_secs, 0.0);
    assert_eq!(
        result.chapters[0].summary.as_deref(),
        Some("The host introduces the guests.")
    );
    assert_eq!(result.chapters[1].start_secs, 120.0);
    assert_eq!(result.ads.len(), 1);
    assert_eq!(result.ads[0].start_secs, 60.0);
    assert_eq!(result.ads[0].end_secs, 90.0);
    assert_eq!(result.ads[0].kind, "midroll");
}

#[test]
fn parse_full_forces_first_chapter_to_zero() {
    // The LLM may return 5 as the first start (e.g. "after intro music").
    // The Swift compiler and we must clamp it to 0.
    let raw = r#"{
        "chapters": [
            { "start": 5, "title": "Intro" },
            { "start": 100, "title": "Topic" },
            { "start": 200, "title": "More" },
            { "start": 400, "title": "End" }
        ],
        "ads": []
    }"#;
    let result = parse_full(raw, Some(600.0)).expect("should parse");
    assert_eq!(result.chapters[0].start_secs, 0.0, "first chapter forced to 0");
}

#[test]
fn parse_full_rejects_fewer_than_4_valid_chapters() {
    let raw = r#"{"chapters": [{"start":0,"title":"Only One"}], "ads": []}"#;
    assert!(
        parse_full(raw, Some(600.0)).is_none(),
        "fewer than 4 chapters must return None"
    );
}

#[test]
fn parse_full_drops_non_monotonic_chapters() {
    let raw = r#"{
        "chapters": [
            { "start": 0, "title": "A" },
            { "start": 100, "title": "B" },
            { "start": 50, "title": "C - bad, goes backwards" },
            { "start": 200, "title": "D" },
            { "start": 300, "title": "E" }
        ],
        "ads": []
    }"#;
    let result = parse_full(raw, Some(600.0)).expect("4+ valid chapters should parse");
    // "C" (start=50 < prev=100) must be dropped; result has A, B, D, E.
    assert_eq!(result.chapters.len(), 4);
    assert_eq!(result.chapters[2].title, "D");
}

#[test]
fn parse_full_empty_ads_array_is_valid() {
    let raw = r#"{
        "chapters": [
            {"start":0,"title":"Intro"},
            {"start":60,"title":"Main"},
            {"start":120,"title":"Side"},
            {"start":300,"title":"End"}
        ],
        "ads": []
    }"#;
    let result = parse_full(raw, Some(600.0)).expect("should parse");
    assert!(result.ads.is_empty());
}

#[test]
fn parse_full_missing_ads_field_is_valid() {
    // The model may omit "ads" entirely — treat as empty.
    let raw = r#"{
        "chapters": [
            {"start":0,"title":"Intro"},
            {"start":60,"title":"Main"},
            {"start":120,"title":"Side"},
            {"start":300,"title":"End"}
        ]
    }"#;
    let result = parse_full(raw, Some(600.0)).expect("should parse");
    assert!(result.ads.is_empty());
}

// ── parse_enrich_only (ENRICH-ONLY mode: summaries by index + ads) ────────────

#[test]
fn parse_enrich_only_valid_payload() {
    let raw = r#"{
        "summaries": [
            { "index": 0, "summary": "The show opens with a recap." },
            { "index": 1, "summary": "Deep-dive on the main topic." }
        ],
        "ads": [
            { "start": 30, "end": 60, "kind": "preroll" }
        ]
    }"#;
    let result = parse_enrich_only(raw, Some(600.0));
    assert_eq!(result.summaries.len(), 2);
    assert_eq!(
        result.summaries[&0].as_str(),
        "The show opens with a recap."
    );
    assert_eq!(
        result.summaries[&1].as_str(),
        "Deep-dive on the main topic."
    );
    assert_eq!(result.ads.len(), 1);
    assert_eq!(result.ads[0].kind, "preroll");
}

#[test]
fn parse_enrich_only_garbage_returns_empty_summaries_and_ads() {
    // A malformed response must not panic; returns empty structs.
    let result = parse_enrich_only("totally not json", None);
    assert!(result.summaries.is_empty());
    assert!(result.ads.is_empty());
}

#[test]
fn parse_enrich_only_no_ads_field_returns_empty_ads() {
    let raw = r#"{"summaries": [{"index":0,"summary":"First chapter."}]}"#;
    let result = parse_enrich_only(raw, Some(300.0));
    assert_eq!(result.summaries.len(), 1);
    assert!(result.ads.is_empty());
}

// ── parse_ads validation (ad-span rules ported from Swift validateAds) ────────

/// Helper: build a minimal JSON Value for a single ad item.
fn ad_item(start: f64, end: f64, kind: &str) -> serde_json::Value {
    serde_json::json!({ "start": start, "end": end, "kind": kind })
}

#[test]
fn parse_ads_accepts_valid_non_overlapping_spans() {
    let items = vec![
        ad_item(30.0, 60.0, "preroll"),
        ad_item(120.0, 150.0, "midroll"),
    ];
    let ads = parse_ads(&items, Some(600.0));
    assert_eq!(ads.len(), 2);
    assert_eq!(ads[0].start_secs, 30.0);
    assert_eq!(ads[0].end_secs, 60.0);
    assert_eq!(ads[0].kind, "preroll");
    assert_eq!(ads[1].start_secs, 120.0);
}

#[test]
fn parse_ads_rejects_span_where_end_le_start() {
    let items = vec![ad_item(100.0, 50.0, "midroll")]; // end < start
    let ads = parse_ads(&items, Some(600.0));
    assert!(ads.is_empty(), "end <= start must be rejected");

    let items2 = vec![ad_item(100.0, 100.0, "midroll")]; // end == start
    let ads2 = parse_ads(&items2, Some(600.0));
    assert!(ads2.is_empty(), "end == start must be rejected");
}

#[test]
fn parse_ads_rejects_overlapping_spans() {
    // Second span starts before the first ends — must be dropped.
    let items = vec![
        ad_item(30.0, 90.0, "midroll"),
        ad_item(60.0, 120.0, "midroll"), // overlaps with [30, 90)
    ];
    let ads = parse_ads(&items, Some(600.0));
    assert_eq!(ads.len(), 1, "overlapping second span must be dropped");
    assert_eq!(ads[0].start_secs, 30.0);
}

#[test]
fn parse_ads_accepts_legacy_start_end_seconds_keys() {
    // The legacy detector prompt used start_seconds/end_seconds — must tolerate both.
    let items = vec![
        serde_json::json!({ "start_seconds": 10.0, "end_seconds": 40.0, "kind": "midroll" })
    ];
    let ads = parse_ads(&items, Some(600.0));
    assert_eq!(ads.len(), 1);
    assert_eq!(ads[0].start_secs, 10.0);
    assert_eq!(ads[0].end_secs, 40.0);
}

#[test]
fn parse_ads_uses_midroll_as_default_kind() {
    let items = vec![serde_json::json!({ "start": 20.0, "end": 50.0 })]; // no "kind"
    let ads = parse_ads(&items, Some(600.0));
    assert_eq!(ads.len(), 1);
    assert_eq!(ads[0].kind, "midroll");
}

#[test]
fn parse_ads_clamps_to_duration_cap() {
    let items = vec![ad_item(500.0, 700.0, "postroll")]; // end > duration
    let ads = parse_ads(&items, Some(600.0));
    assert_eq!(ads.len(), 1);
    assert_eq!(ads[0].end_secs, 600.0, "end must be clamped to duration_cap");
}

#[test]
fn parse_ads_empty_input_returns_empty() {
    let ads = parse_ads(&[], Some(600.0));
    assert!(ads.is_empty());
}

// ── SynthError discriminator ──────────────────────────────────────────────────

#[test]
fn synth_error_discriminates_unavailable_from_parse() {
    assert!(SynthError::Unavailable("connection refused".into()).is_unavailable());
    assert!(!SynthError::Parse("no JSON array".into()).is_unavailable());
    assert_eq!(SynthError::Parse("boom".into()).message(), "boom");
}

// ── synthesize_chapters offline test ─────────────────────────────────────────

#[test]
fn synthesize_offline_is_unavailable() {
    let rt = std::sync::Arc::new(tokio::runtime::Runtime::new().unwrap());
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let result = synthesize_chapters("Ep", "some transcript text", 600.0, 5, &rt, &store);
    match result {
        Err(e) => assert!(
            e.is_unavailable(),
            "offline LLM must classify as Unavailable, got: {e:?}"
        ),
        Ok(_) => {}
    }
}

// ── Live LLM tests (ignored by default) ──────────────────────────────────────

#[test]
#[ignore = "requires a live LLM instance"]
fn synthesize_against_live_llm_returns_prose_titles() {
    let rt = std::sync::Arc::new(tokio::runtime::Runtime::new().unwrap());
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let transcript = "Welcome back to the show. Today we sit down with a longtime \
        systems engineer to talk about the hard-won lessons of scaling \
        distributed databases. We start with the early architecture choices \
        that seemed clever but aged poorly, then move into how the team \
        rebuilt the storage layer twice, and finally we cover what they would \
        tell their younger selves about premature optimization and technical \
        debt.";

    let result = synthesize_chapters(
        "Lessons from Scaling Databases",
        transcript,
        3600.0,
        5,
        &rt,
        &store,
    );

    let chapters = result.expect("live LLM should return chapters");
    eprintln!("LIVE CHAPTERS: {chapters:#?}");
    assert!(!chapters.is_empty());
    assert_eq!(chapters[0].start_secs, 0.0);
    for w in chapters.windows(2) {
        assert!(w[1].start_secs > w[0].start_secs);
    }
    for c in &chapters {
        assert!(!c.title.starts_with("Chapter "));
    }
}
