//! `nmp_app_podcast_provider_model_catalog` — shared provider model catalog.

use std::ffi::{c_char, CString};
use std::sync::Arc;

use super::guard::ffi_guard;
use super::handle::PodcastHandle;
use crate::llm::model_catalog;

#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub fn nmp_app_podcast_provider_model_catalog(
    handle: *mut PodcastHandle,
) -> *mut c_char {
    if handle.is_null() {
        return err_envelope("null handle").into_raw();
    }
    ffi_guard(
        "nmp_app_podcast_provider_model_catalog",
        || err_envelope("panic").into_raw(),
        || {
            let handle_ref = unsafe { &*handle };
            json_envelope(provider_model_catalog_json(handle_ref)).into_raw()
        },
    )
}

pub(crate) fn provider_model_catalog_json(handle: &PodcastHandle) -> String {
    let store = Arc::clone(&handle.state.library.store);
    let runtime = Arc::clone(&handle.state.infra.runtime);
    let value = match runtime.block_on(model_catalog::fetch_model_catalog(store)) {
        Ok(result) => serde_json::json!({"result": result}),
        Err(error) => serde_json::json!({"error": error.to_string()}),
    };
    value.to_string()
}

fn json_envelope(value: String) -> CString {
    CString::new(value).unwrap_or_else(|_| CString::new(r#"{"error":"encoding"}"#).unwrap())
}

fn err_envelope(reason: &str) -> CString {
    let json = serde_json::json!({"error": reason}).to_string();
    CString::new(json).unwrap_or_else(|_| CString::new(r#"{"error":"encoding"}"#).unwrap())
}
