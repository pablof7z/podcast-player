use super::*;
#[test]
fn fresh_store_has_default_skip_intervals() {
    let store = PodcastStore::new();
    assert!((store.skip_forward_secs() - 30.0).abs() < f64::EPSILON);
    assert!((store.skip_backward_secs() - 15.0).abs() < f64::EPSILON);
}
#[test]
fn set_skip_intervals_updates_values() {
    let mut store = PodcastStore::new();
    store.set_skip_intervals(45.0, 10.0);
    assert!((store.skip_forward_secs() - 45.0).abs() < f64::EPSILON);
    assert!((store.skip_backward_secs() - 10.0).abs() < f64::EPSILON);
}
#[test]
fn set_skip_intervals_clamps_to_bounds() {
    let mut store = PodcastStore::new();
    store.set_skip_intervals(0.0, 200.0);
    assert!((store.skip_forward_secs() - 1.0).abs() < f64::EPSILON);
    assert!((store.skip_backward_secs() - 120.0).abs() < f64::EPSILON);
}
#[test]
fn set_skip_intervals_same_value_is_noop() {
    let mut store = PodcastStore::new();
    // Writing defaults again must not change state
    store.set_skip_intervals(30.0, 15.0);
    assert!((store.skip_forward_secs() - 30.0).abs() < f64::EPSILON);
    assert!((store.skip_backward_secs() - 15.0).abs() < f64::EPSILON);
}

