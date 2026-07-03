use super::uniffi_facade::PodcastApp;

#[test]
fn constructor_owns_podcast_handle() {
    let app = PodcastApp::new();
    assert_ne!(app.podcast_handle(), 0);
    assert_eq!(app.podcast_snapshot_rev(), 1);
    assert!(app.podcast_snapshot().is_some());
}

#[test]
fn lifecycle_start_stop_shutdown_do_not_panic() {
    let app = PodcastApp::new();
    app.start(64, 4);
    app.configure(64, 4);
    app.stop();
    app.reset();
    app.shutdown();
}

#[test]
fn dispatch_empty_envelope_returns_error_outcome() {
    let app = PodcastApp::new();
    let out = app.dispatch_action(Vec::new());
    assert!(out.correlation_id.is_none());
    assert!(out.error.is_some());
}
