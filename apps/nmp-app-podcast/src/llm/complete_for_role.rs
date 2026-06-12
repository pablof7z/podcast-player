//! Shared role-dispatch helper for the per-feature `*_llm.rs` callers.
//!
//! Six feature modules (`wiki_llm`, `picks_llm`, `episode_summary_llm`,
//! `categorization_llm`, `agent_llm`, `ai_chapters_llm`) each repeated the same
//! "resolve the role's model → validate its provider credentials → select the
//! backend → build an [`LlmRequest`] → `backend.complete().await`" block inside
//! their own `runtime.block_on`. This module hoists that block into one place.
//!
//! ## Two seams, one core
//!
//! * [`complete_for_role`] is the high-level helper the four *simple* callers
//!   use. It performs the whole resolve→validate→dispatch→complete block and
//!   flattens both failure modes (credential validation, transport) to
//!   `Result<String, String>` exactly as those callers did.
//! * [`resolve_request`] is the lower-level seam for the two callers
//!   (`agent_llm`, `ai_chapters_llm`) that wrap the completion in their own
//!   `tokio::time::timeout` and need the *typed* [`LlmError`] / custom error
//!   strings preserved. It returns the selected backend + built request so the
//!   caller still owns the `complete().await` step and its bespoke error
//!   mapping.
//!
//! Both seams resolve the model identically via [`role_model_or_default`] and
//! validate via [`validate_model_credentials`], so model resolution and the
//! credential-error contract are byte-identical to the pre-refactor call sites.

use std::sync::{Arc, Mutex};

use super::{
    backend_for, role_model_or_default, validate_model_credentials, LlmBackend, LlmError,
    LlmRequest,
};
use crate::store::PodcastStore;

/// Resolve a role's effective model, validate its provider credentials, and
/// build the dispatch-ready `(backend, request)` pair.
///
/// `role_config` is the role's stored model string (e.g. the value of
/// `store.wiki_model()`), already read out of the store by the caller.
/// `cloud_default` is that caller's historical bare-cloud default, applied by
/// [`role_model_or_default`] when `role_config` carries no explicit provider
/// prefix. `history` is the prior `(role, content)` turn list — empty for the
/// single-shot feature callers, populated for the agent chat loop.
///
/// On a credential-validation failure this returns the **typed** [`LlmError`]
/// (via the `Err` arm) so callers that discriminate on the error variant
/// (`ai_chapters_llm`'s `SynthError`) or wrap the message
/// (`agent_llm`'s `"{model} failed: {e}"`) keep their exact behavior. The
/// completion call itself is left to the caller.
pub fn resolve_request(
    store: &Arc<Mutex<PodcastStore>>,
    role_config: &str,
    cloud_default: &str,
    system_preamble: &str,
    user_prompt: &str,
    history: Vec<(String, String)>,
) -> Result<(Box<dyn LlmBackend>, LlmRequest), LlmError> {
    let model = role_model_or_default(role_config, cloud_default);
    validate_model_credentials(store, &model)?;
    let backend = backend_for(store, &model);
    let req = LlmRequest {
        system: system_preamble.to_owned(),
        history,
        user: user_prompt.to_owned(),
        model,
    };
    Ok((backend, req))
}

/// Run the full single-shot dispatch for a role: resolve the model, validate
/// credentials, select the backend, build the request, and await the
/// completion — collapsing every failure to `Result<String, String>`.
///
/// This is the shared body of the four single-shot callers (`wiki_llm`,
/// `picks_llm`, `episode_summary_llm`, `categorization_llm`), which all used an
/// empty `history` and flattened both the credential error and the transport
/// error to a `String`. The credential error is stringified via
/// [`LlmError`]'s `Display` and the transport error via the same
/// `From<LlmError> for String` impl those callers relied on through `?`, so the
/// error text is unchanged.
pub async fn complete_for_role(
    store: &Arc<Mutex<PodcastStore>>,
    role_config: &str,
    cloud_default: &str,
    system_preamble: &str,
    user_prompt: &str,
) -> Result<String, String> {
    let (backend, req) = resolve_request(
        store,
        role_config,
        cloud_default,
        system_preamble,
        user_prompt,
        Vec::new(),
    )
    .map_err(|e| e.to_string())?;

    backend.complete(&req).await.map_err(|e| e.to_string())
}

/// Find the first balanced-by-extremes `{ … }` JSON object slice in `text`.
///
/// Returns the slice from the first `{` to the last `}` (inclusive), or `None`
/// when either delimiter is absent or the closing brace precedes the opening
/// one. The per-feature parsers (`picks_llm::parse_picks_response`) wrap this
/// with their own error messages; this is the single source of the
/// find-first-to-last logic those copies duplicated.
pub fn extract_json_object(text: &str) -> Option<&str> {
    let start = text.find('{')?;
    let end = text.rfind('}')?;
    if end < start {
        return None;
    }
    Some(&text[start..=end])
}

/// Find the first balanced-by-extremes `[ … ]` JSON array slice in `text`.
///
/// Returns the slice from the first `[` to the last `]` (inclusive), or `None`
/// when either delimiter is absent or the closing bracket precedes the opening
/// one. Shared by `categorization_llm` and `ai_chapters_llm`, which previously
/// each carried a byte-identical copy.
pub fn extract_json_array(text: &str) -> Option<&str> {
    let start = text.find('[')?;
    let end = text.rfind(']')?;
    if end < start {
        return None;
    }
    Some(&text[start..=end])
}

#[cfg(test)]
mod tests {
    use super::{extract_json_array, extract_json_object};

    #[test]
    fn object_extracts_from_surrounding_prose() {
        let s = r#"prefix {"score": 0.6, "reason": "ok"} trailing"#;
        let got = extract_json_object(s).expect("object present");
        assert_eq!(got, r#"{"score": 0.6, "reason": "ok"}"#);
    }

    #[test]
    fn object_none_without_braces() {
        assert!(extract_json_object("no braces here").is_none());
    }

    #[test]
    fn object_none_when_close_before_open() {
        assert!(extract_json_object("} then {").is_none());
    }

    #[test]
    fn array_extracts_from_surrounding_prose() {
        let s = "prefix [\"a\", \"b\"] suffix";
        assert_eq!(extract_json_array(s).expect("array present"), r#"["a", "b"]"#);
    }

    #[test]
    fn array_none_without_brackets() {
        assert!(extract_json_array("no brackets here").is_none());
    }

    #[test]
    fn array_none_when_close_before_open() {
        assert!(extract_json_array("] then [").is_none());
    }
}
