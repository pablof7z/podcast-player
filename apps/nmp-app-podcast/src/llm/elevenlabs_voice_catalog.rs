//! Shared ElevenLabs voice catalog transport.

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};

use super::provider_config::{ProviderConfigError, ProviderSettings, ELEVENLABS_BASE_URL};
use crate::store::PodcastStore;

const VOICES_TIMEOUT: Duration = Duration::from_secs(30);

#[derive(Debug, Serialize, PartialEq)]
pub struct ElevenLabsVoiceCatalog {
    pub provider: String,
    pub voices: Vec<ElevenLabsVoice>,
    pub latency_ms: u128,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ElevenLabsVoice {
    pub voice_id: String,
    pub name: String,
    pub category: String,
    pub labels: BTreeMap<String, String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub preview_url: Option<String>,
}

#[derive(Debug)]
pub enum ElevenLabsVoiceCatalogError {
    MissingCredential,
    Transport(String),
    ProviderStatus(u16, String),
    Decode(String),
    StoreUnavailable,
}

impl ElevenLabsVoiceCatalogError {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::MissingCredential => "missing_api_key",
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

impl std::fmt::Display for ElevenLabsVoiceCatalogError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::MissingCredential => write!(f, "ElevenLabs API key is not configured"),
            Self::Transport(message) => write!(f, "ElevenLabs voice catalog failed: {message}"),
            Self::ProviderStatus(status, body) => write!(
                f,
                "ElevenLabs voice catalog returned HTTP {status}: {}",
                body.chars().take(300).collect::<String>()
            ),
            Self::Decode(message) => write!(f, "ElevenLabs voice catalog decode failed: {message}"),
            Self::StoreUnavailable => write!(f, "settings store unavailable"),
        }
    }
}

impl From<ProviderConfigError> for ElevenLabsVoiceCatalogError {
    fn from(error: ProviderConfigError) -> Self {
        match error {
            ProviderConfigError::StoreUnavailable => Self::StoreUnavailable,
        }
    }
}

pub async fn fetch_elevenlabs_voice_catalog(
    store: Arc<Mutex<PodcastStore>>,
) -> Result<ElevenLabsVoiceCatalog, ElevenLabsVoiceCatalogError> {
    let settings = ProviderSettings::from_store(&store)?;
    let api_key = settings
        .eleven_labs_key
        .filter(|key| !key.trim().is_empty())
        .ok_or(ElevenLabsVoiceCatalogError::MissingCredential)?;
    let client = reqwest::Client::builder()
        .timeout(VOICES_TIMEOUT)
        .build()
        .map_err(map_reqwest_error)?;
    fetch_elevenlabs_voice_catalog_with_client(
        &client,
        &format!("{ELEVENLABS_BASE_URL}/v1/voices"),
        &api_key,
    )
    .await
}

async fn fetch_elevenlabs_voice_catalog_with_client(
    client: &reqwest::Client,
    url: &str,
    api_key: &str,
) -> Result<ElevenLabsVoiceCatalog, ElevenLabsVoiceCatalogError> {
    let started = Instant::now();
    let response = client
        .get(url)
        .header("xi-api-key", api_key)
        .header("Accept", "application/json")
        .timeout(VOICES_TIMEOUT)
        .send()
        .await
        .map_err(map_reqwest_error)?;
    let status = response.status();
    let text = response.text().await.map_err(map_reqwest_error)?;
    if !status.is_success() {
        return Err(ElevenLabsVoiceCatalogError::ProviderStatus(
            status.as_u16(),
            text,
        ));
    }
    decode_voices_response(&text, started.elapsed().as_millis())
}

fn decode_voices_response(
    text: &str,
    latency_ms: u128,
) -> Result<ElevenLabsVoiceCatalog, ElevenLabsVoiceCatalogError> {
    let dto: VoicesResponse =
        serde_json::from_str(text).map_err(|e| ElevenLabsVoiceCatalogError::Decode(e.to_string()))?;
    let voices = dto
        .voices
        .into_iter()
        .map(|voice| ElevenLabsVoice {
            voice_id: voice.voice_id,
            name: voice.name,
            category: voice.category.unwrap_or_else(|| "other".to_owned()),
            labels: normalize_labels(voice.labels),
            preview_url: voice.preview_url.filter(|url| !url.trim().is_empty()),
        })
        .collect();
    Ok(ElevenLabsVoiceCatalog {
        provider: "elevenlabs".to_owned(),
        voices,
        latency_ms,
    })
}

fn normalize_labels(
    labels: Option<BTreeMap<String, serde_json::Value>>,
) -> BTreeMap<String, String> {
    labels
        .unwrap_or_default()
        .into_iter()
        .filter_map(|(key, value)| value.as_str().map(|s| (key, s.to_owned())))
        .collect()
}

fn map_reqwest_error(error: reqwest::Error) -> ElevenLabsVoiceCatalogError {
    if error.is_timeout() {
        ElevenLabsVoiceCatalogError::Transport("request timed out".to_owned())
    } else {
        ElevenLabsVoiceCatalogError::Transport(error.to_string())
    }
}

#[derive(Debug, Deserialize)]
struct VoicesResponse {
    #[serde(default)]
    voices: Vec<VoiceDto>,
}

#[derive(Debug, Deserialize)]
struct VoiceDto {
    voice_id: String,
    name: String,
    category: Option<String>,
    labels: Option<BTreeMap<String, serde_json::Value>>,
    preview_url: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_elevenlabs_voice_catalog() {
        let catalog = decode_voices_response(
            r#"{
                "voices": [
                    {
                        "voice_id": "voice-a",
                        "name": "Narrator",
                        "category": "premade",
                        "labels": {
                            "gender": "female",
                            "accent": "american",
                            "count": 2
                        },
                        "preview_url": "https://example.test/preview.mp3"
                    },
                    {
                        "voice_id": "voice-b",
                        "name": "Custom",
                        "labels": null,
                        "preview_url": ""
                    }
                ]
            }"#,
            42,
        )
        .unwrap();

        assert_eq!(catalog.provider, "elevenlabs");
        assert_eq!(catalog.latency_ms, 42);
        assert_eq!(catalog.voices.len(), 2);
        assert_eq!(catalog.voices[0].labels.get("gender").unwrap(), "female");
        assert!(!catalog.voices[0].labels.contains_key("count"));
        assert_eq!(catalog.voices[1].category, "other");
        assert_eq!(catalog.voices[1].preview_url, None);
    }

    #[test]
    fn invalid_key_uses_stable_ffi_kind() {
        assert_eq!(
            ElevenLabsVoiceCatalogError::ProviderStatus(401, String::new()).kind(),
            "invalid_key"
        );
    }
}
