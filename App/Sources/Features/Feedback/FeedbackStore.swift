import Foundation
import SwiftUI

// MARK: - FeedbackStore

/// In-app feedback threads, reactively projected from the kernel snapshot.
///
/// The Rust kernel owns the relay connection (NMP relay pool, no iOS
/// WebSocket): `kernelFetchFeedback` opens a relay-pinned subscription to the
/// feedback relay and inbound events land on `podcastSnapshot.feedbackEvents`.
/// `threads` is a computed projection over that snapshot, merged with
/// local-only state the relay can't carry: optimistic just-posted threads,
/// attached screenshots, and client-side deletions.
@MainActor
@Observable
final class FeedbackStore {

    /// Injected by the view in `.task` before the first `load()`. Weak — the
    /// view owns the store, the app owns the AppStateStore. Reading it inside
    /// `threads` registers `@Observable` tracking through to
    /// `podcastSnapshot.feedbackEvents`, so a kernel push re-renders the list.
    weak var appStore: AppStateStore?

    /// `true` after `load()` dispatches a fetch and before the first snapshot
    /// frame carrying feedback events arrives.
    var isLoading: Bool = false
    var loadError: String?

    // MARK: Local-only overlay state (never sourced from the relay)

    /// Optimistically-posted threads, shown immediately while the publish
    /// propagates and the kernel re-fetches. Dropped once the relay echo for
    /// the same author+content arrives in the snapshot.
    private var pendingThreads: [FeedbackThread] = []
    /// Optimistically-posted replies, keyed by root thread id, shown
    /// immediately while the publish propagates. The fetch is `OneShot`, so a
    /// just-posted reply isn't in the snapshot until a later fetch — without
    /// this overlay the reply would vanish until pull-to-refresh. Dropped once
    /// the relay echo (same author + content under that root) arrives.
    private var pendingReplies: [String: [FeedbackReply]] = [:]
    /// Screenshots attached to optimistic threads, keyed by thread id.
    private var attachedImages: [String: UIImage] = [:]
    /// Thread ids the user dismissed locally (client-side hide).
    private var hiddenThreadIDs: Set<String> = []
    /// Last identity pubkey seen, so `threads` can resolve "is from me".
    private var localPubkey: String?

    // MARK: Projection

