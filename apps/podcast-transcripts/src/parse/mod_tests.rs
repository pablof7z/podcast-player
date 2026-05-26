use super::*;

#[test]
fn parses_three_part_timestamp() {
    let t = parse_timestamp("01:02:03.500").unwrap();
    assert!((t - 3723.5).abs() < 1e-9);
}

#[test]
fn parses_two_part_timestamp() {
    let t = parse_timestamp("02:30.000").unwrap();
    assert!((t - 150.0).abs() < 1e-9);
}

#[test]
fn parses_srt_comma_decimal() {
    let t = parse_timestamp("00:00:01,250").unwrap();
    assert!((t - 1.25).abs() < 1e-9);
}

#[test]
fn rejects_garbage_timestamp() {
    assert!(matches!(
        parse_timestamp("not-a-time"),
        Err(ParseError::MalformedTiming(_))
    ));
}

#[test]
fn normalises_crlf() {
    let input = "a\r\nb\rc\nd";
    assert_eq!(normalise_newlines(input), "a\nb\nc\nd");
}
