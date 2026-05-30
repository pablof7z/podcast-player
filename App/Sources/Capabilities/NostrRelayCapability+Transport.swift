import Foundation

// MARK: - Nostr relay WebSocket transport
//
// The blocking, fan-out WebSocket logic for `NostrRelayCapability`. Each relay
// gets its own `URLSessionWebSocketTask`; we fan out concurrently and wait on a
// `DispatchGroup`. All `URLSessionWebSocketTask` calls use the
// completion-handler forms so they land on the session's private background
// `OperationQueue` — never the calling (kernel actor) thread — which is what
// makes the synchronous `group.wait()` safe (see file-level note in
// `NostrRelayCapability.swift`).
//
// Protocol frames (NIP-01):
//   Publish:   send `["EVENT", <event>]`, wait for `["OK", id, true/false, msg]`.
//   Subscribe: send `["REQ", sub_id, filter]`, collect `["EVENT", sub_id, ev]`
//              until `["EOSE", sub_id]` or timeout, then send `["CLOSE", sub_id]`.

extension NostrRelayCapability {
    // MARK: Publish

    /// Publish a pre-signed event to every relay concurrently. `ok` is true iff
    /// at least one relay returned `["OK", …, true, …]`; per-relay rejections
    /// and transport failures land in `errors`.
    func publish(eventJSON: String, relayURLs: [String]) -> NostrRelayResult {
        // Mirror the headless executor: a malformed event is reported as a
        // per-relay error for every target, not a top-level error.
        guard
            let eventData = eventJSON.data(using: .utf8),
            let eventValue = try? JSONSerialization.jsonObject(with: eventData),
            let frameData = try? JSONSerialization.data(withJSONObject: ["EVENT", eventValue]),
            let frame = String(data: frameData, encoding: .utf8)
        else {
            let errors = relayURLs.map { ($0, "invalid event_json") }
            return .published(ok: false, acceptedRelays: [], errors: errors)
        }

        let box = OutcomeBox()
        let group = DispatchGroup()
        for relayURL in relayURLs {
            group.enter()
            publishToRelay(relayURL: relayURL, frame: frame) { result in
                switch result {
                case .success:
                    box.accept(relayURL)
                case let .failure(message):
                    box.reject(relayURL, message)
                }
                group.leave()
            }
        }
        // Backstop above the per-relay timeout so a stuck completion can't
        // wedge the actor thread forever.
        _ = group.wait(timeout: .now() + publishTimeout + 5)

        let (accepted, errors) = box.snapshot()
        return .published(ok: !accepted.isEmpty, acceptedRelays: accepted, errors: errors)
    }

