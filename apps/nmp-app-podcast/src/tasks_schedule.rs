//! Schedule parsing for Rust-owned agent tasks.
//!
//! Platform shells submit user intent such as `"daily"` or `"every 3600s"`;
//! Rust owns whether that intent is valid and when it is next due.

enum ScheduleKind {
    Once,
    Recurring(i64),
}

pub(crate) fn next_run_after(schedule: &str, now: i64) -> Result<Option<i64>, String> {
    match parse_schedule(schedule)? {
        ScheduleKind::Once => Ok(Some(now)),
        ScheduleKind::Recurring(seconds) => Ok(Some(now + seconds)),
    }
}

pub(crate) fn next_run_after_attempt(schedule: &str, now: i64) -> Result<Option<i64>, String> {
    match parse_schedule(schedule)? {
        ScheduleKind::Once => Ok(None),
        ScheduleKind::Recurring(seconds) => Ok(Some(now + seconds)),
    }
}

fn parse_schedule(schedule: &str) -> Result<ScheduleKind, String> {
    let normalized = schedule.trim().to_lowercase().replace(['_', '-'], " ");
    let compact = normalized.split_whitespace().collect::<Vec<_>>().join(" ");
    match compact.as_str() {
        "once" => Ok(ScheduleKind::Once),
        "hourly" | "every hour" | "every 1 hour" => Ok(ScheduleKind::Recurring(3_600)),
        "daily" | "nightly" | "every day" | "every night" => Ok(ScheduleKind::Recurring(86_400)),
        "weekly" | "every week" => Ok(ScheduleKind::Recurring(604_800)),
        _ => parse_seconds_schedule(&compact)
            .map(ScheduleKind::Recurring)
            .ok_or_else(|| {
                "invalid schedule; use hourly, daily, nightly, weekly, once, or every <seconds>s"
                    .to_owned()
            }),
    }
}

fn parse_seconds_schedule(schedule: &str) -> Option<i64> {
    let raw = schedule
        .strip_prefix("every ")
        .or_else(|| schedule.strip_prefix("every:"))
        .unwrap_or(schedule)
        .trim();
    let number = raw
        .strip_suffix(" seconds")
        .or_else(|| raw.strip_suffix(" second"))
        .or_else(|| raw.strip_suffix(" secs"))
        .or_else(|| raw.strip_suffix(" sec"))
        .or_else(|| raw.strip_suffix('s'))
        .unwrap_or(raw)
        .trim();
    let seconds = number.parse::<i64>().ok()?;
    (seconds > 0).then_some(seconds)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn common_schedules_compute_next_run() {
        let now = 1_700_000_000;
        assert_eq!(next_run_after("hourly", now).unwrap(), Some(now + 3_600));
        assert_eq!(next_run_after("daily", now).unwrap(), Some(now + 86_400));
        assert_eq!(next_run_after("nightly", now).unwrap(), Some(now + 86_400));
        assert_eq!(next_run_after("weekly", now).unwrap(), Some(now + 604_800));
    }

    #[test]
    fn custom_second_schedules_compute_next_run() {
        let now = 100;
        assert_eq!(next_run_after("every 45s", now).unwrap(), Some(145));
        assert_eq!(next_run_after("every:60", now).unwrap(), Some(160));
        assert_eq!(next_run_after("90 seconds", now).unwrap(), Some(190));
    }

    #[test]
    fn once_is_due_now_then_unscheduled_after_attempt() {
        let now = 100;
        assert_eq!(next_run_after("once", now).unwrap(), Some(now));
        assert_eq!(next_run_after_attempt("once", now).unwrap(), None);
    }

    #[test]
    fn malformed_schedules_are_rejected() {
        assert!(next_run_after("", 0).is_err());
        assert!(next_run_after("every 0s", 0).is_err());
        assert!(next_run_after("someday", 0).is_err());
    }
}
