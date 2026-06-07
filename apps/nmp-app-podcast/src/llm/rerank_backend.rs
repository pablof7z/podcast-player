//! Provider-owned RAG reranking transport.
//!
//! Swift passes a provider-neutral rerank request through FFI. This module owns
//! the OpenRouter URL, auth headers, Cohere-compatible request DTO, status
//! mapping, and response parsing.

use serde::{Deserialize, Serialize};

const OPENROUTER_RERANK_URL: &str = "https://openrouter.ai/api/v1/rerank";
const REQUEST_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(30);
const X_TITLE: &str = "Podcastr";

#[derive(Debug, Clone, Deserialize)]
pub struct RerankRequest {
    pub model: String,
    pub query: String,
    pub documents: Vec<String>,
    pub top_n: Option<usize>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RerankError {
    MissingCredential(String),
    Unauthorized(String),
    RateLimited(String),
    Server { status_code: u16, message: String },
    Transport(String),
    Decoding(String),
    InvalidRequest(String),
}

impl RerankError {
    pub fn kind(&self) -> &'static str {
        match self {
            RerankError::MissingCredential(_) => "missing_api_key",
            RerankError::Unauthorized(_) => "unauthorized",
            RerankError::RateLimited(_) => "rate_limited",
            RerankError::Server { .. } => "server_error",
            RerankError::Transport(_) => "transport",
            RerankError::Decoding(_) => "decoding",
            RerankError::InvalidRequest(_) => "invalid_request",
        }
    }

    pub fn message(&self) -> &str {
        match self {
            RerankError::MissingCredential(message)
            | RerankError::Unauthorized(message)
            | RerankError::RateLimited(message)
            | RerankError::Transport(message)
            | RerankError::Decoding(message)
            | RerankError::InvalidRequest(message) => message,
            RerankError::Server { message, .. } => message,
        }
    }

    pub fn status_code(&self) -> Option<u16> {
        match self {
            RerankError::Server { status_code, .. } => Some(*status_code),
            _ => None,
        }
    }
}

#[derive(Debug, Serialize)]
struct OpenRouterRerankPayload<'a> {
    model: &'a str,
    query: &'a str,
    documents: &'a [String],
    top_n: usize,
}

#[derive(Debug, Deserialize)]
struct OpenRouterRerankResponse {
    results: Vec<OpenRouterRerankResult>,
}

#[derive(Debug, Deserialize)]
struct OpenRouterRerankResult {
    index: usize,
    relevance_score: f64,
}

fn normalized_top_n(request: &RerankRequest) -> usize {
    request
        .top_n
        .unwrap_or(request.documents.len())
        .min(request.documents.len())
}

fn validate_request(request: &RerankRequest) -> Result<(), RerankError> {
    if request.model.trim().is_empty() {
        return Err(RerankError::InvalidRequest(
            "rerank model is empty".to_owned(),
        ));
    }
    if request.query.trim().is_empty() {
        return Err(RerankError::InvalidRequest(
            "rerank query is empty".to_owned(),
        ));
    }
    Ok(())
}

fn decode_openrouter_rerank_response(text: &str) -> Result<Vec<usize>, RerankError> {
    let mut decoded: OpenRouterRerankResponse =
        serde_json::from_str(text).map_err(|e| RerankError::Decoding(e.to_string()))?;
    decoded
        .results
        .sort_by(|a, b| b.relevance_score.total_cmp(&a.relevance_score));
    Ok(decoded.results.into_iter().map(|item| item.index).collect())
}

fn map_status_error(status_code: u16, body: String) -> RerankError {
    match status_code {
        401 | 403 => RerankError::Unauthorized("OpenRouter rejected the API key".to_owned()),
        429 => RerankError::RateLimited("OpenRouter rate limited rerank requests".to_owned()),
        code => RerankError::Server {
            status_code: code,
            message: body,
        },
    }
}

pub fn rerank_openrouter(
    api_key: Option<String>,
    request: RerankRequest,
) -> Result<Vec<usize>, RerankError> {
    if request.documents.is_empty() || normalized_top_n(&request) == 0 {
        return Ok(Vec::new());
    }
    validate_request(&request)?;

    let api_key = api_key
        .filter(|key| !key.trim().is_empty())
        .ok_or_else(|| {
            RerankError::MissingCredential(
                "OpenRouter API key is not loaded in the Rust provider store".to_owned(),
            )
        })?;

    let payload = OpenRouterRerankPayload {
        model: &request.model,
        query: &request.query,
        documents: &request.documents,
        top_n: normalized_top_n(&request),
    };

    let client = reqwest::blocking::Client::builder()
        .timeout(REQUEST_TIMEOUT)
        .build()
        .map_err(|e| RerankError::Transport(e.to_string()))?;

    let response = client
        .post(OPENROUTER_RERANK_URL)
        .bearer_auth(api_key)
        .header(reqwest::header::CONTENT_TYPE, "application/json")
        .header("X-Title", X_TITLE)
        .json(&payload)
        .send()
        .map_err(|e| RerankError::Transport(e.to_string()))?;

    let status = response.status();
    let text = response
        .text()
        .map_err(|e| RerankError::Transport(e.to_string()))?;
    if !status.is_success() {
        return Err(map_status_error(status.as_u16(), text));
    }

    decode_openrouter_rerank_response(&text)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_documents_short_circuits_without_key() {
        let request = RerankRequest {
            model: "cohere/rerank-v3.5".to_owned(),
            query: "query".to_owned(),
            documents: Vec::new(),
            top_n: None,
        };

        let result = rerank_openrouter(None, request).unwrap();

        assert!(result.is_empty());
    }

    #[test]
    fn response_indices_are_sorted_by_score() {
        let text = r#"{"results":[{"index":2,"relevance_score":0.2},{"index":0,"relevance_score":0.9},{"index":1,"relevance_score":0.5}]}"#;

        let result = decode_openrouter_rerank_response(text).unwrap();

        assert_eq!(result, vec![0, 1, 2]);
    }

    #[test]
    fn status_errors_map_to_stable_kinds() {
        assert_eq!(
            map_status_error(401, "bad key".to_owned()).kind(),
            "unauthorized"
        );
        assert_eq!(
            map_status_error(429, "slow down".to_owned()).kind(),
            "rate_limited"
        );
        assert_eq!(
            map_status_error(500, "oops".to_owned()).status_code(),
            Some(500)
        );
    }

    #[test]
    fn top_n_is_clamped_to_document_count() {
        let request = RerankRequest {
            model: "cohere/rerank-v3.5".to_owned(),
            query: "query".to_owned(),
            documents: vec!["a".to_owned(), "b".to_owned()],
            top_n: Some(100),
        };

        assert_eq!(normalized_top_n(&request), 2);
    }
}
