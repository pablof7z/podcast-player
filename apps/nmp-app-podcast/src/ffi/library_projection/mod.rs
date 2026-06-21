//! Rust-owned Library screen projections.
//!
//! Swift owns native list rendering and local text-field interaction. Rust owns
//! library membership, archive visibility, ordering, and caps.

mod helpers;
mod types;

mod catalog;
mod episodes;

pub use catalog::{
    nmp_app_podcast_library_all_podcasts, nmp_app_podcast_library_categories,
    nmp_app_podcast_library_download_rows, nmp_app_podcast_library_followed_podcasts,
    nmp_app_podcast_library_owned_podcasts, nmp_app_podcast_library_podcast_stats,
    nmp_app_podcast_library_subscription_status, nmp_app_podcast_library_summary,
};
pub use episodes::{
    nmp_app_podcast_library_all_episodes, nmp_app_podcast_library_episode_for_audio_url,
    nmp_app_podcast_library_episode_lookup, nmp_app_podcast_library_show_episodes,
    nmp_app_podcast_library_starred_episodes,
};
