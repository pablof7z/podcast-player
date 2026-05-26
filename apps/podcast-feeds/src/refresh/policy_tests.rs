use super::*;

fn t(s: &str) -> DateTime<Utc> {
    DateTime::parse_from_rfc3339(s).unwrap().with_timezone(&Utc)
}

#[test]
fn manual_never_refreshes() {
    let now = t("2026-01-01T12:00:00Z");
    let last = t("2020-01-01T00:00:00Z");
    assert!(!should_refresh(Some(last), RefreshPolicy::Manual, now));
    assert!(!should_refresh(None, RefreshPolicy::Manual, now));
}

#[test]
fn never_refreshed_returns_true_for_scheduled() {
    let now = t("2026-01-01T12:00:00Z");
    assert!(should_refresh(None, RefreshPolicy::Hourly, now));
    assert!(should_refresh(None, RefreshPolicy::Daily, now));
}

#[test]
fn hourly_respects_one_hour() {
    let now = t("2026-01-01T12:00:00Z");
    let just_now = t("2026-01-01T11:30:00Z");
    let an_hour_ago = t("2026-01-01T11:00:00Z");
    assert!(!should_refresh(Some(just_now), RefreshPolicy::Hourly, now));
    assert!(should_refresh(Some(an_hour_ago), RefreshPolicy::Hourly, now));
}

#[test]
fn every_4h_threshold() {
    let now = t("2026-01-01T12:00:00Z");
    let three_hours_ago = t("2026-01-01T09:00:00Z");
    let four_hours_ago = t("2026-01-01T08:00:00Z");
    assert!(!should_refresh(Some(three_hours_ago), RefreshPolicy::Every4h, now));
    assert!(should_refresh(Some(four_hours_ago), RefreshPolicy::Every4h, now));
}

#[test]
fn daily_threshold() {
    let now = t("2026-01-02T12:00:00Z");
    let twelve_hours_ago = t("2026-01-02T00:00:00Z");
    let a_day_ago = t("2026-01-01T12:00:00Z");
    assert!(!should_refresh(Some(twelve_hours_ago), RefreshPolicy::Daily, now));
    assert!(should_refresh(Some(a_day_ago), RefreshPolicy::Daily, now));
}

#[test]
fn etag_cache_round_trip() {
    let value = EtagCache::with_headers(
        t("2026-01-01T12:00:00Z"),
        Some("\"abc123\"".into()),
        Some("Wed, 31 Dec 2025 23:00:00 GMT".into()),
    );
    let json = serde_json::to_string(&value).unwrap();
    let back: EtagCache = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}
