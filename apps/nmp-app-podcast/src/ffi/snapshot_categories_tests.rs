use super::*;
use crate::ffi::projections::EpisodeSummary;
fn make_podcast(id: &str, episodes: Vec<EpisodeSummary>) -> PodcastSummary {
    PodcastSummary {
        id: id.into(),
        title: id.into(),
        episodes,
        ..PodcastSummary::default()
    }
}
fn make_episode(id: &str, categories: Vec<&str>, published_at: Option<i64>) -> EpisodeSummary {
    EpisodeSummary {
        id: id.into(),
        title: id.into(),
        ai_categories: categories.into_iter().map(|s| s.to_string()).collect(),
        published_at,
        ..EpisodeSummary::default()
    }
}
#[test]
fn empty_library_yields_empty_categories() {
    assert!(build_category_aggregate(&[]).is_empty());
}
#[test]
fn single_category_aggregates_correctly() {
    let library = vec![make_podcast(
        "p1",
        vec![
            make_episode("ep1", vec!["Tech"], Some(100)),
            make_episode("ep2", vec!["Tech"], Some(200)),
        ],
    )];
    let result = build_category_aggregate(&library);
    assert_eq!(result.len(), 1);
    assert_eq!(result[0].category, "Tech");
    assert_eq!(result[0].episode_count, 2);
    assert_eq!(result[0].podcast_count, 1);
    assert_eq!(result[0].top_episode_ids[0], "ep2");
}
#[test]
fn ordered_newest_category_first() {
    let library = vec![make_podcast(
        "p1",
        vec![
            make_episode("ep1", vec!["Old"], Some(10)),
            make_episode("ep2", vec!["New"], Some(999)),
        ],
    )];
    let result = build_category_aggregate(&library);
    assert_eq!(result[0].category, "New");
    assert_eq!(result[1].category, "Old");
}
#[test]
fn top_episode_ids_capped_at_three() {
    let episodes: Vec<EpisodeSummary> = (0..5)
        .map(|i| make_episode(&format!("ep{i}"), vec!["Cat"], Some(i as i64)))
        .collect();
    let library = vec![make_podcast("p1", episodes)];
    let result = build_category_aggregate(&library);
    assert_eq!(result[0].top_episode_ids.len(), 3);
}
