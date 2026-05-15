//! Holds the current user's keys / signer state. Pure state; relay I/O lives
//! in [`crate::nostr_runtime`].

use nostr_sdk::prelude::*;

use crate::errors::CoreError;

#[derive(Default)]
pub struct Session {
    keys: Option<Keys>,
    pubkey: Option<PublicKey>,
}

impl Session {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn keys(&self) -> Option<&Keys> {
        self.keys.as_ref()
    }

    pub fn pubkey(&self) -> Option<&PublicKey> {
        self.pubkey.as_ref()
    }

    pub fn is_authenticated(&self) -> bool {
        self.pubkey.is_some()
    }

    /// Log in with a hex or nsec/nprofile private key.
    pub fn login_nsec(&mut self, secret: &str) -> Result<PublicKey, CoreError> {
        let keys = if secret.starts_with("nsec1") {
            let parsed = SecretKey::from_bech32(secret)
                .map_err(|e| CoreError::InvalidInput(e.to_string()))?;
            Keys::new(parsed)
        } else {
            let parsed = SecretKey::from_hex(secret)
                .map_err(|e| CoreError::InvalidInput(e.to_string()))?;
            Keys::new(parsed)
        };
        let pubkey = keys.public_key();
        self.keys = Some(keys);
        self.pubkey = Some(pubkey);
        Ok(pubkey)
    }

    /// Log in with a public key only (read-only / NIP-46 pending mode).
    pub fn login_pubkey(&mut self, npub_or_hex: &str) -> Result<PublicKey, CoreError> {
        let pk = if npub_or_hex.starts_with("npub1") {
            PublicKey::from_bech32(npub_or_hex)
                .map_err(|e| CoreError::InvalidInput(e.to_string()))?
        } else {
            PublicKey::from_hex(npub_or_hex)
                .map_err(|e| CoreError::InvalidInput(e.to_string()))?
        };
        self.keys = None;
        self.pubkey = Some(pk);
        Ok(pk)
    }

    pub fn logout(&mut self) {
        self.keys = None;
        self.pubkey = None;
    }
}
