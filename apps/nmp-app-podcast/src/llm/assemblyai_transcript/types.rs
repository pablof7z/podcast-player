use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
pub struct AssemblyAITranscriptIntent {
    pub audio_url: String,
    #[serde(default)]
    pub language_hint: Option<String>,
}

#[derive(Debug, Serialize, PartialEq)]
pub struct AssemblyAITranscriptResult {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub audio_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub audio_duration: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub language_code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    pub words: Vec<AssemblyAIWord>,
    pub utterances: Vec<AssemblyAIUtterance>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub usage: Option<AssemblyAIUsage>,
    pub model: String,
    pub latency_ms: u128,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq)]
pub struct AssemblyAIUsage {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cost: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub seconds: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub input_tokens: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub output_tokens: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub total_tokens: Option<i64>,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq)]
pub struct AssemblyAIUtterance {
    pub start: i64,
    pub end: i64,
    pub text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub confidence: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub speaker: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub words: Vec<AssemblyAIWord>,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq)]
pub struct AssemblyAIWord {
    pub start: i64,
    pub end: i64,
    pub text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub confidence: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub speaker: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(super) struct AssemblyAIResponse {
    pub id: Option<String>,
    pub status: Option<String>,
    pub audio_url: Option<String>,
    pub audio_duration: Option<f64>,
    pub language_code: Option<String>,
    pub text: Option<String>,
    pub error: Option<String>,
    pub words: Option<Vec<AssemblyAIWord>>,
    pub utterances: Option<Vec<AssemblyAIUtterance>>,
    pub usage: Option<AssemblyAIUsage>,
}

impl AssemblyAIResponse {
    pub(super) fn into_result(self, model: String, latency_ms: u128) -> AssemblyAITranscriptResult {
        AssemblyAITranscriptResult {
            id: self.id,
            status: self.status,
            audio_url: self.audio_url,
            audio_duration: self.audio_duration,
            language_code: self.language_code,
            text: self.text,
            error: self.error,
            words: self.words.unwrap_or_default(),
            utterances: self.utterances.unwrap_or_default(),
            usage: self.usage,
            model,
            latency_ms,
        }
    }
}

#[derive(Debug, Serialize)]
pub(super) struct SubmitRequest {
    pub audio_url: String,
    pub speech_models: Vec<String>,
    pub speaker_labels: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub language_detection: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub language_code: Option<String>,
}
