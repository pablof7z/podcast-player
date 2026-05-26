use super::*;
use chrono::Datelike;

#[test]
fn parses_canonical_rfc2822() {
    let dt = parse_rfc2822("Mon, 01 Jan 2024 12:30:45 +0000").unwrap();
    assert_eq!(dt.year(), 2024);
    assert_eq!(dt.month(), 1);
    assert_eq!(dt.day(), 1);
}

#[test]
fn parses_single_digit_day() {
    let dt = parse_rfc2822("Mon, 1 Jan 2024 12:30:45 +0000").unwrap();
    assert_eq!(dt.day(), 1);
}

#[test]
fn parses_named_timezone() {
    let dt = parse_rfc2822("Mon, 01 Jan 2024 12:30:45 GMT").unwrap();
    assert_eq!(dt.year(), 2024);
}

#[test]
fn parses_missing_seconds() {
    let dt = parse_rfc2822("Mon, 01 Jan 2024 12:30 +0000").unwrap();
    assert_eq!(dt.year(), 2024);
}

#[test]
fn tolerates_wrong_weekday() {
    // Real feeds occasionally lie about the day of week (or copy-paste
    // a template). Some chrono parsers accept this; the cascade should
    // succeed via one of the looser formats even if RFC-2822 strict
    // mode rejects the mismatch.
    let dt = parse_rfc2822("Sun, 01 Jan 2024 12:30:45 +0000");
    assert!(dt.is_some(), "feed parser should tolerate wrong weekday");
}

#[test]
fn parses_iso8601() {
    let dt = parse_rfc2822("2024-01-01T12:00:00Z").unwrap();
    assert_eq!(dt.year(), 2024);
}

#[test]
fn parses_iso8601_fractional() {
    let dt = parse_rfc2822("2024-01-01T12:00:00.123Z").unwrap();
    assert_eq!(dt.year(), 2024);
}

#[test]
fn returns_none_for_garbage() {
    assert!(parse_rfc2822("not a date").is_none());
    assert!(parse_rfc2822("").is_none());
    assert!(parse_rfc2822("   ").is_none());
}
