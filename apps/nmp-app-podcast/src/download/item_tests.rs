use super::*;
#[test]
fn holds_slot_only_for_active_and_paused() {
    assert!(DownloadItemState::Active.holds_slot());
    assert!(DownloadItemState::Paused.holds_slot());
    assert!(!DownloadItemState::Queued.holds_slot());
    assert!(!DownloadItemState::Completed.holds_slot());
    assert!(!DownloadItemState::Failed.holds_slot());
    assert!(!DownloadItemState::Cancelled.holds_slot());
}
#[test]
fn is_terminal_only_for_completed_failed_cancelled() {
    assert!(!DownloadItemState::Queued.is_terminal());
    assert!(!DownloadItemState::Active.is_terminal());
    assert!(!DownloadItemState::Paused.is_terminal());
    assert!(DownloadItemState::Completed.is_terminal());
    assert!(DownloadItemState::Failed.is_terminal());
    assert!(DownloadItemState::Cancelled.is_terminal());
}
#[test]
fn progress_fraction_handles_unknown_total() {
    let item = DownloadItem::queued("ep-1", "https://ex.com/a.mp3");
    assert_eq!(item.progress_fraction(), 0.0);
}
#[test]
fn progress_fraction_clamps_to_unit() {
    let mut item = DownloadItem::queued("ep-1", "https://ex.com/a.mp3");
    item.bytes_downloaded = 1000;
    item.total_bytes = Some(500); // pathological — clamp.
    assert_eq!(item.progress_fraction(), 1.0);
}
#[test]
fn progress_fraction_half_when_half_done() {
    let mut item = DownloadItem::queued("ep-1", "https://ex.com/a.mp3");
    item.bytes_downloaded = 50;
    item.total_bytes = Some(100);
    assert!((item.progress_fraction() - 0.5).abs() < 1e-6);
}
#[test]
fn item_round_trips_through_serde() {
    let mut item = DownloadItem::queued("ep-1", "https://ex.com/a.mp3");
    item.state = DownloadItemState::Active;
    item.bytes_downloaded = 1024;
    item.total_bytes = Some(8192);
    let json = serde_json::to_string(&item).expect("encode");
    let decoded: DownloadItem = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, item);
}

