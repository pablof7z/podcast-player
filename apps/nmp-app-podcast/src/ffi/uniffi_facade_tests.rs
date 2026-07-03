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

#[test]
fn static_catalog_methods_return_data() {
    let app = PodcastApp::new();

    let speech_catalog = app
        .speech_model_catalog()
        .expect("speech catalog should be available through the facade");
    assert_catalog_array_non_empty(&speech_catalog, "eleven_labs_stt");
    assert_catalog_array_non_empty(&speech_catalog, "open_router_whisper");

    let local_catalog = app
        .local_model_catalog()
        .expect("local catalog should be available through the facade");
    assert_catalog_array_non_empty(&local_catalog, "models");
}

fn assert_catalog_array_non_empty(envelope: &str, key: &str) {
    let value: serde_json::Value = serde_json::from_str(envelope).expect("catalog JSON envelope");
    let entries = value
        .get("result")
        .and_then(|result| result.get(key))
        .and_then(serde_json::Value::as_array)
        .unwrap_or_else(|| panic!("catalog envelope should contain result.{key}"));
    assert!(!entries.is_empty(), "catalog {key} should not be empty");
}
