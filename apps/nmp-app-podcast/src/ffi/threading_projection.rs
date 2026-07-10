//! Rust-owned cross-episode threading projection.
//!
//! Swift used to persist threading topics/mentions and seed a DEBUG mock row.
//! This projection derives bounded thread rows from kernel library,
//! transcript, and categorization facts so native shells only render.

use std::collections::{HashMap, HashSet};
use std::ffi::{c_char, CStr, CString};
use std::sync::atomic::Ordering;
use std::sync::Arc;

use podcast_core::TriageDecision;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::ffi::actions::categorization_module::categorize_text;
use crate::ffi::guard::ffi_guard;
use crate::ffi::handle::PodcastHandle;

const MIN_EPISODES_PER_THREAD: usize = 3;
const MAX_TOPICS: usize = 12;
const MAX_MENTIONS_PER_TOPIC: usize = 60;

#[derive(Debug, Deserialize)]
struct ActiveTopicsRequest {
    #[serde(default)]
    podcast_ids: Vec<String>,
    #[serde(default)]
    limit: Option<usize>,
}

#[derive(Debug, Serialize)]
struct ActiveTopicsProjection {
    active_topics: Vec<ActiveThreadingTopicRow>,
}

#[derive(Debug, Serialize)]
struct ActiveThreadingTopicRow {
    topic_id: String,
    unplayed_episode_count: usize,
    mention_ids: Vec<String>,
}

#[derive(Debug, Serialize)]
pub(crate) struct ThreadingProjection {
    topics: Vec<ThreadingTopicRow>,
    mentions: Vec<ThreadingMentionRow>,
}

#[derive(Debug, Serialize)]
struct ThreadingTopicRow {
    id: String,
    slug: String,
    display_name: String,
    definition: Option<String>,
    episode_mention_count: usize,
    contradiction_count: usize,
    last_mentioned_at: Option<i64>,
}

#[derive(Debug, Serialize)]
struct ThreadingMentionRow {
    id: String,
    topic_id: String,
    episode_id: String,
    start_ms: i64,
    end_ms: i64,
    snippet: String,
    confidence: f64,
    is_contradictory: bool,
}

#[derive(Clone)]
pub(crate) struct EpisodeThreadInput {
    podcast_id: String,
    episode_id: String,
    title: String,
    description: String,
    /// Precomputed at collect time (see [`mention_source_for`]) so this
    /// struct never carries a whole transcript or timed-entry list forward —
    /// `candidate_for` only ever needs one snippet per episode, truncated to
    /// `truncate_snippet`'s 220-char cap. The naive version cloned the full
    /// transcript string/timed-entry vector for every episode on every
    /// projection build regardless of whether that episode ever became part
    /// of a qualifying thread.
    mention_source: MentionSource,
    published_at: i64,
    played: bool,
    triage_archived: bool,
}

#[derive(Clone)]
enum MentionSource {
    /// A timed transcript entry was available: exact playback position.
    TimedEntry { start_ms: i64, end_ms: i64, snippet: String },
    /// No timed entry — fall back to the plain transcript or description
    /// text (already truncated; no start/end position).
    Text(String),
}

#[derive(Clone)]
struct CandidateMention {
    episode_id: String,
    published_at: i64,
    start_ms: i64,
    end_ms: i64,
    snippet: String,
}

#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub fn nmp_app_podcast_threading_projection(
    handle: *mut PodcastHandle,
) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    ffi_guard(
        "nmp_app_podcast_threading_projection",
        std::ptr::null_mut,
        || {
            let handle_ref = unsafe { &*handle };
            let Some((_inputs, projection)) = projection_and_inputs_for_current_rev(handle_ref)
            else {
                return std::ptr::null_mut();
            };

            match serde_json::to_string(&*projection) {
                Ok(json) => match CString::new(json) {
                    Ok(c) => c.into_raw(),
                    Err(_) => std::ptr::null_mut(),
                },
                Err(_) => std::ptr::null_mut(),
            }
        },
    )
}