    /// Reactive feedback threads. Reading this in a SwiftUI body tracks the
    /// snapshot keypath, so the next kernel push re-renders.
    var threads: [FeedbackThread] {
        let events = (appStore?.kernel?.podcastSnapshot?.feedbackEvents ?? [])
            .map(\.asSignedEvent)
        let projected = buildThreads(from: events, localPubkey: localPubkey)
        // Drop optimistic threads whose relay echo has arrived (same author +
        // content), so "Mine" doesn't show a synthetic + real duplicate row.
        let echoed = Set(projected.map { ThreadDedupKey(thread: $0) })
        let surviving = pendingThreads.filter { !echoed.contains(ThreadDedupKey(thread: $0)) }
        return (surviving + projected)
            .filter { !hiddenThreadIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func load(identity: UserIdentityStore) async {
        localPubkey = identity.publicKeyHex
        loadError = nil
        // Fire-and-forget: the kernel opens the subscription; events arrive on
        // the snapshot. `isLoading` clears once any feedback event is present.
        guard let appStore else {
            loadError = "Feedback is unavailable."
            return
        }
        isLoading = (appStore.kernel?.podcastSnapshot?.feedbackEvents.isEmpty ?? true)
        appStore.kernelFetchFeedback()
        if !isLoading { return }
        // Brief grace so the spinner doesn't hang forever if the relay is empty
        // (no events at all is a valid steady state). This is a UI debounce, not
        // a data poll — `threads` updates reactively regardless.
        try? await Task.sleep(for: .seconds(3))
        isLoading = false
    }

    @discardableResult
    func publishThread(
        category: FeedbackCategory,
        content: String,
        image: UIImage?,
        identity: UserIdentityStore
    ) async throws -> FeedbackThread {
        // Self-heal: ensure a local key exists (and is forwarded to the kernel
        // signer) before dispatching, mirroring `publishUserNote`. A fresh user
        // with no identity gets a generated key here.
        if identity.signer == nil {
            try identity._ensureGeneratedKey()
        }
        localPubkey = identity.publicKeyHex
        // Sign + publish through the kernel (NMP signs, AUTHs, routes to the
        // feedback relay). Fire-and-forget — no returned signed event.
        appStore?.kernelPublishFeedback(category: category.tagValue, content: content.trimmed)
        // Synthesize an optimistic thread from the inputs (mirrors the prior
        // returned-event shape) so the UI reflects the post immediately.
        let thread = FeedbackThread(
            authorPubkey: identity.publicKeyHex ?? "",
            category: category,
            content: content.trimmed,
            attachedImage: image
        )
        pendingThreads.insert(thread, at: 0)
        if let image { attachedImages[thread.id] = image }
        return thread
    }

    func publishReply(content: String, threadID: String, identity: UserIdentityStore) async throws {
        if identity.signer == nil {
            try identity._ensureGeneratedKey()
        }
        localPubkey = identity.publicKeyHex
        guard let thread = threads.first(where: { $0.id == threadID }) else { return }
        let trimmed = content.trimmed
        let lastSpeaker = thread.replies.last?.authorPubkey ?? thread.authorPubkey
        let replyToPubkey = lastSpeaker == identity.publicKeyHex ? nil : lastSpeaker
        appStore?.kernelPublishFeedback(
            category: thread.category.tagValue,
            content: trimmed,
            parentEventID: thread.eventID,
            replyToPubkey: replyToPubkey
        )
        // Optimistically show the reply immediately (the OneShot fetch won't
        // return the just-posted event yet). Keyed by the root thread id.
        let optimistic = FeedbackReply(
            authorPubkey: identity.publicKeyHex ?? "",
            content: trimmed,
            isFromMe: true
        )
        pendingReplies[thread.eventID, default: []].append(optimistic)
    }

    /// Re-open the feedback subscription (pull-to-refresh / detail appear).
    /// Replies + metadata ride the same `["a"]`-anchored fetch as roots, so
    /// there is no separate replies subscription.
    func loadReplies(for thread: FeedbackThread, identity: UserIdentityStore) async {
        localPubkey = identity.publicKeyHex
        appStore?.kernelFetchFeedback()
    }

    func deleteThread(id: String) {
        hiddenThreadIDs.insert(id)
        pendingThreads.removeAll { $0.id == id }
        pendingReplies[id] = nil
        attachedImages[id] = nil
    }

    // MARK: Thread reconstruction (unchanged from the relay-client era)

    private func buildThreads(from events: [SignedNostrEvent], localPubkey: String?) -> [FeedbackThread] {
        let metas = events.filter { $0.kind == FeedbackRelayClient.metadataKind }
        let messages = events.filter { $0.kind == FeedbackRelayClient.textNoteKind }

        var metaByRoot: [String: FeedbackMetadata] = [:]
        for event in metas {
            guard let rootID = event.rootEventID else { continue }
            let parsed = FeedbackMetadata(event: event)
            if let existing = metaByRoot[rootID], existing.createdAt >= parsed.createdAt { continue }
            metaByRoot[rootID] = parsed
        }

        let replies = Dictionary(grouping: messages.filter { $0.rootEventID != nil }) {
            $0.rootEventID ?? ""
        }

        return messages
            .filter { $0.rootEventID == nil && $0.projectATags.contains(FeedbackRelayClient.projectCoordinate) }
            .sorted { $0.created_at > $1.created_at }
            .map { root in
                var thread = FeedbackThread(
                    event: root,
                    replies: (replies[root.id] ?? []).sorted { $0.created_at < $1.created_at },
                    metadata: metaByRoot[root.id],
                    attachedImage: attachedImages[root.id],
                    localPubkey: localPubkey
                )
                // Merge optimistic replies, dropping any whose relay echo (same
                // author + content under this root) has already arrived.
                let echoed = Set(thread.replies.map { ReplyDedupKey(reply: $0) })
                let surviving = (pendingReplies[root.id] ?? [])
                    .filter { !echoed.contains(ReplyDedupKey(reply: $0)) }
                if !surviving.isEmpty {
                    thread.replies = (thread.replies + surviving)
                        .sorted { $0.createdAt < $1.createdAt }
                }
                return thread
            }
    }
}

// MARK: - Optimistic-vs-echo dedup

/// Identity used to drop an optimistic thread once its relay echo arrives.
/// Keyed by author + content so the synthetic `local-<uuid>` row and the real
/// event (with its own id) collapse to one under the "Mine" filter.
private struct ThreadDedupKey: Hashable {
    let authorPubkey: String
    let content: String
    init(thread: FeedbackThread) {
        authorPubkey = thread.authorPubkey
        content = thread.content
    }
}

/// Identity used to drop an optimistic reply once its relay echo arrives.
private struct ReplyDedupKey: Hashable {
    let authorPubkey: String
    let content: String
    init(reply: FeedbackReply) {
        authorPubkey = reply.authorPubkey
        content = reply.content
    }
}

// MARK: - FeedbackRelayClient (publish + profile fetch)
//
// The FEEDBACK relay-fetch path moved to the Rust kernel (NMP relay pool — see
// `feedback_handler.rs` + `FeedbackStore` above); no iOS WebSocket is opened
// for feedback. The feedback-specific `fetchProjectEvents` / `fetchReplies`
// were deleted. What remains is still used by NON-feedback consumers that have
// not yet moved to the kernel:
//   * `publish()` + `profileRelayURLs` — `UserIdentityStore.publishProfile` /
//     generated-profile auto-publish (kind:0); the `.remoteSigner` (bunker)
//     note/clip fallbacks; `LivePeerEventPublisher`'s default project a-tag.
//   * `fetchKind0()` + the generic `fetch()` REQ path —
//     `UserIdentityStore.fetchAndCacheProfile` (kind:0 profile fetch).
// `projectCoordinate` / `metadataKind` / `textNoteKind` are also read by
// `FeedbackStore.buildThreads` (above). Removing the remaining WebSocket here
// is a separate migration (profile + bunker signing kernel seams).

actor FeedbackRelayClient {
    static let textNoteKind = 1
    static let metadataKind = 513
    static let feedbackRelayURL = URL(string: "wss://relay.tenex.chat")!
    static let profileRelayURLs = [
        URL(string: "wss://relay.tenex.chat")!,
        URL(string: "wss://purplepag.es")!,
    ]
    static let projectCoordinate =
        "31933:09d48a1a5dbe13404a729634f1d6ba722d40513468dd713c8ea38ca9b7b6f2c7:podcast"

    private let relayURL: URL

    init(relayURL: URL = FeedbackRelayClient.feedbackRelayURL) {
        self.relayURL = relayURL
    }

    /// Fetch the most-recent kind:0 metadata event for `pubkeyHex`. Used by
    /// `UserIdentityStore.fetchAndCacheProfile` (profile fetch — a separate
    /// concern from feedback, not yet migrated to the kernel).
    func fetchKind0(pubkeyHex: String) async throws -> [SignedNostrEvent] {
        try await fetch(filter: [
            "kinds": [0],
            "authors": [pubkeyHex],
            "limit": 1,
        ])
    }

    private func fetch(filter: [String: Any], signer: (any NostrSigner)? = nil) async throws -> [SignedNostrEvent] {
        let task = URLSession.shared.webSocketTask(with: relayURL)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        let subscriptionID = "feedback-\(UUID().uuidString)"
        try await send(["REQ", subscriptionID, filter], task: task)

        var events: [SignedNostrEvent] = []
        var authenticated = false
        var reqResentAfterAuth = false
        while let text = try await receiveText(task: task, timeoutSeconds: 8) {
            guard let message = Self.parseMessage(text) else { continue }
            switch message {
            case .event(let subID, let event):
                guard subID == subscriptionID else { continue }
                events.append(event)
            case .eose(let subID):
                guard subID == subscriptionID else { continue }
                return events
            case .closed(let subID, let reason):
                guard subID == subscriptionID else { continue }
                if reason?.hasPrefix("auth-required:") == true, authenticated, !reqResentAfterAuth {
                    reqResentAfterAuth = true
                    try await send(["REQ", subscriptionID, filter], task: task)
                } else {
                    return events
                }
            case .auth(let challenge):
                guard let signer else { continue }
                let authEvent = try await signer.sign(NostrEventDraft(
                    kind: 22242,
                    content: "",
                    tags: [["relay", relayURL.absoluteString], ["challenge", challenge]]
                ))
                try await send(["AUTH", eventDictionary(authEvent)], task: task)
                authenticated = true
            case .notice(let message):
                throw FeedbackRelayError.rejected(message)
            case .ok:
                continue
            }
        }
        return events
    }

    func publish(_ event: SignedNostrEvent, authSigner: (any NostrSigner)?) async throws {
        let task = URLSession.shared.webSocketTask(with: relayURL)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        try await sendEvent(event, task: task)

        var authEventID: String?
        var retriedAfterAuth = false
        while let text = try await receiveText(task: task, timeoutSeconds: 8) {
            guard let message = Self.parseMessage(text) else { continue }
            switch message {
            case .ok(let eventID, let accepted, let reason):
                if eventID == event.id {
                    if accepted { return }
                    if reason?.hasPrefix("auth-required:") == true, authSigner != nil { continue }
                    throw FeedbackRelayError.rejected(reason ?? "Relay rejected feedback.")
                }
                if eventID == authEventID, accepted, !retriedAfterAuth {
                    retriedAfterAuth = true
                    try await sendEvent(event, task: task)
                } else if eventID == authEventID, !accepted {
                    throw FeedbackRelayError.rejected(reason ?? "Relay rejected authentication.")
                }
            case .auth(let challenge):
                guard let authSigner else { throw FeedbackRelayError.authRequired }
                let auth = try await authSigner.sign(NostrEventDraft(
                    kind: 22242,
                    content: "",
                    tags: [["relay", relayURL.absoluteString], ["challenge", challenge]]
                ))
                authEventID = auth.id
                try await send(["AUTH", eventDictionary(auth)], task: task)
            case .notice(let message):
                throw FeedbackRelayError.rejected(message)
            case .event, .eose, .closed:
                continue
            }
        }
        throw FeedbackRelayError.timeout
    }

    private func sendEvent(_ event: SignedNostrEvent, task: URLSessionWebSocketTask) async throws {
        try await send(["EVENT", eventDictionary(event)], task: task)
    }

    private func send(_ message: [Any], task: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw FeedbackRelayError.encodingFailed
        }
        try await task.send(.string(text))
    }

    private func receiveText(task: URLSessionWebSocketTask, timeoutSeconds: Double) async throws -> String? {
        try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                let message = try await task.receive()
                if case .string(let text) = message { return text }
                return nil
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return nil
            }
            let result = try await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private func eventDictionary(_ event: SignedNostrEvent) -> [String: Any] {
        [
            "id": event.id,
            "pubkey": event.pubkey,
            "created_at": event.created_at,
            "kind": event.kind,
            "tags": event.tags,
            "content": event.content,
            "sig": event.sig,
        ]
    }

    private static func parseMessage(_ text: String) -> RelayMessage? {
        guard let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let head = array.first as? String else { return nil }
        switch head {
        case "EVENT":
            guard array.count >= 3,
                  let subID = array[1] as? String,
                  let event = decodeEvent(array[2]) else { return nil }
            return .event(subID, event)
        case "EOSE":
            guard array.count >= 2, let subID = array[1] as? String else { return nil }
            return .eose(subID)
        case "OK":
            guard array.count >= 3,
                  let eventID = array[1] as? String,
                  let accepted = array[2] as? Bool else { return nil }
            return .ok(eventID, accepted, array.count >= 4 ? array[3] as? String : nil)
        case "AUTH":
            guard array.count >= 2, let challenge = array[1] as? String else { return nil }
            return .auth(challenge)
        case "NOTICE":
            return .notice(array.count >= 2 ? (array[1] as? String ?? "Relay notice.") : "Relay notice.")
        case "CLOSED":
            guard array.count >= 2, let subID = array[1] as? String else { return nil }
            return .closed(subID, array.count >= 3 ? array[2] as? String : nil)
        default:
            return nil
        }
    }

    private static func decodeEvent(_ value: Any) -> SignedNostrEvent? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? Self.eventDecoder.decode(SignedNostrEvent.self, from: data)
    }

    /// Shared. `decodeEvent` runs for every Nostr event the relay streams, so
    /// a busy session reallocated a `JSONDecoder` per event.
    private static let eventDecoder = JSONDecoder()

    private enum RelayMessage {
        case event(String, SignedNostrEvent)
        case eose(String)
        case ok(String, Bool, String?)
        case auth(String)
        case notice(String)
        case closed(String, String?)
    }
}

enum FeedbackRelayError: LocalizedError {
    case authRequired
    case encodingFailed
    case rejected(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .authRequired:
            "Relay requires authentication, but no signer is available."
        case .encodingFailed:
            "Could not encode the feedback event."
        case .rejected(let message):
            message
        case .timeout:
            "Feedback relay did not respond in time."
        }
    }
}
