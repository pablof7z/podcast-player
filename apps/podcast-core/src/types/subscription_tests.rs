use super::*;
use url::Url;
use uuid::Uuid;
fn fixture_episode() -> Episode {
    Episode::new(
        PodcastId::generate(),
        "https://example.com/feed.xml",
        "guid-1",
        "Pilot",
        Url::parse("https://example.com/audio.mp3").unwrap(),
        Utc::now(),
    )
}
#[test]
fn policy_round_trip() {
    let value = AutoDownloadPolicy {
        mode: AutoDownloadMode::LatestN { count: 5 },
        wifi_only: false,
    };
    let json = serde_json::to_string(&value).unwrap();
    let back: AutoDownloadPolicy = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}
#[test]
fn subscription_round_trip() {
    let value = PodcastSubscription::new(PodcastId::new(Uuid::nil()));
    let json = serde_json::to_string(&value).unwrap();
    let back: PodcastSubscription = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}
#[test]
fn should_auto_download_off_returns_false() {
    let policy = AutoDownloadPolicy::new(AutoDownloadMode::Off, true);
    assert!(!policy.should_auto_download(&fixture_episode()));
}
#[test]
fn should_auto_download_all_new_returns_true() {
    let policy = AutoDownloadPolicy::new(AutoDownloadMode::AllNew, true);
    assert!(policy.should_auto_download(&fixture_episode()));
}
#[test]
fn should_auto_download_latest_n_with_positive_count_returns_true() {
    let policy =
        AutoDownloadPolicy::new(AutoDownloadMode::LatestN { count: 5 }, true);
    assert!(policy.should_auto_download(&fixture_episode()));
}
#[test]
fn should_auto_download_latest_n_zero_returns_false() {
    let policy =
        AutoDownloadPolicy::new(AutoDownloadMode::LatestN { count: 0 }, true);
    assert!(!policy.should_auto_download(&fixture_episode()));
}
#[test]
fn should_auto_download_ignores_wifi_only_in_m4a() {
    // M4.A doesn't see the network type; M4.B's policy layer does.
    // Document the simplification with a regression test so a future
    // edit doesn't quietly add a wifi check here.
    let policy = AutoDownloadPolicy::new(AutoDownloadMode::AllNew, true);
    assert!(policy.should_auto_download(&fixture_episode()));
    let policy = AutoDownloadPolicy::new(AutoDownloadMode::AllNew, false);
    assert!(policy.should_auto_download(&fixture_episode()));
}

