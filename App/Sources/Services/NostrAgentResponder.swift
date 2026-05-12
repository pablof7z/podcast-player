import Foundation
import os.log

/// Drives the inbound-to-LLM-to-outbound pipeline for kind:1 messages
/// from a Nostr pubkey the user has approved. Owned by
/// `NostrRelayService` and invoked from its allowed-pubkey branch.
///
/// Responsibilities (parity with `win-the-day` `NostrAgentService.handleInbound`):
///   • Dedup via `state.nostrRespondedEventIDs` (persisted).
///   • Bump `state.nostrSinceCursor` before model invocation so a crash
///     mid-reply still moves the cursor forward.
///   • Honour the per-thread end-conversation gate (`wtd-end` tag + the
///     in-memory `nostrEndedRootIDs` set).
///   • Enforce a per-root outgoing turn cap.
///   • Fetch the thread, fetch the peer's kind:0 (bounded at 2s), build
///     the message history with identity prefixes, invoke `AgentLLMClient`
///     one-shot, sign + publish the kind:1 reply with NIP-10 tags, and
///     record both incoming + outgoing turns into the store.
///
/// Agent invocation: we call `AgentLLMClient.streamCompletion` directly
/// rather than going through `AgentChatSession`. Rationale: chat session
/// is `@Observable`, owns a `ChatHistoryStore` conversation row,
/// auto-resumes, swaps between "initial" and "thinking" models, and
/// drives the typing-indicator + skill-enable UI state. None of that is
/// useful for a one-shot peer reply; reusing it would force us to
/// instantiate a phantom conversation, suppress half the UI hooks, and
/// drag in the full tool dispatcher. The lower-level
/// `AgentLLMClient.streamCompletion` already handles provider switching
/// + credential resolution + cost-ledger logging, which is exactly what
/// we need.
@MainActor
final class NostrAgentResponder {

    nonisolated private static let logger = Logger.app("NostrAgentResponder")

    /// Inbound payload, decoded from the relay frame by the caller.
    struct Inbound: Sendable, Equatable {
        let eventID: String
        let pubkey: String
        let createdAt: Int
        let content: String
        let tags: [[String]]
        /// Full event dictionary serialised back to JSON for transcript
        /// export. May be nil if serialisation fails — the conversation
        /// store accepts nil there.
        let rawEventJSON: String?
    }

    /// Per-root outgoing turn cap. Once we've published this many
    /// outbound notes on the same conversation root, further inbounds
    /// on that root are silently swallowed — defence against runaway
    /// agent-on-agent loops.
    private static let maxOutgoingTurnsPerRoot = 10

    /// NIP-10 reply tag for the wrap signal. When an inbound carries
    /// this tag we record the turn, mark the root ended, and bail
    /// without invoking the model. (Podcastr does not emit this tag
    /// today, but win-the-day does — supporting inbound parity keeps
    /// cross-app conversations terminable from either side.)
    private static let endConversationTagName = "wtd-end"

