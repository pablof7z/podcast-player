//! ADR-0064 typed dispatch helper used by the UniFFI facade.

use super::handle::PodcastHandle;

pub(crate) fn dispatch_action_json(
    handle: &PodcastHandle,
    namespace: &str,
    action_json: &str,
) -> String {
    match crate::dispatch_bytes::dispatch_action_bytes_for(handle.app, namespace, action_json) {
        Ok(correlation_id) => format!(r#"{{"correlation_id":"{correlation_id}"}}"#),
        Err(e) => {
            let escaped = e.replace('\\', r"\\").replace('"', r#"\""#);
            format!(r#"{{"error":"{escaped}"}}"#)
        }
    }
}
