//! Auto ad-skip — re-export of the canonical [`podcast_core::AdSegment`]
//! domain type + a small helper the player actor uses to test
//! containment.
//!
//! The actor / FFI projections use the existing [`podcast_core::AdSegment`]
//! so we don't fragment the domain across two definitions. The `id` is a
//! `Uuid` (serializes as a hyphenated string in JSON — iOS decodes it
//! into a `String` field, no shape break); `kind` distinguishes
//! pre-roll / mid-roll / post-roll for upstream ingest pipelines.
//!
//! ## Why half-open `[start, end)`?
//!
//! Strict less-than at the right edge so the seek target (`end_secs`)
//! doesn't immediately re-trigger the same auto-skip on the next
//! `Playing` report. The legacy iOS `PlaybackState+AdSkip.swift`
//! enforces the same boundary; we keep parity here.
//!
//! ## Why per-session skip tracking?
//!
//! See [`super::PlayerActor::set_ad_segments`] — if the user manually
//! scrubs back into a segment we already skipped, that's a deliberate
//! "let it play" intent. The set lives on the actor and clears on
//! `AudioReport::Stopped`.

pub use podcast_core::AdSegment;

/// Half-open `[start, end)` containment check the player actor uses
/// to decide whether `position_secs` falls inside an ad break.
/// Left edge inclusive, right edge exclusive so a seek-to-`end_secs`
/// doesn't re-enter the segment on the next `Playing` tick.
#[must_use]
pub(crate) fn contains(segment: &AdSegment, position_secs: f64) -> bool {
    position_secs >= segment.start_secs && position_secs < segment.end_secs
}

#[cfg(test)]
#[path = "ad_segments_tests.rs"]
mod tests;
