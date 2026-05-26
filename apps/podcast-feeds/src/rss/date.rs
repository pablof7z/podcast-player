use chrono::{DateTime, NaiveDateTime, TimeZone, Utc};

/// Parses common RFC-2822 / RFC-1123 forms emitted by RSS publishers plus
/// ISO-8601 fallbacks for Atom-flavoured feeds. The cascade mirrors the
/// legacy Swift `DateParsing.parseRFC822`: try strict RFC-2822 first, then
/// progressively looser variants (no seconds, no timezone), then ISO-8601
/// with and without fractional seconds.
pub fn parse_rfc2822(raw: &str) -> Option<DateTime<Utc>> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }

    if let Ok(dt) = DateTime::parse_from_rfc2822(trimmed) {
        return Some(dt.with_timezone(&Utc));
    }

    // Strict RFC-2822 rejects mismatched weekday (e.g. publisher copy-paste
    // bugs that label a date "Sun" when the date is actually a Monday). The
    // legacy Swift `DateFormatter` is lenient about this — strip a leading
    // weekday token so the looser cascade has a chance.
    let weekday_stripped: Option<String> = strip_leading_weekday(trimmed);
    let candidates: [&str; 2] = [
        trimmed,
        weekday_stripped.as_deref().unwrap_or(trimmed),
    ];

    for candidate in candidates {
        for fmt in RFC822_OFFSET_FORMATS {
            if let Ok(dt) = DateTime::parse_from_str(candidate, fmt) {
                return Some(dt.with_timezone(&Utc));
            }
        }
        for fmt in RFC822_NAIVE_FORMATS {
            if let Ok(naive) = NaiveDateTime::parse_from_str(candidate, fmt) {
                return Some(Utc.from_utc_datetime(&naive));
            }
        }
    }

    if let Ok(dt) = DateTime::parse_from_rfc3339(trimmed) {
        return Some(dt.with_timezone(&Utc));
    }

    None
}

/// Returns the input with a leading `"Xxx, "` weekday token removed, or
/// `None` if no such prefix is present.
fn strip_leading_weekday(s: &str) -> Option<String> {
    let bytes = s.as_bytes();
    if bytes.len() < 5 {
        return None;
    }
    // Three letters + comma + space.
    if !bytes[..3].iter().all(|c| c.is_ascii_alphabetic()) {
        return None;
    }
    if bytes[3] != b',' || bytes[4] != b' ' {
        return None;
    }
    Some(s[5..].to_string())
}

const RFC822_OFFSET_FORMATS: &[&str] = &[
    "%a, %d %b %Y %H:%M:%S %z",
    "%a, %e %b %Y %H:%M:%S %z",
    "%a, %d %b %Y %H:%M %z",
    "%d %b %Y %H:%M:%S %z",
    "%e %b %Y %H:%M:%S %z",
    "%d %b %Y %H:%M %z",
];

const RFC822_NAIVE_FORMATS: &[&str] = &[
    "%a, %d %b %Y %H:%M:%S",
    "%a, %e %b %Y %H:%M:%S",
    "%d %b %Y %H:%M:%S",
    "%e %b %Y %H:%M:%S",
];

#[cfg(test)]
#[path = "date_tests.rs"]
mod tests;
