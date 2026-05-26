use super::*;
use chrono::Utc;
use podcast_core::{DownloadState, PodcastId, TranscriptSource, TranscriptState, TriageDecision};
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

#[test]
fn merge_preserves_existing_position_for_matching_ids() {
    let existing = vec![ep("A", 42.0), ep("B", 100.0)];
    let mut fresh = existing
        .iter()
        .map(|e| {
            let mut e2 = e.clone();
            e2.position_secs = 0.0;
            e2
        })
        .collect::<Vec<_>>();
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

#[test]
fn merge_preserves_played_flag() {
    let mut existing = ep("A", 0.0);
    existing.played = true;
    let mut fresh = existing.clone();
    fresh.played = false; // feed never sets played

    let merged = merge_episodes(vec![fresh], vec![existing]);
    assert!(merged[0].played, "played flag must survive a feed refresh");
}

#[test]
fn merge_preserves_is_starred_flag() {
    let mut existing = ep("A", 0.0);
    existing.is_starred = true;
    let mut fresh = existing.clone();
    fresh.is_starred = false;

    let merged = merge_episodes(vec![fresh], vec![existing]);
    assert!(merged[0].is_starred, "starred flag must survive a feed refresh");
}

#[test]
fn merge_preserves_triage_state() {
    let mut existing = ep("A", 0.0);
    existing.triage_decision = Some(TriageDecision::Inbox);
    existing.triage_rationale = Some("interesting tech".into());
    existing.triage_is_hero = true;
    let mut fresh = existing.clone();
    fresh.triage_decision = None;
    fresh.triage_rationale = None;
    fresh.triage_is_hero = false;

    let merged = merge_episodes(vec![fresh], vec![existing]);
    assert_eq!(merged[0].triage_decision, Some(TriageDecision::Inbox));
    assert_eq!(merged[0].triage_rationale.as_deref(), Some("interesting tech"));
    assert!(merged[0].triage_is_hero);
}

#[test]
fn merge_preserves_download_state() {
    let mut existing = ep("A", 0.0);
    existing.download_state = DownloadState::Downloaded {
        local_file_url: Url::parse("file:///tmp/a.mp3").unwrap(),
        byte_count: 12_345_678,
    };
    let mut fresh = existing.clone();
    fresh.download_state = DownloadState::NotDownloaded; // feed resets to default

    let merged = merge_episodes(vec![fresh], vec![existing]);
    assert!(
        matches!(&merged[0].download_state, DownloadState::Downloaded { .. }),
        "download state must survive a feed refresh"
    );
}

#[test]
fn merge_preserves_transcript_state() {
    let mut existing = ep("A", 0.0);
    existing.transcript_state = TranscriptState::Ready {
        source: TranscriptSource::Scribe,
    };
    let mut fresh = existing.clone();
    fresh.transcript_state = TranscriptState::None;

    let merged = merge_episodes(vec![fresh], vec![existing]);
    assert!(
        matches!(&merged[0].transcript_state, TranscriptState::Ready { .. }),
        "transcript state must survive a feed refresh"
    );
}

#[test]
fn merge_preserves_metadata_indexed_flag() {
    let mut existing = ep("A", 0.0);
    existing.metadata_indexed = true;
    let mut fresh = existing.clone();
    fresh.metadata_indexed = false;

    let merged = merge_episodes(vec![fresh], vec![existing]);
    assert!(
        merged[0].metadata_indexed,
        "metadata_indexed must survive a feed refresh to avoid re-indexing"
    );
}

#[test]
fn merge_new_episode_has_default_user_state() {
    // A brand-new episode in the feed (no prior local record) must come
    // through with default state — played=false, is_starred=false, etc.
    let new_ep = ep("New", 0.0);
    let unrelated = ep("Existing", 30.0);
    let merged = merge_episodes(vec![new_ep], vec![unrelated]);
    assert!(!merged[0].played);
    assert!(!merged[0].is_starred);
    assert_eq!(merged[0].triage_decision, None);
}
