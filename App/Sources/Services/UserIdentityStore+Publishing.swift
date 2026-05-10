import Foundation

// MARK: - User-identity publishing (slice B)
//
// Implements the wiring contract from
// `docs/spec/briefs/identity-05-synthesis.md` §5 — every method below
// mirrors the existing `publishFeedbackNote` shape: ensure a signer
// exists (auto-generate if needed), sign through the active `NostrSigner`,
// and publish through `FeedbackRelayClient.publish(..., authSigner:)`.
//
// Lives in a separate file purely to keep `UserIdentityStore.swift` under
// the 500-line hard cap defined in `AGENTS.md`.

extension UserIdentityStore {

    /// Sign + publish a kind:0 metadata event with the supplied profile
    /// fields. Mirrors the shape of `publishGeneratedProfileIfNeeded` but
    /// is driven by the EditProfile flow rather than auto-publish on first
    /// launch. The resulting event is fanned out across every relay in
    /// `FeedbackRelayClient.profileRelayURLs`; success is "at least one
    /// relay acked." Returns the signed event so callers can echo it into
    /// local profile state.
    func publishProfile(name: String, displayName: String, about: String, picture: String) async throws -> SignedNostrEvent {
        if signer == nil {
            try _ensureGeneratedKey()
        }
        guard let signer else { throw UserIdentityError.noIdentity }
        let payload: [String: String] = [
            "name": name,
            "display_name": displayName,
            "about": about,
            "picture": picture,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let content = String(data: data, encoding: .utf8) ?? "{}"
        let event = try await signer.sign(NostrEventDraft(kind: 0, content: content))
        var lastError: Error?
        var anyAck = false
        for relayURL in FeedbackRelayClient.profileRelayURLs {
            let client = FeedbackRelayClient(relayURL: relayURL)
            do {
                try await client.publish(event, authSigner: signer)
                anyAck = true
            } catch {
                lastError = error
                continue
            }
        }
        if !anyAck, let lastError {
            throw lastError
        }
        return event
    }

    /// Sign + publish a user-authored note as a kind:1 text note. Matches
    /// the row "Notes (user)" in `identity-05-synthesis.md` §5.3.
    /// `episodeCoord` is the `30311:<author>:<id>` reference (or whatever
    /// shape the episode coordinate adopts) — passed through verbatim into
    /// an `["a", episodeCoord]` tag when present. Today no call-site has
    /// an episode coord to pass in, so the tag is omitted; future episode-
    /// anchored notes will populate it.
    func publishUserNote(_ note: Note, episodeCoord: String?) async throws -> SignedNostrEvent {
        if signer == nil {
            try _ensureGeneratedKey()
        }
        guard let signer else { throw UserIdentityError.noIdentity }
        var tags: [[String]] = [["t", "note"]]
        if let episodeCoord, !episodeCoord.isEmpty {
            tags.insert(["a", episodeCoord], at: 0)
        }
        let event = try await signer.sign(NostrEventDraft(kind: 1, content: note.text, tags: tags))
        try await FeedbackRelayClient().publish(event, authSigner: signer)
        return event
    }

    /// Sign + publish a user-authored clip as a kind:9802 highlight
    /// (NIP-84). Matches the rows "Clips, source `.touch / .auto /
    /// .headphone / .carplay / .watch / .siri`" in `identity-05-synthesis.md`
    /// §5.3 — the `.agent` source is filtered at the call-site, not here.
    func publishUserClip(_ clip: Clip) async throws -> SignedNostrEvent {
        if signer == nil {
            try _ensureGeneratedKey()
        }
        guard let signer else { throw UserIdentityError.noIdentity }
        // No relay-side episode coordinate exists today; when a future
        // schema lands, the `["a", episodeCoord]` tag joins this list.
        var tags: [[String]] = [["context", clip.transcriptText]]
        if let caption = clip.caption, !caption.isEmpty {
            tags.append(["alt", caption])
        }
        let event = try await signer.sign(NostrEventDraft(kind: 9802, content: clip.transcriptText, tags: tags))
        try await FeedbackRelayClient().publish(event, authSigner: signer)
        return event
    }

}
