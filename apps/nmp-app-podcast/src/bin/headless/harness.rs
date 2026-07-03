use std::time::{Duration, Instant};

use nmp_app_podcast::ffi::{PodcastApp, PodcastUpdate};

/// Dispatch a JSON action to the kernel and return the decoded result value.
///
/// The `namespace` / `payload` shape must match the registered `ActionModule`
/// for that namespace. Returns `serde_json::Value::Null` on any failure.
pub fn dispatch(
    app: &PodcastApp,
    namespace: &str,
    payload: serde_json::Value,
) -> serde_json::Value {
    app.dispatch_podcast_action(namespace.to_owned(), payload.to_string())
        .and_then(|json| serde_json::from_str(&json).ok())
        .unwrap_or_else(|| serde_json::json!({"error": "dispatch returned no envelope"}))
}

/// Read the current podcast snapshot through the app-owned facade.
pub fn snapshot(app: &PodcastApp) -> Option<PodcastUpdate> {
    app.podcast_update_for_rust()
}

/// Returns `true` if a TCP connection to `host:port` can be established within 2 seconds.
/// Used by scenarios to gate on optional external services (e.g. Ollama).
///
/// Resolves the hostname via DNS first (using `std::net::ToSocketAddrs`), then
/// tries every resolved address. This matters for `localhost`: some machines
/// return `::1` first even when the service only listens on IPv4.
pub fn probe_tcp(host: &str, port: u16) -> bool {
    use std::net::{TcpStream, ToSocketAddrs};
    use std::time::Duration;
    let timeout = Duration::from_secs(2);
    let addr_str = format!("{host}:{port}");
    match addr_str.to_socket_addrs() {
        Ok(addrs) => addrs
            .into_iter()
            .any(|addr| TcpStream::connect_timeout(&addr, timeout).is_ok()),
        Err(_) => false,
    }
}

/// Poll the snapshot every 100 ms until `pred` returns `true` or `timeout_ms`
/// elapses. Returns `Ok(update)` on success, `Err(msg)` on timeout.
///
/// Uses `PodcastApp::podcast_snapshot_rev` (atomic read, no lock) to detect when
/// the store has changed, then reads the typed snapshot. This avoids blocking
/// indefinitely on the store mutex while the actor thread is doing a
/// long-running subscribe write.
pub fn wait_for<F>(app: &PodcastApp, timeout_ms: u64, pred: F) -> Result<PodcastUpdate, String>
where
    F: Fn(&PodcastUpdate) -> bool,
{
    let deadline = Instant::now() + Duration::from_millis(timeout_ms);
    let mut last_rev = app.podcast_snapshot_rev();
    loop {
        // Check deadline first so we don't do extra work past it.
        if Instant::now() >= deadline {
            break;
        }
        std::thread::sleep(Duration::from_millis(100));
        let rev = app.podcast_snapshot_rev();
        if rev != last_rev {
            last_rev = rev;
            if let Some(update) = snapshot(app) {
                if pred(&update) {
                    return Ok(update);
                }
            }
        }
    }
    Err(format!("wait_for timed out after {timeout_ms} ms"))
}