#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub fn nmp_app_podcast_threading_active_topics(
    handle: *mut PodcastHandle,
    request_json: *const c_char,
) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    ffi_guard(
        "nmp_app_podcast_threading_active_topics",
        std::ptr::null_mut,
        || {
            let request = if request_json.is_null() {
                ActiveTopicsRequest {
                    podcast_ids: Vec::new(),
                    limit: Some(1),
                }
            } else {
                let raw = unsafe { CStr::from_ptr(request_json) }
                    .to_string_lossy()
                    .into_owned();
                serde_json::from_str::<ActiveTopicsRequest>(&raw).unwrap_or(ActiveTopicsRequest {
                    podcast_ids: Vec::new(),
                    limit: Some(1),
                })
            };
            let allowed_podcasts: HashSet<String> = request.podcast_ids.into_iter().collect();
            let limit = request.limit.unwrap_or(1).max(1).min(MAX_TOPICS);

            let handle_ref = unsafe { &*handle };
            let Some((inputs, projection)) = projection_and_inputs_for_current_rev(handle_ref)
            else {
                return std::ptr::null_mut();
            };
            let active =
                build_active_topics(&projection, inputs.as_slice(), &allowed_podcasts, limit);

            match serde_json::to_string(&active) {
                Ok(json) => match CString::new(json) {
                    Ok(c) => c.into_raw(),
                    Err(_) => std::ptr::null_mut(),
                },
                Err(_) => std::ptr::null_mut(),
            }
        },
    )
}

/// Fetch the `(inputs, projection)` pair for the library's current rev,
/// rebuilding only on a cache miss.
///
/// `build_projection` scans every episode (categorization + candidate-mention
/// selection) and `collect_thread_inputs` clones each episode's transcript
/// data — real work that both FFI entry points need, and that HomeView's
/// `.task` blocks can trigger several times per launch as the library and
/// categorizer cache settle. Caching by `state.infra.rev` (the same counter
/// `snapshot_cache` uses) means a burst of same-rev calls costs one rebuild
/// plus cheap `Arc` clones instead of re-scanning the whole library each time.
/// Returns `None` only if the store mutex is poisoned.
fn projection_and_inputs_for_current_rev(
    handle: &PodcastHandle,
) -> Option<(Arc<Vec<EpisodeThreadInput>>, Arc<ThreadingProjection>)> {
    let rev = handle.state.infra.rev.load(Ordering::Relaxed);
    if let Ok(cache) = handle.threading_projection_cache.lock() {
        if let Some((cached_rev, ref inputs, ref projection)) = *cache {
            if cached_rev == rev {
                return Some((Arc::clone(inputs), Arc::clone(projection)));
            }
        }
    }

    let categories = handle.state.categories.categories_snapshot();
    let inputs = {
        let store = handle.state.library.store.lock().ok()?;
        collect_thread_inputs(&store, handle)
    };
    let projection = build_projection(inputs.clone(), &categories);
    let inputs = Arc::new(inputs);
    let projection = Arc::new(projection);

    if let Ok(mut cache) = handle.threading_projection_cache.lock() {
        *cache = Some((rev, Arc::clone(&inputs), Arc::clone(&projection)));
    }
    Some((inputs, projection))
}

fn collect_thread_inputs(
    store: &crate::store::PodcastStore,
    handle: &PodcastHandle,
) -> Vec<EpisodeThreadInput> {
    let mut inputs = Vec::new();
    for (_podcast, episodes) in store.all_podcasts() {
        for ep in episodes {
            let id = ep.id.0.to_string();
            inputs.push(EpisodeThreadInput {
                podcast_id: ep.podcast_id.0.to_string(),
                episode_id: id.clone(),
                title: ep.title.clone(),
                // Memoized (see `PodcastHandle::clean_html`) — the raw
                // description is immutable per content, so a same-content
                // rebuild reuses the already-cleaned string instead of
                // re-running the HTML strip for every episode again.
                description: handle.clean_html(&ep.description),
                mention_source: mention_source_for(store, &id, &ep.description),
                published_at: ep.pub_date.timestamp(),
                played: ep.played,
                triage_archived: ep.triage_decision == Some(TriageDecision::Archived),
            });
        }
    }
    inputs
}

