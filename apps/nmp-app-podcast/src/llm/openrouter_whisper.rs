//! Shared OpenRouter Whisper transcription transport.

use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use reqwest::multipart::{Form, Part};
use serde::{Deserialize, Serialize};

use super::openrouter_whisper_audio::{map_reqwest_error, resolve_audio_source};
use super::provider_config::{
    strip_provider_prefix, ProviderConfigError, ProviderSettings, OPENROUTER_BASE_URL,
};
use crate::store::PodcastStore;

const TRANSCRIPTION_TIMEOUT: Duration = Duration::from_secs(600);
const DEFAULT_WHISPER_MODEL: &str = "openai/whisper-1";

#[derive(Debug, Deserialize)]
pub struct OpenRouterWhisperIntent {
    pub audio_url: String,
    #[serde(default)]
    pub language_hint: Option<String>,
}

#[derive(Debug, Serialize, PartialEq)]
pub struct OpenRouterWhisperResult {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub task: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub language: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub duration: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    pub segments: Vec<OpenRouterWhisperSegment>,
    pub model: String,
    pub latency_ms: u128,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq)]
pub struct OpenRouterWhisperSegment {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<i64>,
    pub start: f64,
    pub end: f64,
    pub text: String,
}

#[derive(Debug)]
pub enum OpenRouterWhisperError {
    MissingCredential,
    InvalidAudioSource(String),
    DownloadFailed(String),
    Timeout,
    Transport(String),
    ProviderStatus(u16, String),
    Decode(String),
    StoreUnavailable,
}

impl OpenRouterWhisperError {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::MissingCredential => "missing_api_key",
            Self::InvalidAudioSource(_) => "invalid_audio_url",
            Self::DownloadFailed(_) => "download_failed",
            Self::Timeout => "timed_out",
            Self::Transport(_) => "network_error",
            Self::ProviderStatus(401 | 403, _) => "invalid_key",
            Self::ProviderStatus(429, _) => "rate_limited",
            Self::ProviderStatus(_, _) => "server_error",
            Self::Decode(_) => "decoding_error",
            Self::StoreUnavailable => "store_unavailable",
        }
    }

    pub fn status_code(&self) -> Option<u16> {
        match self {
            Self::ProviderStatus(status, _) => Some(*status),
            _ => None,
        }
    }
}

impl std::fmt::Display for OpenRouterWhisperError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::MissingCredential => write!(f, "OpenRouter API key is not configured"),
            Self::InvalidAudioSource(message) => write!(f, "invalid audio source: {message}"),
            Self::DownloadFailed(message) => write!(f, "audio download failed: {message}"),
            Self::Timeout => write!(f, "OpenRouter transcription timed out"),
            Self::Transport(message) => write!(f, "OpenRouter transcription failed: {message}"),
            Self::ProviderStatus(status, body) => write!(
                f,
                "OpenRouter transcription returned HTTP {status}: {}",
                body.chars().take(300).collect::<String>()
            ),
            Self::Decode(message) => write!(f, "OpenRouter transcript decode failed: {message}"),
            Self::StoreUnavailable => write!(f, "settings store unavailable"),
        }
    }
}

impl From<ProviderConfigError> for OpenRouterWhisperError {
    fn from(error: ProviderConfigError) -> Self {
        match error {
            ProviderConfigError::StoreUnavailable => Self::StoreUnavailable,
        }
    }
}

pub async fn transcribe_openrouter_whisper(
    store: Arc<Mutex<PodcastStore>>,
    intent: OpenRouterWhisperIntent,
) -> Result<OpenRouterWhisperResult, OpenRouterWhisperError> {
    let settings = ProviderSettings::from_store(&store)?;
    let api_key = settings
        .openrouter_key
        .filter(|key| !key.trim().is_empty())
        .ok_or(OpenRouterWhisperError::MissingCredential)?;
    let model = normalize_model(&settings.openrouter_whisper_model);
    let client = reqwest::Client::builder()
        .timeout(TRANSCRIPTION_TIMEOUT)
        .build()
        .map_err(map_reqwest_error)?;
    let audio = resolve_audio_source(&client, &intent.audio_url).await?;
    let mut form = Form::new()
        .text("model", model.clone())
        .text("response_format", "verbose_json")
        .text("timestamp_granularities[]", "segment");
    if let Some(language) = intent.language_hint.filter(|hint| !hint.trim().is_empty()) {
        form = form.text("language", language);
    }
    let part = Part::bytes(audio.bytes)
        .file_name(audio.filename)
        .mime_str(&audio.content_type)
        .map_err(|e| OpenRouterWhisperError::InvalidAudioSource(e.to_string()))?;
    let started = Instant::now();
    let response = client
        .post(format!("{OPENROUTER_BASE_URL}/audio/transcriptions"))
        .bearer_auth(api_key)
        .header("X-Title", "Podcastr")
        .multipart(form.part("file", part))
        .timeout(TRANSCRIPTION_TIMEOUT)
        .send()
        .await
        .map_err(map_reqwest_error)?;
    let status = response.status();
    let text = response.text().await.map_err(map_reqwest_error)?;
    if !status.is_success() {
        return Err(OpenRouterWhisperError::ProviderStatus(
            status.as_u16(),
            text,
        ));
    }
    decode_transcription_response(&text, model, started.elapsed().as_millis())
}

fn normalize_model(raw: &str) -> String {
    let trimmed = strip_provider_prefix(raw.trim(), "openrouter").trim();
    if trimmed.is_empty() {
        DEFAULT_WHISPER_MODEL.to_owned()
    } else {
        trimmed.to_owned()
    }
}

#[derive(Debug, Deserialize)]
struct WhisperResponse {
    task: Option<String>,
    language: Option<String>,
    duration: Option<f64>,
    text: Option<String>,
    segments: Option<Vec<OpenRouterWhisperSegment>>,
}

fn decode_transcription_response(
    text: &str,
    model: String,
    latency_ms: u128,
) -> Result<OpenRouterWhisperResult, OpenRouterWhisperError> {
    let raw: WhisperResponse =
        serde_json::from_str(text).map_err(|e| OpenRouterWhisperError::Decode(e.to_string()))?;
    Ok(OpenRouterWhisperResult {
        task: raw.task,
        language: raw.language,
        duration: raw.duration,
        text: raw.text,
        segments: raw.segments.unwrap_or_default(),
        model,
        latency_ms,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_openrouter_prefixed_model() {
        assert_eq!(
            normalize_model("openrouter:openai/whisper-1"),
            "openai/whisper-1"
        );
        assert_eq!(normalize_model(" "), DEFAULT_WHISPER_MODEL);
    }

    #[test]
    fn decodes_verbose_transcription_response() {
        let result = decode_transcription_response(
            r#"{"language":"en","duration":1.2,"text":"hello","segments":[{"id":0,"start":0.0,"end":1.2,"text":" hello "}]} "#,
            "openai/whisper-1".to_owned(),
            42,
        )
        .unwrap();
        assert_eq!(result.language.as_deref(), Some("en"));
        assert_eq!(result.segments.len(), 1);
        assert_eq!(result.latency_ms, 42);
    }

    #[test]
    fn provider_status_maps_to_stable_kinds() {
        assert_eq!(
            OpenRouterWhisperError::ProviderStatus(401, String::new()).kind(),
            "invalid_key"
        );
        assert_eq!(
            OpenRouterWhisperError::ProviderStatus(429, String::new()).kind(),
            "rate_limited"
        );
    }
}
