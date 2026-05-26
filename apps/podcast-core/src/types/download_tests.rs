use super::*;
#[test]
fn not_downloaded_round_trip() {
    let value = DownloadState::NotDownloaded;
    let json = serde_json::to_string(&value).unwrap();
    let back: DownloadState = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}
#[test]
fn downloading_round_trip() {
    let value = DownloadState::Downloading {
        progress: 0.33,
        bytes_written: Some(1024),
    };
    let json = serde_json::to_string(&value).unwrap();
    let back: DownloadState = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}
#[test]
fn downloaded_round_trip() {
    let value = DownloadState::Downloaded {
        local_file_url: Url::parse("file:///tmp/ep.mp3").unwrap(),
        byte_count: 4096,
    };
    let json = serde_json::to_string(&value).unwrap();
    let back: DownloadState = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}

