use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TranscriptKind {
    Vtt,
    Srt,
    Json,
    Html,
    Text,
}

impl TranscriptKind {
    pub fn from_mime(raw: &str) -> Option<Self> {
        let normalized = raw.trim().to_ascii_lowercase();
        match normalized.as_str() {
            "text/vtt" | "application/vtt" | "vtt" => Some(Self::Vtt),
            "application/x-subrip" | "application/srt" | "text/srt" | "srt" => Some(Self::Srt),
            "application/json"
            | "application/json+podcastindex.org"
            | "application/json; charset=utf-8" => Some(Self::Json),
            "text/html" | "html" => Some(Self::Html),
            "text/plain" | "plain" => Some(Self::Text),
            other => {
                if other.starts_with("text/vtt") {
                    Some(Self::Vtt)
                } else if other.starts_with("application/json") {
                    Some(Self::Json)
                } else if other.starts_with("text/html") {
                    Some(Self::Html)
                } else if other.starts_with("text/plain") {
                    Some(Self::Text)
                } else {
                    None
                }
            }
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TranscriptSource {
    Publisher,
    Scribe,
    Whisper,
    OnDevice,
    AssemblyAi,
    Other,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum TranscriptState {
    #[default]
    None,
    Queued,
    FetchingPublisher,
    Transcribing { progress: f64 },
    Ready { source: TranscriptSource },
    Failed { message: String },
}

#[cfg(test)]
#[path = "transcript_tests.rs"]
mod tests;
