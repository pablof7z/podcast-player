use thiserror::Error;

#[derive(Debug, Error, uniffi::Error)]
#[uniffi(flat_error)]
pub enum CoreError {
    #[error("not initialized")]
    NotInitialized,
    #[error("not authenticated")]
    NotAuthenticated,
    #[error("invalid input: {0}")]
    InvalidInput(String),
    #[error("network error: {0}")]
    Network(String),
    #[error("signer error: {0}")]
    Signer(String),
    #[error("relay error: {0}")]
    Relay(String),
    #[error("not found")]
    NotFound,
    #[error("{0}")]
    Other(String),
}

impl From<anyhow::Error> for CoreError {
    fn from(value: anyhow::Error) -> Self {
        Self::Other(value.to_string())
    }
}

impl From<nostr_sdk::client::Error> for CoreError {
    fn from(value: nostr_sdk::client::Error) -> Self {
        Self::Other(value.to_string())
    }
}

impl From<nostr::event::Error> for CoreError {
    fn from(value: nostr::event::Error) -> Self {
        Self::Other(value.to_string())
    }
}

impl From<nostr::key::Error> for CoreError {
    fn from(value: nostr::key::Error) -> Self {
        Self::Signer(value.to_string())
    }
}

impl From<serde_json::Error> for CoreError {
    fn from(value: serde_json::Error) -> Self {
        Self::InvalidInput(value.to_string())
    }
}

impl From<reqwest::Error> for CoreError {
    fn from(value: reqwest::Error) -> Self {
        Self::Network(value.to_string())
    }
}
