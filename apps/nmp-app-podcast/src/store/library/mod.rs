//! Podcast library management and episode lookup for [`super::super::PodcastStore`].
//!
//! Extracted from `store/mod.rs` to keep that file within the 300-line soft
//! limit. Covers known-podcast lifecycle, read-only podcast/episode queries,
//! download-path tracking, and episode metadata resolution.
//!
//! Split into two focused sub-modules by domain:
//! - [`podcasts`]: podcast/subscription management
//! - [`episodes`]: episode queries and download-path tracking

pub mod episodes;
pub mod podcasts;