    /// Open one relay, send the EVENT frame, and resolve on the first `OK`
    /// reply (or timeout/transport error). Calls `completion` exactly once.
    private func publishToRelay(
        relayURL: String,
        frame: String,
        completion: @escaping (PublishOutcome) -> Void
    ) {
        guard let url = URL(string: relayURL), url.scheme == "ws" || url.scheme == "wss" else {
            completion(.failure("invalid relay url"))
            return
        }

        let task = session.webSocketTask(with: url)
        let once = OnceCompletion<PublishOutcome>(completion)
        task.resume()

        // Per-relay timeout backstop.
        let deadline = DispatchWorkItem {
            once.fire(.failure("timeout waiting for OK")) { task.cancel(with: .goingAway, reason: nil) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + publishTimeout, execute: deadline)

        task.send(.string(frame)) { sendError in
            if let sendError {
                deadline.cancel()
                once.fire(.failure("send error: \(sendError.localizedDescription)")) {
                    task.cancel(with: .goingAway, reason: nil)
                }
                return
            }
            // Read until we see an OK frame (relays may emit NOTICE/AUTH first).
            self.awaitOK(task: task, deadline: deadline, once: once)
        }
    }

    /// Recursively read frames until an `["OK", …]` arrives, then resolve.
    private func awaitOK(
        task: URLSessionWebSocketTask,
        deadline: DispatchWorkItem,
        once: OnceCompletion<PublishOutcome>
    ) {
        task.receive { [weak self] result in
            switch result {
            case let .success(message):
                guard let array = Self.decodeFrame(message) else {
                    // Non-array / binary frame — keep reading.
                    self?.awaitOK(task: task, deadline: deadline, once: once)
                    return
                }
                if (array.first as? String) == "OK" {
                    deadline.cancel()
                    let ok = (array.count > 2 ? array[2] as? Bool : nil) ?? false
                    let msg = (array.count > 3 ? array[3] as? String : nil) ?? ""
                    let outcome: PublishOutcome = ok ? .success : .failure("rejected: \(msg)")
                    once.fire(outcome) { task.cancel(with: .normalClosure, reason: nil) }
                } else {
                    // NOTICE / AUTH / other — keep reading for our OK.
                    self?.awaitOK(task: task, deadline: deadline, once: once)
                }
            case let .failure(error):
                deadline.cancel()
                once.fire(.failure("ws error: \(error.localizedDescription)")) {
                    task.cancel(with: .goingAway, reason: nil)
                }
            }
        }
    }

    // MARK: Subscribe

    /// Subscribe to `filter` on every relay concurrently, collect events until
    /// EOSE/timeout, dedupe by event `id`. `eose` is best-effort `true` — we
    /// always return after EOSE or the timeout elapses (matches headless).
    func subscribe(
        subID: String,
        filter: [String: Any],
        relayURLs: [String],
        timeout: TimeInterval
    ) -> NostrRelayResult {
        guard
            let frameData = try? JSONSerialization.data(withJSONObject: ["REQ", subID, filter]),
            let frame = String(data: frameData, encoding: .utf8)
        else {
            return .error(message: "invalid filter")
        }

        let box = EventBox()
        let group = DispatchGroup()
        for relayURL in relayURLs {
            group.enter()
            subscribeToRelay(relayURL: relayURL, frame: frame, subID: subID, timeout: timeout, box: box) {
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + timeout + 5)

        return .events(events: box.deduped(), eose: true)
    }

    /// Open one relay, send the REQ frame, collect EVENT frames until EOSE or
    /// timeout, then CLOSE. Calls `done` exactly once.
    private func subscribeToRelay(
        relayURL: String,
        frame: String,
        subID: String,
        timeout: TimeInterval,
        box: EventBox,
        done: @escaping () -> Void
    ) {
        guard let url = URL(string: relayURL), url.scheme == "ws" || url.scheme == "wss" else {
            done()
            return
        }

        let task = session.webSocketTask(with: url)
        let once = OnceCompletion<Void> { _ in done() }
        task.resume()

        let deadline = DispatchWorkItem {
            once.fire(()) {
                let close = (try? JSONSerialization.data(withJSONObject: ["CLOSE", subID]))
                    .flatMap { String(data: $0, encoding: .utf8) }
                if let close { task.send(.string(close)) { _ in } }
                task.cancel(with: .goingAway, reason: nil)
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)

        task.send(.string(frame)) { sendError in
            if sendError != nil {
                deadline.cancel()
                once.fire(()) { task.cancel(with: .goingAway, reason: nil) }
                return
            }
            self.collectEvents(task: task, subID: subID, deadline: deadline, once: once, box: box)
        }
    }

    /// Recursively read frames, appending EVENT payloads to `box`, until EOSE.
    private func collectEvents(
        task: URLSessionWebSocketTask,
        subID: String,
        deadline: DispatchWorkItem,
        once: OnceCompletion<Void>,
        box: EventBox
    ) {
        task.receive { [weak self] result in
            switch result {
            case let .success(message):
                guard let array = Self.decodeFrame(message) else {
                    self?.collectEvents(task: task, subID: subID, deadline: deadline, once: once, box: box)
                    return
                }
                let tag = array.first as? String
                let frameSubID = array.count > 1 ? array[1] as? String : nil
                if tag == "EVENT", frameSubID == subID, array.count > 2 {
                    box.add(array[2])
                    self?.collectEvents(task: task, subID: subID, deadline: deadline, once: once, box: box)
                } else if tag == "EOSE", frameSubID == subID {
                    deadline.cancel()
                    once.fire(()) {
                        let close = (try? JSONSerialization.data(withJSONObject: ["CLOSE", subID]))
                            .flatMap { String(data: $0, encoding: .utf8) }
                        if let close { task.send(.string(close)) { _ in } }
                        task.cancel(with: .normalClosure, reason: nil)
                    }
                } else {
                    self?.collectEvents(task: task, subID: subID, deadline: deadline, once: once, box: box)
                }
            case .failure:
                deadline.cancel()
                once.fire(()) { task.cancel(with: .goingAway, reason: nil) }
            }
        }
    }

    // MARK: Frame decoding

    /// Decode a received WebSocket message into a top-level JSON array, or
    /// `nil` for binary / non-array / unparseable frames.
    static func decodeFrame(_ message: URLSessionWebSocketTask.Message) -> [Any]? {
        let data: Data?
        switch message {
        case let .string(text): data = text.data(using: .utf8)
        case let .data(raw): data = raw
        @unknown default: data = nil
        }
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [Any]
    }
}

// MARK: - Thread-safe accumulators

/// Collects per-relay publish outcomes across the session's background queue.
final class OutcomeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var accepted: [String] = []
    private var errors: [(String, String)] = []

    func accept(_ relayURL: String) {
        lock.lock(); accepted.append(relayURL); lock.unlock()
    }

    func reject(_ relayURL: String, _ message: String) {
        lock.lock(); errors.append((relayURL, message)); lock.unlock()
    }

    func snapshot() -> ([String], [(String, String)]) {
        lock.lock(); defer { lock.unlock() }
        return (accepted, errors)
    }
}

/// Collects subscription events across relays and dedupes by event `id`.
final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [Any] = []
    private var seen = Set<String>()

    func add(_ event: Any) {
        lock.lock(); defer { lock.unlock() }
        let id = (event as? [String: Any])?["id"] as? String ?? ""
        // Empty-id events (malformed) are kept once via the empty-string slot,
        // matching the headless dedupe-by-id behaviour.
        if seen.insert(id).inserted {
            events.append(event)
        }
    }

    func deduped() -> [Any] {
        lock.lock(); defer { lock.unlock() }
        return events
    }
}

/// Guarantees a completion fires at most once across racing timeout / receive /
/// send paths, running an optional teardown block under the same gate.
final class OnceCompletion<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private let body: (T) -> Void

    init(_ body: @escaping (T) -> Void) {
        self.body = body
    }

    /// Fire once. `teardown` (socket cancel / CLOSE) runs only for the winning
    /// caller, so we never double-cancel.
    func fire(_ value: T, teardown: () -> Void) {
        lock.lock()
        if fired { lock.unlock(); return }
        fired = true
        lock.unlock()
        teardown()
        body(value)
    }
}