/// Pick the one snippet `candidate_for` will ever need for this episode,
/// without cloning the whole transcript or timed-entry list to get it: the
/// first non-empty timed entry if one exists, else the transcript (falling
/// back to the description) truncated up front.
fn mention_source_for(
    store: &crate::store::PodcastStore,
    episode_id: &str,
    description: &str,
) -> MentionSource {
    if let Some(entry) = store
        .timed_transcript_for(episode_id)
        .and_then(|entries| entries.iter().find(|entry| !entry.text.trim().is_empty()))
    {
        return MentionSource::TimedEntry {
            start_ms: seconds_to_ms(entry.start_secs),
            end_ms: seconds_to_ms(entry.end_secs),
            snippet: truncate_snippet(&entry.text),
        };
    }
    let text = store
        .transcript_for(episode_id)
        .filter(|s| !s.trim().is_empty())
        .unwrap_or(description);
    MentionSource::Text(truncate_snippet(text))
}

fn build_projection(
    inputs: Vec<EpisodeThreadInput>,
    categories: &HashMap<String, Vec<String>>,
) -> ThreadingProjection {
    let mut by_topic: HashMap<String, Vec<CandidateMention>> = HashMap::new();

    for input in inputs {
        let labels = categories
            .get(&input.episode_id)
            .cloned()
            .unwrap_or_else(|| categorize_text(&input.title, &input.description));
        for label in labels {
            if label.trim().is_empty() {
                continue;
            }
            by_topic
                .entry(label)
                .or_default()
                .push(candidate_for(&input));
        }
    }

    let mut topic_rows: Vec<(i64, ThreadingTopicRow, Vec<ThreadingMentionRow>)> = Vec::new();
    for (label, mut candidates) in by_topic {
        let episode_ids: HashSet<String> = candidates.iter().map(|m| m.episode_id.clone()).collect();
        if episode_ids.len() < MIN_EPISODES_PER_THREAD {
            continue;
        }
        candidates.sort_by(|a, b| {
            b.published_at
                .cmp(&a.published_at)
                .then_with(|| a.episode_id.cmp(&b.episode_id))
        });
        candidates.truncate(MAX_MENTIONS_PER_TOPIC);

        let slug = slugify(&label);
        if slug.is_empty() {
            continue;
        }
        let topic_id = stable_uuid(&format!("thread-topic:{slug}")).to_string();
        let last_mentioned_at = candidates.first().map(|m| m.published_at);
        let topic = ThreadingTopicRow {
            id: topic_id.clone(),
            slug,
            display_name: label.clone(),
            definition: Some(format!(
                "Episodes the kernel categorizer grouped under {label}."
            )),
            episode_mention_count: episode_ids.len(),
            contradiction_count: 0,
            last_mentioned_at,
        };
        let mentions = candidates
            .into_iter()
            .map(|m| ThreadingMentionRow {
                id: stable_uuid(&format!("thread-mention:{topic_id}:{}", m.episode_id)).to_string(),
                topic_id: topic_id.clone(),
                episode_id: m.episode_id,
                start_ms: m.start_ms,
                end_ms: m.end_ms,
                snippet: m.snippet,
                confidence: 0.68,
                is_contradictory: false,
            })
            .collect();
        topic_rows.push((last_mentioned_at.unwrap_or(0), topic, mentions));
    }

    topic_rows.sort_by(|a, b| {
        b.0.cmp(&a.0)
            .then_with(|| a.1.display_name.cmp(&b.1.display_name))
    });
    topic_rows.truncate(MAX_TOPICS);

    let mut topics = Vec::new();
    let mut mentions = Vec::new();
    for (_, topic, topic_mentions) in topic_rows {
        topics.push(topic);
        mentions.extend(topic_mentions);
    }
    ThreadingProjection { topics, mentions }
}

