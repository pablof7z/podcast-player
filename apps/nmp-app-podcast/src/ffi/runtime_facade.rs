//! Shared helpers behind the app-owned UniFFI facade.
//!
//! Generic NMP runtime lifecycle, identity, callback, and ref APIs are exposed
//! through the app-owned UniFFI `PodcastApp` object. This module keeps the
//! non-C Rust helpers shared by the TUI and UniFFI facade.

#[path = "runtime_facade_intent.rs"]
mod runtime_facade_intent;
pub use runtime_facade_intent::{
    classify_input_intent_json, decode_nip21_uri_json, dispatch_input_intent_json,
};
