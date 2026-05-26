use serde::{Deserialize, Serialize};
use url::Url;

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum DownloadState {
    #[default]
    NotDownloaded,
    Queued,
    Downloading {
        progress: f64,
        #[serde(skip_serializing_if = "Option::is_none")]
        bytes_written: Option<i64>,
    },
    Downloaded {
        local_file_url: Url,
        byte_count: i64,
    },
    Failed {
        message: String,
    },
}

#[cfg(test)]
#[path = "download_tests.rs"]
mod tests;
