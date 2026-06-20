//! Emitter — produces the exact text of each Generated/*.generated.swift file.
//!
//! Each `emit_*` function returns `(filename, content)`.
//! All files are returned by `all_files()`.

mod library;
mod media;
mod platform;
mod podcast;
mod settings;
mod social;
mod update;

pub fn all_files() -> Vec<(&'static str, String)> {
    vec![
        ("PodcastTypes.generated.swift",             podcast::emit_podcast_types()),
        ("PodcastAgentContextTypes.generated.swift", podcast::emit_agent_context_types()),
        ("PodcastDownloadTypes.generated.swift",     podcast::emit_download_types()),
        ("PodcastLibraryTypes.generated.swift",      library::emit_library_types()),
        ("PodcastMediaTypes.generated.swift",        media::emit_media_types()),
        ("PodcastSocialTypes.generated.swift",       social::emit_social_types()),
        ("PodcastUpdate.generated.swift",            update::emit_podcast_update()),
        ("PodcastSettingsSnapshot.generated.swift",  settings::emit_settings_snapshot()),
        ("PodcastPlatformTypes.generated.swift",     platform::emit_platform_types()),
    ]
}

// ── helpers ──────────────────────────────────────────────────────────────────

fn header(file: &str, note: &str, source: &str) -> String {
    format!(
        "// {file}\n// {note}\n// Source of truth: {source}\n\nimport Foundation\n",
    )
}
