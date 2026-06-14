use std::collections::HashSet;
use std::fmt;

use podcast_core::{NostrVisibility, Podcast, PodcastId};
use quick_xml::events::Event;
use quick_xml::Reader;
use url::Url;

use chrono::Utc;

pub const MAX_OPML_BYTES: usize = 5 * 1024 * 1024;
pub const MAX_OPML_FEEDS: usize = 5_000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OpmlImportIssue {
    pub feed_url: Option<String>,
    pub title: String,
    pub error: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct OpmlImportReport {
    pub podcasts: Vec<Podcast>,
    pub issues: Vec<OpmlImportIssue>,
}

/// Parses an OPML 2.0 subscription list into seeded `Podcast` records, ready
/// for first refresh. Ports `OPMLImport.swift`.
///
/// `<outline>` entries with `xmlUrl` are kept; grouping folders without one
/// are skipped. Order is preserved as emitted. Duplicate feed URLs are
/// dropped after the first occurrence.
///
/// Return shape is `Vec<Podcast>` (not `Vec<Url>`) so the import sheet can
/// render the user's list with titles before the first refresh round-trips.
pub fn import_opml(xml: &str) -> Result<Vec<Podcast>, OpmlError> {
    import_opml_report(xml).map(|report| report.podcasts)
}

/// Parses OPML and preserves row-level issues for invalid feed entries.
/// Malformed XML, oversized input, and unbounded feed counts remain whole-file
/// errors; individual bad feed URLs are partial failures.
pub fn import_opml_report(xml: &str) -> Result<OpmlImportReport, OpmlError> {
    if xml.len() > MAX_OPML_BYTES {
        return Err(OpmlError::FileTooLarge {
            limit_bytes: MAX_OPML_BYTES,
        });
    }
    let mut reader = Reader::from_str(xml);
    let config = reader.config_mut();
    config.trim_text(true);

    let mut podcasts: Vec<Podcast> = Vec::new();
    let mut issues: Vec<OpmlImportIssue> = Vec::new();
    let mut seen: HashSet<Url> = HashSet::new();
    let mut buf: Vec<u8> = Vec::new();

    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Start(e)) | Ok(Event::Empty(e)) => {
                if e.name().as_ref() == b"outline" {
                    let mut xml_url: Option<String> = None;
                    let mut text: Option<String> = None;
                    let mut title: Option<String> = None;
                    let mut description: Option<String> = None;
                    let mut language: Option<String> = None;

                    for attr_result in e.attributes().with_checks(false) {
                        let attr =
                            attr_result.map_err(|err| OpmlError::MalformedXml(err.to_string()))?;
                        let key = attr.key.as_ref();
                        let value = attr
                            .decode_and_unescape_value(reader.decoder())
                            .map_err(|err| OpmlError::MalformedXml(err.to_string()))?
                            .into_owned();
                        match key {
                            b"xmlUrl" => xml_url = Some(value),
                            b"text" => text = Some(value),
                            b"title" => title = Some(value),
                            b"description" => description = Some(value),
                            b"language" => language = Some(value),
                            _ => {}
                        }
                    }

                    if let Some(url_str) = xml_url {
                        let display_title = non_empty(text.as_deref())
                            .or_else(|| non_empty(title.as_deref()))
                            .unwrap_or("Invalid feed URL")
                            .to_string();
                        let Ok(feed_url) = Url::parse(url_str.trim()) else {
                            issues.push(invalid_url_issue(Some(url_str), display_title));
                            buf.clear();
                            continue;
                        };
                        if !is_http_feed_url(&feed_url) {
                            issues.push(invalid_url_issue(Some(url_str), display_title));
                            buf.clear();
                            continue;
                        }
                        if seen.insert(feed_url.clone()) {
                            if podcasts.len() >= MAX_OPML_FEEDS {
                                return Err(OpmlError::TooManyFeeds {
                                    limit: MAX_OPML_FEEDS,
                                });
                            }
                            let display_title = non_empty(text.as_deref())
                                .or_else(|| non_empty(title.as_deref()))
                                .map(str::to_owned)
                                .unwrap_or_else(|| {
                                    feed_url
                                        .host_str()
                                        .map(String::from)
                                        .unwrap_or_else(|| feed_url.as_str().to_string())
                                });
                            podcasts.push(seed_podcast(
                                feed_url,
                                display_title,
                                description.unwrap_or_default(),
                                language,
                            ));
                        }
                    }
                }
            }
            Ok(Event::Eof) => break,
            Err(e) => return Err(OpmlError::MalformedXml(e.to_string())),
            _ => {}
        }
        buf.clear();
    }

    Ok(OpmlImportReport { podcasts, issues })
}

fn seed_podcast(
    feed_url: Url,
    title: String,
    description: String,
    language: Option<String>,
) -> Podcast {
    Podcast {
        id: PodcastId::generate(),
        feed_url: Some(feed_url),
        title,
        author: String::new(),
        image_url: None,
        description,
        language,
        categories: Vec::new(),
        discovered_at: Utc::now(),
        owner_pubkey_hex: None,
        nostr_visibility: NostrVisibility::Public,
        nostr_coordinate: None,
        title_is_placeholder: false,
        last_refreshed_at: None,
        etag: None,
        last_modified: None,
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OpmlError {
    MalformedXml(String),
    FileTooLarge { limit_bytes: usize },
    TooManyFeeds { limit: usize },
}

impl fmt::Display for OpmlError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            OpmlError::MalformedXml(_) => write!(
                f,
                "This file isn't a valid OPML export. If you exported it from another podcast app, check that the export completed and try again."
            ),
            OpmlError::FileTooLarge { limit_bytes } => write!(
                f,
                "That OPML file is too large. Import files must be {} MB or smaller.",
                std::cmp::max(1, limit_bytes / 1_048_576)
            ),
            OpmlError::TooManyFeeds { limit } => write!(
                f,
                "That OPML file has more than {limit} feeds. Split it into smaller imports and try again."
            ),
        }
    }
}

impl std::error::Error for OpmlError {}

fn is_http_feed_url(url: &Url) -> bool {
    matches!(url.scheme(), "http" | "https") && url.host_str().is_some_and(|host| !host.is_empty())
}

fn non_empty(value: Option<&str>) -> Option<&str> {
    value.map(str::trim).filter(|value| !value.is_empty())
}

fn invalid_url_issue(feed_url: Option<String>, title: String) -> OpmlImportIssue {
    OpmlImportIssue {
        feed_url,
        title,
        error: "Only public http:// and https:// feed URLs can be imported.".to_string(),
    }
}
