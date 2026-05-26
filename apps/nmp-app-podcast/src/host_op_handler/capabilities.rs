//! Capability dispatch helpers and settings action handler for
//! [`super::PodcastHostOpHandler`].
//!
//! Extracted from `host_op_handler.rs` to keep that file within the 300-line
//! soft limit. All methods here are thin wrappers that serialize a typed
//! command to JSON and hand it to `NmpApp::dispatch_capability`.

use std::sync::atomic::Ordering;

use nmp_core::substrate::CapabilityRequest;

use crate::ad_skip_handler::handle_set_auto_skip_ads;
use crate::capability::{
    notification_command_json, AudioCommand, DownloadCommand, NotificationCommand,
    AUDIO_CAPABILITY_NAMESPACE, DOWNLOAD_CAPABILITY_NAMESPACE, NOTIFICATION_CAPABILITY_NAMESPACE,
};
use crate::ffi::actions::settings_module::SettingsAction;
use podcast_feeds::http::{HttpRequest, HttpResult, HTTP_CAPABILITY_NAMESPACE};

use super::PodcastHostOpHandler;

impl PodcastHostOpHandler {
    pub(crate) fn dispatch_http(
        &self,
        req: &HttpRequest,
        correlation_id: &str,
    ) -> Result<HttpResult, String> {
        let payload_json = serde_json::to_string(req).map_err(|e| e.to_string())?;
        let cap_req = CapabilityRequest {
            namespace: HTTP_CAPABILITY_NAMESPACE.to_owned(),
            correlation_id: correlation_id.to_owned(),
            payload_json,
        };
        let envelope = unsafe { &*self.app }.dispatch_capability(&cap_req);
        serde_json::from_str::<HttpResult>(&envelope.result_json)
            .map_err(|e| format!("decode http result: {e}"))
    }

    pub(crate) fn dispatch_audio(
        &self,
        cmd: &AudioCommand,
        correlation_id: &str,
    ) -> Result<(), String> {
        let payload_json = serde_json::to_string(cmd).map_err(|e| e.to_string())?;
        let req = CapabilityRequest {
            namespace: AUDIO_CAPABILITY_NAMESPACE.to_owned(),
            correlation_id: correlation_id.to_owned(),
            payload_json,
        };
        let _ = unsafe { &*self.app }.dispatch_capability(&req);
        Ok(())
    }

    pub(super) fn dispatch_download(
        &self,
        cmd: &DownloadCommand,
        correlation_id: &str,
    ) -> Result<(), String> {
        let payload_json = serde_json::to_string(cmd).map_err(|e| e.to_string())?;
        let req = CapabilityRequest {
            namespace: DOWNLOAD_CAPABILITY_NAMESPACE.to_owned(),
            correlation_id: correlation_id.to_owned(),
            payload_json,
        };
        let _ = unsafe { &*self.app }.dispatch_capability(&req);
        Ok(())
    }

    /// Fire-and-forget notification dispatch. Mirrors the audio/download
    /// envelope shape so the iOS-side router can fan out by namespace
    /// without special-casing.
    pub(super) fn dispatch_notification(
        &self,
        cmd: &NotificationCommand,
        correlation_id: &str,
    ) -> Result<(), String> {
        let payload_json = notification_command_json(cmd);
        let req = CapabilityRequest {
            namespace: NOTIFICATION_CAPABILITY_NAMESPACE.to_owned(),
            correlation_id: correlation_id.to_owned(),
            payload_json,
        };
        let _ = unsafe { &*self.app }.dispatch_capability(&req);
        Ok(())
    }

    pub(crate) fn handle_settings_action(&self, action: SettingsAction) -> serde_json::Value {
        match action {
            SettingsAction::SetAutoSkipAds { enabled } => {
                handle_set_auto_skip_ads(&self.store, &self.player_actor, &self.rev, enabled)
            }
            SettingsAction::SetSkipIntervals { forward_secs, backward_secs } => {
                if let Ok(mut s) = self.store.lock() {
                    s.set_skip_intervals(forward_secs, backward_secs);
                }
                self.rev.fetch_add(1, Ordering::Relaxed);
                serde_json::json!({"ok": true})
            }
        }
    }
}
