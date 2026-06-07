use super::parse_dispatch_envelope;

#[test]
fn dispatch_envelope_accepts_nested_ok_result() {
    let value = serde_json::json!({
        "correlation_id": "corr-1",
        "result_json": "{\"ok\":true}"
    });

    assert_eq!(parse_dispatch_envelope(&value).unwrap(), "corr-1");
}

#[test]
fn dispatch_envelope_rejects_nested_error_result() {
    let value = serde_json::json!({
        "correlation_id": "corr-1",
        "result_json": "{\"ok\":false,\"error\":\"task disabled\"}"
    });

    assert_eq!(
        parse_dispatch_envelope(&value),
        Err("task disabled".to_owned())
    );
}

#[test]
fn dispatch_envelope_rejects_nested_failed_status() {
    let value = serde_json::json!({
        "correlation_id": "corr-1",
        "result_json": "{\"ok\":false,\"status\":\"failed\"}"
    });

    assert_eq!(
        parse_dispatch_envelope(&value),
        Err("action failed: failed".to_owned())
    );
}

#[test]
fn dispatch_envelope_rejects_top_level_action_error() {
    let value = serde_json::json!({
        "correlation_id": "corr-1",
        "ok": false,
        "error": "bad input"
    });

    assert_eq!(parse_dispatch_envelope(&value), Err("bad input".to_owned()));
}
