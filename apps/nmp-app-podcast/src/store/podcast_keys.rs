//! Per-podcast keypair store for NIP-F4 owned podcast publishing
//! (features #27/#28).
//!
//! Each podcast the user "owns" — i.e. has chosen to publish as a
//! NIP-F4 `kind:10154` show event — gets its own Nostr secret key.
//! The public key derived from it is what appears in the show event,
//! and (collectively) in the user's `kind:10064` author-claim event
//! under the agent identity.
//!
//! ## Scope
//!
//! * In-memory only — disk persistence belongs to the future
//!   `PodcastStore` schema bump (tracked: p0-nipf4-real-keys).
//! * Pubkey derivation uses real secp256k1 (via the `nostr` crate).
//! * Key generation uses `nostr::Keys::generate()` which delegates to
//!   a cryptographically-random source on every supported platform.
//!
//! ## D6
//!
//! Every lookup is total: `None` for missing keys, never panics on
//! poisoned mutexes higher up the stack.

use std::collections::HashMap;

use nostr::{Keys, SecretKey};

/// In-memory per-podcast secret-key store.
///
/// Keyed by `podcast_id` (UUID hyphenated string — the same form the
/// FFI `PodcastSummary.id` carries) so the action module can resolve a
/// row purely from the wire payload it received.
#[derive(Default)]
pub struct PodcastKeyStore {
    keys: HashMap<String, [u8; 32]>,
}

impl PodcastKeyStore {
    pub fn new() -> Self {
        Self {
            keys: HashMap::new(),
        }
    }

    /// Generate (or replace) a cryptographically-random secp256k1
    /// secret key for `podcast_id`. Returns the raw 32-byte scalar so
    /// callers can persist or inspect without a second lookup.
    pub fn generate_key(&mut self, podcast_id: &str) -> [u8; 32] {
        let sk = nostr::Keys::generate().secret_key().to_secret_bytes();
        self.keys.insert(podcast_id.to_owned(), sk);
        sk
    }

    pub fn get_key(&self, podcast_id: &str) -> Option<&[u8; 32]> {
        self.keys.get(podcast_id)
    }

    pub fn remove_key(&mut self, podcast_id: &str) {
        self.keys.remove(podcast_id);
    }

    /// x-only public key (hex) derived from the stored secp256k1 secret
    /// key for `podcast_id`. Returns `None` when the podcast is unknown.
    pub fn pubkey_hex(&self, podcast_id: &str) -> Option<String> {
        self.keys.get(podcast_id).map(derive_pubkey_hex)
    }

    /// Iterator over `(podcast_id, pubkey_hex)` for every key currently
    /// known to the store. Used by the snapshot builder to populate
    /// `PodcastUpdate.owned_podcasts` and by `publish_author_claim`
    /// to enumerate `p` tags.
    pub fn iter_pubkeys(&self) -> Vec<(String, String)> {
        self.keys
            .iter()
            .map(|(id, sk)| (id.clone(), derive_pubkey_hex(sk)))
            .collect()
    }
}

/// Derive the x-only secp256k1 public key (lowercase hex) from a
/// 32-byte secret key scalar. The fallback branch (invalid scalar) is
/// astronomically unlikely with randomly-generated keys.
fn derive_pubkey_hex(sk: &[u8; 32]) -> String {
    SecretKey::from_slice(sk)
        .map(|sk| Keys::new(sk).public_key().to_hex())
        .unwrap_or_else(|_| {
            // Invalid scalar (< 1 in 2^128 probability with random input).
            // Return the raw bytes as hex so callers still get 64 chars.
            sk.iter().fold(String::with_capacity(64), |mut s, b| {
                s.push_str(&format!("{:02x}", b));
                s
            })
        })
}

#[cfg(test)]
#[path = "podcast_keys_tests.rs"]
mod tests;
