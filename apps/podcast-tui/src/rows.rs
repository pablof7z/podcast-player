use nmp_app_podcast::ffi::{
    ChapterSummary, DownloadItemSnapshot, EpisodeSummary, InboxItem, PodcastSummary,
    TranscriptEntry,
};
use nmp_app_podcast::player::AdSegment;

#[derive(Debug, Clone, PartialEq)]
pub struct PodcastRow {
    pub id: String,
    pub title: String,
    pub unplayed_count: usize,
    pub episodes: Vec<EpisodeRow>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct EpisodeRow {
    pub id: String,
    pub title: String,
    pub podcast_title: Option<String>,
    pub description: Option<String>,
    pub duration_secs: Option<f64>,
    pub file_size_bytes: i64,
    pub enclosure_url: Option<String>,
    pub playback_position_secs: Option<f64>,
    pub played: bool,
    pub starred: bool,
    pub download_path: Option<String>,
    pub transcript_url: Option<String>,
    pub transcript_entries: Vec<TranscriptEntry>,
    pub transcript: Option<String>,
    pub summary: Option<String>,
    pub ai_categories: Vec<String>,
    pub ad_segments: Vec<AdSegment>,
    pub transcript_status: String,
    pub transcript_status_message: Option<String>,
    pub chapters: Vec<ChapterSummary>,
    pub chapters_count: usize,
    pub has_transcript: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SearchResult {
    pub id: String,
    pub title: String,
    pub author: Option<String>,
    pub artwork_url: Option<String>,
    pub feed_url: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct InboxRow {
    pub episode_id: String,
    pub episode_title: String,
    pub podcast_title: String,
    pub duration_secs: Option<f64>,
    pub priority_score: f32,
    pub priority_reason: Option<String>,
    pub ai_categories: Vec<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct DownloadRow {
    pub episode_id: String,
    pub kind: String,
    pub url: String,
    pub progress: f32,
    pub state: String,
    pub total_bytes: Option<u64>,
    pub error: Option<String>,
}

impl From<PodcastSummary> for PodcastRow {
    fn from(summary: PodcastSummary) -> Self {
        Self {
            id: summary.id,
            title: summary.title,
            unplayed_count: summary.unplayed_count,
            episodes: summary.episodes.into_iter().map(EpisodeRow::from).collect(),
        }
    }
}

impl From<EpisodeSummary> for EpisodeRow {
    fn from(summary: EpisodeSummary) -> Self {
        let chapters_count = summary.chapters.len();
        let has_transcript = summary
            .transcript
            .as_deref()
            .map(|text| !text.is_empty())
            .unwrap_or(false);
        Self {
            id: summary.id,
            title: summary.title,
            podcast_title: summary.podcast_title,
            description: summary.description,
            duration_secs: summary.duration_secs,
            file_size_bytes: summary.file_size_bytes,
            enclosure_url: summary.enclosure_url,
            playback_position_secs: summary.playback_position_secs,
            played: summary.played,
            starred: summary.starred,
            download_path: summary.download_path,
            transcript_url: summary.transcript_url,
            transcript_entries: summary.transcript_entries,
            transcript: summary.transcript,
            summary: summary.summary,
            ai_categories: summary.ai_categories,
            ad_segments: summary.ad_segments,
            transcript_status: summary.transcript_status,
            transcript_status_message: summary.transcript_status_message,
            chapters: summary.chapters,
            chapters_count,
            has_transcript,
        }
    }
}

impl From<PodcastSummary> for SearchResult {
    fn from(summary: PodcastSummary) -> Self {
        Self {
            id: summary.id,
            title: summary.title,
            author: summary.author,
            artwork_url: summary.artwork_url,
            feed_url: summary.feed_url,
        }
    }
}

impl From<InboxItem> for InboxRow {
    fn from(item: InboxItem) -> Self {
        Self {
            episode_id: item.episode_id,
            episode_title: item.episode_title,
            podcast_title: item.podcast_title,
            duration_secs: item.duration_secs,
            priority_score: item.priority_score,
            priority_reason: item.priority_reason,
            ai_categories: item.ai_categories,
        }
    }
}

impl From<DownloadItemSnapshot> for DownloadRow {
    fn from(item: DownloadItemSnapshot) -> Self {
        let kind = if item.kind.is_episode() {
            "episode"
        } else {
            "local_model"
        };
        Self {
            episode_id: item.episode_id,
            kind: kind.to_string(),
            url: item.url,
            progress: item.progress,
            state: item.state,
            total_bytes: item.total_bytes,
            error: item.error,
        }
    }
}
