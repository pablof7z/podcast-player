import Foundation
import os.log

/// `NostrSigner` backed by a NIP-46 remote signer ("bunker"). All signing is delegated
/// over an encrypted kind:24133 channel; the bunker holds the user's nsec.
///
/// Lifecycle:
/// 1. `connect()` — opens relay, sends `connect` RPC, awaits `ack`, then `get_public_key`
///    to learn the user-pubkey the bunker signs as.
/// 2. `sign(_:)` — sends `sign_event` with the canonical event JSON, awaits the signed
///    event JSON in the response.
actor RemoteSigner: NostrSigner {
    private static let logger = Logger.app("RemoteSigner")

    let bunker: BunkerURI
    /// Ephemeral session keypair we use as the kind:24133 author. Never the user's key.
    let sessionKeyPair: NostrKeyPair

    private var client: RemoteSignerClient?
    private var conversationKey: Data?
    private var userPublicKeyHex: String?

    /// In-flight requests keyed by request id.
    private var pending: [String: CheckedContinuation<Nip46Response, Error>] = [:]

    /// Per-request response timeout.
    private let requestTimeout: Duration

    init(bunker: BunkerURI, sessionKeyPair: NostrKeyPair, requestTimeout: Duration = .seconds(30)) {
        self.bunker = bunker
        self.sessionKeyPair = sessionKeyPair
        self.requestTimeout = requestTimeout
    }

    // MARK: - NostrSigner

    func publicKey() async throws -> String {
        try currentUserPublicKey()
    }

    func sign(_ draft: NostrEventDraft) async throws -> SignedNostrEvent {
        let userPub = try currentUserPublicKey()
        // Build canonical event JSON (without `id`/`sig`) for the bunker. Most bunkers
        // accept the unsigned event as a JSON-stringified object.
        let unsigned: [String: Any] = [
            "pubkey": userPub,
            "created_at": draft.createdAt,
            "kind": draft.kind,
            "tags": draft.tags,
            "content": draft.content,
        ]
        let data = try JSONSerialization.data(withJSONObject: unsigned, options: [])
        guard let payload = String(data: data, encoding: .utf8) else {
            throw NostrSignerError.invalidEventForSigning
        }
        let req = Nip46Request(method: .signEvent, params: [payload])
        let resp = try await call(req)
        guard let signedJSON = resp.result?.data(using: .utf8) else {
            throw NostrSignerError.remoteRejected("Empty `result` from bunker on sign_event")
        }
        let decoded = try JSONDecoder().decode(SignedNostrEvent.self, from: signedJSON)
        return decoded
    }

    // MARK: - Connect handshake

    /// Open the relay, run `connect` + `get_public_key`, and remember the user pubkey.
    /// Throws on any handshake failure.
    func connect() async throws -> String {
        guard let relayURLString = bunker.relays.first,
              let relayURL = URL(string: relayURLString) else {
            throw NostrSignerError.notConnected
        }
        let convKey = try Nip44.conversationKey(
            privateKeyHex: sessionKeyPair.privateKeyHex,
            peerPublicKeyHex: bunker.remotePubkeyHex
        )
        self.conversationKey = convKey

        // The receive callback comes back on this actor.
        let inbox = self
        let client = RemoteSignerClient(
            relayURL: relayURL,
            sessionPubkeyHex: sessionKeyPair.publicKeyHex,
            bunkerPubkeyHex: bunker.remotePubkeyHex
        ) { [weak inbox] sender, encrypted in
            await inbox?.handleIncoming(senderPubkey: sender, encryptedContent: encrypted)
        }
        await client.connect()
        self.client = client

        // 1. connect — pass [remote_pubkey, secret?, perms?]
        var params = [bunker.remotePubkeyHex]
        if let secret = bunker.secret { params.append(secret) }
        if !bunker.permissions.isEmpty { params.append(bunker.permissions.joined(separator: ",")) }
        let connectResp = try await call(Nip46Request(method: .connect, params: params))
        if let err = connectResp.error, !err.isEmpty {
            throw NostrSignerError.remoteRejected("connect: \(err)")
        }

        // 2. get_public_key — learn the user's signing pubkey.
        let pkResp = try await call(Nip46Request(method: .getPublicKey, params: []))
        if let err = pkResp.error, !err.isEmpty {
            throw NostrSignerError.remoteRejected("get_public_key: \(err)")
        }
        guard let pk = pkResp.result, isValidHex(pk, length: 64) else {
            throw NostrSignerError.remoteRejected("get_public_key returned an unparseable pubkey")
        }
        self.userPublicKeyHex = pk
        Self.logger.info("RemoteSigner: connected to bunker, user pubkey \(pk, privacy: .public)")
        return pk
    }

    func disconnect() async {
        await client?.disconnect()
        client = nil
        // Fail any pending continuations.
        for (_, c) in pending { c.resume(throwing: NostrSignerError.notConnected) }
        pending.removeAll()
    }

    // MARK: - Inbound dispatch

    private func handleIncoming(senderPubkey: String, encryptedContent: String) async {
        guard senderPubkey == bunker.remotePubkeyHex, let convKey = conversationKey else { return }
        guard let plaintext = try? Nip44.decrypt(payload: encryptedContent, conversationKey: convKey) else {
            Self.logger.warning("RemoteSigner: failed to decrypt incoming kind:24133")
            return
        }
        guard let response = try? Nip46Response.parse(plaintext) else { return }
        if let cont = pending.removeValue(forKey: response.id) {
            cont.resume(returning: response)
        } else {
            Self.logger.debug("RemoteSigner: dropping unmatched response id \(response.id, privacy: .public)")
        }
    }

    // MARK: - Send + await

    private func call(_ request: Nip46Request) async throws -> Nip46Response {
        guard let convKey = conversationKey else { throw NostrSignerError.notConnected }
        let json = try request.encode()
        let ciphertext = try Nip44.encrypt(plaintext: json, conversationKey: convKey)
        let draft = NostrEventDraft(
            kind: 24133,
            content: ciphertext,
            tags: [["p", bunker.remotePubkeyHex]]
        )
        // Sign with the **session** key (the bunker authenticates us via this).
        let local = LocalKeySigner(keyPair: sessionKeyPair)
        let signed = try await local.sign(draft)
        guard let client else { throw NostrSignerError.notConnected }

        // Register the continuation *before* publishing so a fast bunker can't beat us.
        let response = try await registerAndAwait(id: request.id) {
            try await client.publish(event: signed)
        }
        return response
    }

    /// Stash a continuation under `id`, run `send` (publishing the encrypted event),
    /// then race the wait against `requestTimeout`. Cleans up `pending[id]` on every exit.
    private func registerAndAwait(
        id: String,
        send: @escaping @Sendable () async throws -> Void
    ) async throws -> Nip46Response {
        let timeout = self.requestTimeout
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Nip46Response, Error>) in
            pending[id] = continuation
            Task { [weak self] in
                do {
                    try await send()
                } catch {
                    await self?.failPending(id: id, error: error)
                    return
                }
                try? await Task.sleep(for: timeout)
                await self?.failPending(id: id, error: NostrSignerError.timedOut)
            }
        }
    }

    /// If a continuation for `id` is still pending, resolve it with `error` and remove it.
    /// No-op if the response already arrived (continuation was consumed in `handleIncoming`).
    private func failPending(id: String, error: Error) {
        guard let cont = pending.removeValue(forKey: id) else { return }
        cont.resume(throwing: error)
    }

    // MARK: - Helpers

    private func currentUserPublicKey() throws -> String {
        if let pk = userPublicKeyHex { return pk }
        throw NostrSignerError.missingPublicKey
    }

    private func isValidHex(_ s: String, length: Int) -> Bool {
        guard s.count == length else { return false }
        return s.allSatisfy { ($0 >= "0" && $0 <= "9") || ($0 >= "a" && $0 <= "f") || ($0 >= "A" && $0 <= "F") }
    }
}
