//! Network-state report capability — `nmp.network.capability`.
//!
//! iOS fires a `NetworkReport::ConnectivityChanged` event whenever the device's
//! network path changes (Wi-Fi ↔ cellular ↔ offline). Rust uses the last-known
//! state to gate Wi-Fi-only auto-downloads.
//!
//! ## Doctrine
//!
//! * **D7 — capabilities report, never decide.** iOS observes `NWPathMonitor`
//!   and sends facts (`is_wifi`, `is_connected`). Whether to start or defer a
//!   download based on that fact is a Rust policy decision.
//! * **D6 — no errors across the boundary.** Malformed payloads degrade silently.

use serde::{Deserialize, Serialize};

pub const NETWORK_CAPABILITY_NAMESPACE: &str = "nmp.network.capability";

/// Reports iOS fires to Rust when network connectivity changes.
#[derive(Debug, Deserialize, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum NetworkReport {
    /// Fired once on capability start (to prime the Rust-side state) and again
    /// whenever `NWPathMonitor` delivers a path update.
    ConnectivityChanged {
        /// `true` when the active interface is Wi-Fi (includes Wi-Fi-over-IPv6).
        is_wifi: bool,
        /// `false` when the device has no usable network path at all.
        is_connected: bool,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn connectivity_changed_round_trips() {
        let r = NetworkReport::ConnectivityChanged {
            is_wifi: true,
            is_connected: true,
        };
        let json = serde_json::to_string(&r).unwrap();
        let back: NetworkReport = serde_json::from_str(&json).unwrap();
        assert!(matches!(
            back,
            NetworkReport::ConnectivityChanged {
                is_wifi: true,
                is_connected: true
            }
        ));
    }
}
