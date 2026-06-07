//! Audio-source resolution for OpenRouter Whisper uploads.

use std::path::{Path, PathBuf};
use std::time::Duration;

use reqwest::header::CONTENT_TYPE;

use super::openrouter_whisper::OpenRouterWhisperError;

const AUDIO_SOURCE_TIMEOUT: Duration = Duration::from_secs(600);

pub(super) struct AudioUpload {
    pub bytes: Vec<u8>,
    pub filename: String,
    pub content_type: String,
}

pub(super) async fn resolve_audio_source(
    client: &reqwest::Client,
    source: &str,
) -> Result<AudioUpload, OpenRouterWhisperError> {
    let trimmed = source.trim();
    if trimmed.is_empty() {
        return Err(OpenRouterWhisperError::InvalidAudioSource(
            "empty audio source".to_owned(),
        ));
    }
    if let Ok(url) = url::Url::parse(trimmed) {
        return match url.scheme() {
            "file" => {
                let path = url.to_file_path().map_err(|_| {
                    OpenRouterWhisperError::InvalidAudioSource("invalid file URL".to_owned())
                })?;
                read_local_audio(path).await
            }
            "http" | "https" => download_audio(client, url).await,
            scheme => Err(OpenRouterWhisperError::InvalidAudioSource(format!(
                "unsupported URL scheme {scheme}"
            ))),
        };
    }
    read_local_audio(PathBuf::from(trimmed)).await
}

async fn read_local_audio(path: PathBuf) -> Result<AudioUpload, OpenRouterWhisperError> {
    if !path.exists() {
        return Err(OpenRouterWhisperError::InvalidAudioSource(format!(
            "{} does not exist",
            path.display()
        )));
    }
    let filename = filename_from_path(&path);
    let content_type = content_type_for_extension(path.extension().and_then(|ext| ext.to_str()));
    let bytes = tokio::task::spawn_blocking(move || std::fs::read(path))
        .await
        .map_err(|e| OpenRouterWhisperError::Transport(e.to_string()))?
        .map_err(|e| OpenRouterWhisperError::InvalidAudioSource(e.to_string()))?;
    Ok(AudioUpload {
        bytes,
        filename,
        content_type,
    })
}

async fn download_audio(
    client: &reqwest::Client,
    url: url::Url,
) -> Result<AudioUpload, OpenRouterWhisperError> {
    let response = client
        .get(url.clone())
        .timeout(AUDIO_SOURCE_TIMEOUT)
        .send()
        .await
        .map_err(map_reqwest_error)?;
    let status = response.status();
    let header_content_type = response
        .headers()
        .get(CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .map(str::to_owned);
    if !status.is_success() {
        let body = response.text().await.unwrap_or_default();
        return Err(OpenRouterWhisperError::DownloadFailed(format!(
            "HTTP {}: {}",
            status.as_u16(),
            body.chars().take(300).collect::<String>()
        )));
    }
    let filename = filename_from_url(&url);
    let fallback_content_type = content_type_for_extension(
        Path::new(&filename)
            .extension()
            .and_then(|ext| ext.to_str()),
    );
    let bytes = response.bytes().await.map_err(map_reqwest_error)?.to_vec();
    Ok(AudioUpload {
        bytes,
        filename,
        content_type: header_content_type.unwrap_or(fallback_content_type),
    })
}

fn filename_from_path(path: &Path) -> String {
    path.file_name()
        .and_then(|name| name.to_str())
        .filter(|name| !name.is_empty())
        .unwrap_or("audio.mp3")
        .to_owned()
}

fn filename_from_url(url: &url::Url) -> String {
    url.path_segments()
        .and_then(|mut segments| segments.next_back())
        .filter(|name| !name.is_empty())
        .unwrap_or("audio.mp3")
        .to_owned()
}

fn content_type_for_extension(extension: Option<&str>) -> String {
    match extension.unwrap_or_default().to_ascii_lowercase().as_str() {
        "mp3" => "audio/mpeg",
        "m4a" | "m4b" | "aac" => "audio/mp4",
        "wav" => "audio/wav",
        "ogg" => "audio/ogg",
        "opus" => "audio/opus",
        "flac" => "audio/flac",
        "webm" => "audio/webm",
        _ => "application/octet-stream",
    }
    .to_owned()
}

pub(super) fn map_reqwest_error(error: reqwest::Error) -> OpenRouterWhisperError {
    if error.is_timeout() {
        OpenRouterWhisperError::Timeout
    } else {
        OpenRouterWhisperError::Transport(error.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_audio_content_types_by_extension() {
        assert_eq!(content_type_for_extension(Some("mp3")), "audio/mpeg");
        assert_eq!(content_type_for_extension(Some("M4A")), "audio/mp4");
        assert_eq!(
            content_type_for_extension(Some("unknown")),
            "application/octet-stream"
        );
    }

    #[test]
    fn extracts_url_filename_or_default() {
        let url = url::Url::parse("https://example.test/audio/show.mp3").unwrap();
        assert_eq!(filename_from_url(&url), "show.mp3");
        let root = url::Url::parse("https://example.test/").unwrap();
        assert_eq!(filename_from_url(&root), "audio.mp3");
    }
}
