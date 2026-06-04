import Foundation

// MARK: - SignedNostrEvent
//
// A plain Codable DATA struct mirroring the NIP-01 wire shape. This is NOT
// crypto — it carries no key material and performs no signing. It is the
// decoded shape of an event delivered by the kernel's feedback projection
// (`FeedbackEventDTO.asSignedEvent` in `PodcastUpdate.generated.swift`), and
// is consumed by the feedback thread builder (`FeedbackModels`,
// `FeedbackStore.buildThreads`).
//
// All signing and key ownership lives in the Rust kernel (NMP). The Swift app
// never constructs, signs, or verifies these events — it only reads the fields
// the kernel already populated to render feedback threads.

/// Fully-signed Nostr event, as decoded from the kernel feedback projection.
/// A passive data carrier — `id` / `pubkey` / `sig` are read-only fields the
/// kernel filled in, never computed here.
struct SignedNostrEvent: Sendable, Equatable, Codable {
    let id: String        // 32-byte hex event id (computed kernel-side).
    let pubkey: String    // 32-byte hex x-only pubkey of the author.
    let created_at: Int
    let kind: Int
    let tags: [[String]]
    let content: String
    let sig: String       // 64-byte hex signature (produced kernel-side).
}

// MARK: - Feedback thread helpers

extension SignedNostrEvent {
    /// The `a`-tag coordinates (e.g. project addressable references) on this event.
    var projectATags: [String] {
        tags.compactMap { tag in
            tag.count >= 2 && tag[0] == "a" ? tag[1] : nil
        }
    }

    /// The `e`-tag event ids referenced by this event.
    var eTagIDs: [String] {
        tags.compactMap { tag in
            tag.count >= 2 && tag[0] == "e" ? tag[1] : nil
        }
    }

    /// The NIP-10 root event id this event replies under: prefer an explicit
    /// `["e", id, relay, "root"]` marker, else fall back to the first `e` tag.
    var rootEventID: String? {
        if let marked = tags.first(where: { tag in
            tag.count >= 4 && tag[0] == "e" && tag[3] == "root"
        }) {
            return marked[1]
        }
        return eTagIDs.first
    }
}
