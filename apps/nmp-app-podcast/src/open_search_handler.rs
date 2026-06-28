//! Legacy podcast-domain open-search guards.
//!
//! The NMP v0.8 input-intent ABI (`nmp_app_intent_classify` /
//! `nmp_app_intent_dispatch`) is the canonical route for native text-entry
//! surfaces. This module remains only for the older `podcast.open_search`
//! action, which may still be called by compatibility payload builders.

/// Detect if input looks like a Nostr private key (nsec1 prefix).
/// These must never be routed to open_search — callers should reject them
/// immediately with a user-visible warning.
pub(crate) fn looks_like_nsec_key(input: &str) -> bool {
    input.starts_with("nsec1")
}

/// Detect if input looks like a public Nostr identifier (npub/nprofile/nevent prefix).
/// Does NOT match nsec1 — private keys are handled separately via `looks_like_nsec_key`.
pub(crate) fn looks_like_nostr_identifier(input: &str) -> bool {
    input.starts_with("npub1")
        || input.starts_with("nprofile1")
        || input.starts_with("nevent1")
}

/// Detect if input looks like a NIP-05 address (user@domain.com, not http://).
pub(crate) fn looks_like_nip05_address(input: &str) -> bool {
    input.contains('@')
        && !input.starts_with("http://")
        && !input.starts_with("https://")
        && input.contains('.')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_looks_like_nostr_identifier_npub() {
        assert!(looks_like_nostr_identifier("npub1xyz"));
    }

    #[test]
    fn test_looks_like_nostr_identifier_nprofile() {
        assert!(looks_like_nostr_identifier("nprofile1xyz"));
    }

    #[test]
    fn test_looks_like_nostr_identifier_nevent() {
        assert!(looks_like_nostr_identifier("nevent1xyz"));
    }

    #[test]
    fn test_looks_like_nip05_address() {
        assert!(looks_like_nip05_address("user@example.com"));
    }

    #[test]
    fn test_nip05_rejects_http_urls() {
        assert!(!looks_like_nip05_address("http://example.com"));
    }

    #[test]
    fn test_nip05_rejects_https_urls() {
        assert!(!looks_like_nip05_address("https://example.com"));
    }

    #[test]
    fn test_looks_like_nostr_identifier_rejects_nsec() {
        // nsec1 is a private key — must NOT match as a public identifier
        assert!(!looks_like_nostr_identifier("nsec1abc"));
    }

    #[test]
    fn test_looks_like_nsec_key() {
        assert!(looks_like_nsec_key("nsec1abc"));
    }

    #[test]
    fn test_looks_like_nsec_key_rejects_npub() {
        assert!(!looks_like_nsec_key("npub1abc"));
    }

    #[test]
    fn test_nip05_rejects_no_dot() {
        assert!(!looks_like_nip05_address("user@localhost"));
    }

    #[test]
    fn test_nip05_rejects_no_at() {
        assert!(!looks_like_nip05_address("example.com"));
    }
}