    /// Same JSON encoder used for transcript export across the service.
    /// Held as a static so each call doesn't pay the (small) decoder-
    /// initialisation cost.
    nonisolated private static let eventEncoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return enc
    }()

    private weak var store: AppStateStore?
    private let profileFetcher: NostrProfileFetcher

    init(store: AppStateStore) {
        self.store = store
        self.profileFetcher = NostrProfileFetcher(store: store)
    }

    /// Entry point used by `NostrRelayService`. Returns immediately to
    /// the relay loop; all heavy work runs as a detached `Task` so the
    /// receive loop keeps reading frames in parallel.
    func handle(inbound: Inbound) {
        Task { [weak self] in
            await self?.process(inbound)
        }
    }

    // MARK: - Pipeline

    private func process(_ inbound: Inbound) async {
        guard let store else { return }

        // Defence-in-depth anti-loop. The relay service already filters
        // self-authored events, but a future refactor over there
        // shouldn't be able to introduce reply loops here silently.
        if let selfHex = store.state.settings.nostrPublicKeyHex,
           inbound.pubkey == selfHex {
            return
        }

        // Persistent dedup — survives app restarts so a relay replay on
        // reconnect never produces a duplicate reply.
        if store.state.nostrRespondedEventIDs.contains(inbound.eventID) {
            Self.logger.debug("process: \(inbound.eventID.prefix(12), privacy: .public) already responded; skipping")
            return
        }

        // Bump the since-cursor before doing any model work so that a
        // crash partway through the reply still moves the cursor
        // forward. Dedup covers the tiny overlap (we may re-process
        // events with `created_at == cursor` once, but never reply
        // twice). Note: `sendSubscription` in NostrRelayService does
        // not currently pass `since` in the REQ filter, so this field
        // is bookkeeping-only until that wire-up lands. Spec parity
        // with win-the-day is the goal here.
        let current = store.state.nostrSinceCursor ?? 0
        store.state.nostrSinceCursor = max(current, inbound.createdAt)

        let rootID = NostrConversationRoot.rootEventID(
            eventID: inbound.eventID,
            tags: inbound.tags
        )

        // End-conversation gates. `nostrEndedRootIDs` is in-memory; the
        // persisted half is `nostrRespondedEventIDs`, which we stamp
        // below so stragglers landing after a restart still don't fire.
        if store.state.nostrEndedRootIDs.contains(rootID) {
            store.state.nostrRespondedEventIDs.insert(inbound.eventID)
            return
        }

        let isPeerEndSignal = inbound.tags.contains { tag in
            tag.first == Self.endConversationTagName
        }
        if isPeerEndSignal {
            Self.logger.notice("process: peer end signal on root \(rootID.prefix(12), privacy: .public); recording + closing")
            recordTurn(inbound: inbound, rootID: rootID)
            store.state.nostrEndedRootIDs.insert(rootID)
            store.state.nostrRespondedEventIDs.insert(inbound.eventID)
            return
        }

        // Per-root outgoing turn cap. Counts only outbound notes so a
        // long inbound back-and-forth doesn't trip the gate on the
        // peer's behalf.
        if let convo = store.state.nostrConversations.first(where: { $0.rootEventID == rootID }) {
            let outgoingCount = convo.turns.filter { $0.direction == .outgoing }.count
            if outgoingCount >= Self.maxOutgoingTurnsPerRoot {
                Self.logger.notice(
                    "process: suppressing inbound on root \(rootID.prefix(12), privacy: .public): outgoing turn cap (\(Self.maxOutgoingTurnsPerRoot)) reached"
                )
                store.state.nostrRespondedEventIDs.insert(inbound.eventID)
                store.state.nostrEndedRootIDs.insert(rootID)
                return
            }
        }

        // Resolve relay URL once. If it disappeared between the inbound
        // landing and us getting here, we have nothing to publish to —
        // record the incoming turn and bail.
        guard let relayURL = URL(string: store.state.settings.nostrRelayURL),
              !store.state.settings.nostrRelayURL.isEmpty else {
            Self.logger.error("process: no relay URL configured; recording inbound and bailing")
            recordTurn(inbound: inbound, rootID: rootID)
            return
        }

        // Pull the thread + the peer's kind:0 in parallel. Both are
        // bounded internally (thread fetcher has its own 4s timeout;
        // profile fetch is wrapped below at 2s).
        let priorEvents: [NostrThreadFetcher.Event]
        if rootID == inbound.eventID {
            priorEvents = []
        } else {
            priorEvents = await NostrThreadFetcher.fetch(rootID: rootID, relayURL: relayURL)
        }
        if store.state.nostrProfileCache[inbound.pubkey] == nil {
            await fetchProfileWithTimeout(pubkey: inbound.pubkey, seconds: 2.0)
        }

        let messages = buildMessages(
            inbound: inbound,
            priorEvents: priorEvents,
            store: store
        )
        let systemPrompt = NostrPeerAgentPrompt.systemPrompt(
            for: store,
            peerPubkey: inbound.pubkey
        )

        // Local-only signer for now; mirrors the convention used by
        // `publishAgentProfileIfPossible` in NostrRelayService. A
        // NIP-46 remote signer would require plumbing the user's
        // `UserIdentityStore.signer` — out of scope for the initial
        // peer-agent reply path.
        let privateKey: String?
        do {
            privateKey = try NostrCredentialStore.privateKey()
        } catch {
            Self.logger.error("process: keychain read failed — \(error, privacy: .public); cannot reply")
            recordTurn(inbound: inbound, rootID: rootID)
            return
        }
        guard let privKey = privateKey,
              let keyPair = try? NostrKeyPair(privateKeyHex: privKey) else {
            Self.logger.notice("process: no local private key; recording inbound, skipping reply")
            recordTurn(inbound: inbound, rootID: rootID)
            return
        }

        // Build the full chat-completions message array: system prompt
        // up front, followed by the conversation history.
        var fullMessages: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        fullMessages.append(contentsOf: messages)

        let model = store.state.settings.agentInitialModel
        let replyText: String
        do {
            let result = try await AgentLLMClient.streamCompletion(
                messages: fullMessages,
                tools: [],
                model: model,
                feature: CostFeature.agentNostr,
                onPartialContent: { _ in /* one-shot — no UI to feed */ }
            )
            replyText = (result.assistantMessage["content"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            Self.logger.error("process: LLM call failed — \(error, privacy: .public)")
            // Don't mark responded — a transient OpenRouter blip should
            // be re-tryable on the next relay redelivery.
            recordTurn(inbound: inbound, rootID: rootID)
            return
        }

        guard !replyText.isEmpty else {
            Self.logger.notice("process: model returned empty reply; recording inbound and skipping publish")
            recordTurn(inbound: inbound, rootID: rootID)
            store.state.nostrRespondedEventIDs.insert(inbound.eventID)
            return
        }

        // Build NIP-10 reply tags. Root resolution: when we couldn't
        // fetch the actual root event (the inbound IS the root, the
        // common case for the first reply in a fresh thread), fall back
        // to the inbound's tag set so any `a`-tags on the root are
        // still copied through. Matches win-the-day's
        // `priorEvents.first { $0.id == rootID } ?? event`.
        let rootTags: [[String]]
        if let root = priorEvents.first(where: { $0.id == rootID }) {
            rootTags = root.tags
        } else {
            rootTags = inbound.tags
        }
        let replyTags = buildReplyTags(
            rootID: rootID,
            rootTags: rootTags,
            inbound: inbound
        )

        let draft = NostrEventDraft(
            kind: 1,
            content: replyText,
            tags: replyTags
        )
        let signer = LocalKeySigner(keyPair: keyPair)
        let signed: SignedNostrEvent
        do {
            signed = try await signer.sign(draft)
        } catch {
            Self.logger.error("process: signing failed — \(error, privacy: .public)")
            recordTurn(inbound: inbound, rootID: rootID)
            return
        }

        do {
            try await NostrWebSocketEventPublisher().publish(event: signed, relayURL: relayURL)
        } catch {
            // The relay rejected or the socket dropped. Record the
            // inbound (we have its text) but leave the dedup set
            // untouched — next replay can retry.
            Self.logger.error("process: publish failed — \(error, privacy: .public)")
            recordTurn(inbound: inbound, rootID: rootID)
            return
        }

        // Both turns recorded, dedup stamped.
        recordTurn(inbound: inbound, rootID: rootID)
        recordOutgoing(signed: signed, rootID: rootID, counterparty: inbound.pubkey)
        store.state.nostrRespondedEventIDs.insert(inbound.eventID)
        Self.logger.notice(
            "process: replied to \(inbound.eventID.prefix(12), privacy: .public) on root \(rootID.prefix(12), privacy: .public) with event \(signed.id.prefix(12), privacy: .public)"
        )
    }

    // MARK: - Message + tag construction

    private func buildMessages(
        inbound: Inbound,
        priorEvents: [NostrThreadFetcher.Event],
        store: AppStateStore
    ) -> [[String: Any]] {
        let selfHex = store.state.settings.nostrPublicKeyHex ?? ""

        // Splice the new inbound into the prior events. Most relays
        // will include it via the e-tag filter, but a slow relay or a
        // strict NIP-10 implementation may not — append defensively.
        var combined = priorEvents
        if !combined.contains(where: { $0.id == inbound.eventID }) {
            combined.append(
                NostrThreadFetcher.Event(
                    id: inbound.eventID,
                    pubkey: inbound.pubkey,
                    createdAt: inbound.createdAt,
                    content: inbound.content,
                    tags: inbound.tags
                )
            )
        }
        // Dedup by id, sort ascending so the freshest event lands last.
        var seen: Set<String> = []
        let ordered = combined
            .sorted { $0.createdAt < $1.createdAt }
            .filter { seen.insert($0.id).inserted }

        return ordered.map { ev in
            if ev.pubkey == selfHex {
                return ["role": "assistant", "content": ev.content]
            }
            let sanitized = NostrPeerAgentPrompt.stripFromPrefix(ev.content)
            let label = NostrPeerAgentPrompt.peerLabel(for: ev.pubkey, in: store)
            let truncated = NostrPeerAgentPrompt.truncatedNpub(fromHex: ev.pubkey)
            return [
                "role": "user",
                "content": "[from \(label) (\(truncated))]: \(sanitized)"
            ]
        }
    }

    private func buildReplyTags(
        rootID: String,
        rootTags: [[String]],
        inbound: Inbound
    ) -> [[String]] {
        // Copy any `a` tags from the root event so addressable-event
        // anchored threads keep their channel identifier. Callers pass
        // either the fetched root's tags or the inbound's tags when the
        // inbound IS the root.
        var tags: [[String]] = []
        for tag in rootTags where tag.first == "a" {
            tags.append(tag)
        }
        tags.append(["e", rootID, "", "root"])
        if inbound.eventID != rootID {
            tags.append(["e", inbound.eventID, "", "reply"])
        }
        tags.append(["p", inbound.pubkey])
        return tags
    }

    // MARK: - Turn recording

    private func recordTurn(inbound: Inbound, rootID: String) {
        guard let store else { return }
        let turn = NostrConversationTurn(
            eventID: inbound.eventID,
            direction: .incoming,
            pubkey: inbound.pubkey,
            createdAt: Date(timeIntervalSince1970: TimeInterval(inbound.createdAt)),
            content: inbound.content,
            rawEventJSON: inbound.rawEventJSON
        )
        store.recordNostrTurn(rootEventID: rootID, turn: turn, counterpartyPubkey: inbound.pubkey)
    }

    private func recordOutgoing(
        signed: SignedNostrEvent,
        rootID: String,
        counterparty: String
    ) {
        guard let store else { return }
        let rawJSON = (try? Self.eventEncoder.encode(signed))
            .flatMap { String(data: $0, encoding: .utf8) }
        let turn = NostrConversationTurn(
            eventID: signed.id,
            direction: .outgoing,
            pubkey: signed.pubkey,
            createdAt: Date(timeIntervalSince1970: TimeInterval(signed.created_at)),
            content: signed.content,
            rawEventJSON: rawJSON
        )
        // Outgoing turn's `pubkey` is the agent's own pubkey — passing
        // `counterpartyPubkey: counterparty` is required when this is
        // the first turn that creates the conversation record, since
        // otherwise the agent would be filed as its own counterparty.
        store.recordNostrTurn(
            rootEventID: rootID,
            turn: turn,
            counterpartyPubkey: counterparty
        )
    }

    // MARK: - Profile fetch helper

    /// Race a kind:0 fetch against a hard timeout — whichever finishes
    /// first wins, the other is cancelled. The responder proceeds with
    /// whatever (possibly nil) cache state exists after the race.
    private func fetchProfileWithTimeout(pubkey: String, seconds: TimeInterval) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                await self?.profileFetcher.fetchProfiles(for: [pubkey])
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
            }
            await group.next()
            group.cancelAll()
        }
    }
}