fn build_active_topics(
    projection: &ThreadingProjection,
    inputs: &[EpisodeThreadInput],
    allowed_podcasts: &HashSet<String>,
    limit: usize,
) -> ActiveTopicsProjection {
    let topic_by_id: HashMap<String, &ThreadingTopicRow> = projection
        .topics
        .iter()
        .map(|topic| (topic.id.clone(), topic))
        .collect();
    let episode_by_id: HashMap<String, &EpisodeThreadInput> = inputs
        .iter()
        .map(|episode| (episode.episode_id.clone(), episode))
        .collect();
    let mut episodes_by_topic: HashMap<String, HashSet<String>> = HashMap::new();
    let mut mentions_by_topic: HashMap<String, Vec<String>> = HashMap::new();

    for mention in &projection.mentions {
        let Some(episode) = episode_by_id.get(&mention.episode_id) else {
            continue;
        };
        if episode.played || episode.triage_archived {
            continue;
        }
        if !allowed_podcasts.is_empty() && !allowed_podcasts.contains(&episode.podcast_id) {
            continue;
        }
        episodes_by_topic
            .entry(mention.topic_id.clone())
            .or_default()
            .insert(mention.episode_id.clone());
        mentions_by_topic
            .entry(mention.topic_id.clone())
            .or_default()
            .push(mention.id.clone());
    }

    let mut rows: Vec<ActiveThreadingTopicRow> = episodes_by_topic
        .into_iter()
        .filter_map(|(topic_id, episode_ids)| {
            if episode_ids.len() < MIN_EPISODES_PER_THREAD {
                return None;
            }
            let mention_ids = mentions_by_topic.remove(&topic_id).unwrap_or_default();
            Some(ActiveThreadingTopicRow {
                topic_id,
                unplayed_episode_count: episode_ids.len(),
                mention_ids,
            })
        })
        .collect();

    rows.sort_by(|a, b| {
        let a_topic = topic_by_id.get(&a.topic_id);
        let b_topic = topic_by_id.get(&b.topic_id);
        b.unplayed_episode_count
            .cmp(&a.unplayed_episode_count)
            .then_with(|| {
                b_topic
                    .and_then(|topic| topic.last_mentioned_at)
                    .unwrap_or(0)
                    .cmp(&a_topic.and_then(|topic| topic.last_mentioned_at).unwrap_or(0))
            })
            .then_with(|| {
                a_topic
                    .map(|topic| topic.display_name.as_str())
                    .unwrap_or("")
                    .cmp(b_topic.map(|topic| topic.display_name.as_str()).unwrap_or(""))
            })
    });
    rows.truncate(limit);

    ActiveTopicsProjection {
        active_topics: rows,
    }
}

fn candidate_for(input: &EpisodeThreadInput) -> CandidateMention {
    match &input.mention_source {
        MentionSource::TimedEntry { start_ms, end_ms, snippet } => CandidateMention {
            episode_id: input.episode_id.clone(),
            published_at: input.published_at,
            start_ms: *start_ms,
            end_ms: *end_ms,
            snippet: snippet.clone(),
        },
        MentionSource::Text(snippet) => CandidateMention {
            episode_id: input.episode_id.clone(),
            published_at: input.published_at,
            start_ms: 0,
            end_ms: 0,
            snippet: snippet.clone(),
        },
    }
}

fn seconds_to_ms(secs: f64) -> i64 {
    if secs.is_finite() && secs > 0.0 {
        (secs * 1000.0).round() as i64
    } else {
        0
    }
}

fn truncate_snippet(text: &str) -> String {
    let cleaned = text.split_whitespace().collect::<Vec<_>>().join(" ");
    cleaned.chars().take(220).collect()
}

fn slugify(input: &str) -> String {
    let mut out = String::new();
    let mut last_dash = false;
    for ch in input.to_ascii_lowercase().chars() {
        if ch.is_ascii_alphanumeric() {
            out.push(ch);
            last_dash = false;
        } else if !last_dash {
            out.push('-');
            last_dash = true;
        }
    }
    out.trim_matches('-').to_owned()
}

fn stable_uuid(seed: &str) -> Uuid {
    Uuid::new_v5(&Uuid::NAMESPACE_URL, seed.as_bytes())
}

#[cfg(test)]
#[path = "threading_projection_tests.rs"]
mod tests;
