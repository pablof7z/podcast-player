use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum OpenRouterCredentialSource {
    #[default]
    None,
    Manual,
    Byok,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum ElevenLabsCredentialSource {
    #[default]
    None,
    Manual,
    Byok,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum OllamaCredentialSource {
    #[default]
    None,
    Manual,
    Byok,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HeadphoneGestureAction {
    SkipForward,
    SkipBackward,
    NextChapter,
    PreviousChapter,
    ClipNow,
    None,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SttProvider {
    ElevenLabsScribe,
    AssemblyAi,
    OpenRouterWhisper,
    AppleNative,
}

/// Provider credential triple shared by OpenRouter, Ollama, and ElevenLabs.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct ProviderCredentialMetadata {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub byok_key_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub byok_key_label: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub connected_at: Option<DateTime<Utc>>,
}
