import Foundation

// MARK: - Nostr relay capability
//
// iOS half of the kernel-side Nostr relay capability (namespace
// `nostr_relay`). The Rust contract lives in
// `apps/nmp-app-podcast/src/capability/nostr_relay.rs`; the canonical async
// executor is the headless one in
// `apps/nmp-app-podcast/src/bin/headless/relay_client.rs`. This file is the
// iOS executor — before it existed, every `dispatch_nostr_relay` call from
// the kernel returned an `unknown-namespace` envelope, so NIP-F4 publishes
// (and Nostr-backed reads: comments, discovery) never reached the network.
//
// The kernel never opens a relay WebSocket directly; it routes the request
// through the capability socket so the platform supplies the transport. This
// is the `URLSessionWebSocketTask` implementation, mirroring `HttpCapability`.
//
// Doctrine (docs/product-spec/doctrine.md):
//   D6 — errors never cross the boundary as exceptions. A connect/TLS/timeout
//        failure, malformed request, or the capability being stopped all
//        return a populated `NostrRelayResult` inside the envelope; this type
//        never `throw`s across `handle(_:)` / `handleJSON(_:)`.
//   D7 — a capability reports and executes; it never decides policy. It opens
//        the exact relays the kernel names, sends the exact pre-signed event,
//        and reports which relays accepted. *Which* event to sign and *which*
//        relays to target are kernel (NIP-F4 / NIP-01) decisions.
//
// SYNCHRONOUS SOCKET — the capability socket
// (`crates/nmp-core/src/capability_socket.rs`) is synchronous: Rust calls the
// native callback and blocks the actor thread until it returns. So this
// implementation must block too. It drives `URLSessionWebSocketTask` and waits
// on a `DispatchGroup`/`DispatchSemaphore`. The wait is safe because Rust
// invokes this callback from the actor thread (never the main thread) and the
// WebSocket completion handlers run on the session's private background
// `OperationQueue`, not the calling thread — so the wait can never deadlock
// against its own completions. This matches `HttpCapability`'s rationale.
//
// WIRE FIDELITY — the Rust `NostrRelayResult` enum has no `skip_serializing_if`
// and no `#[serde(default)]` on its fields, so `serde_json::from_str` on the
// kernel side FAILS to decode a `Published` result that is missing
// `accepted_relays` or `errors`. We therefore ALWAYS emit all three fields
// (`ok`, `accepted_relays`, `errors`) even when empty — we deliberately do NOT
// copy `HttpResult`'s "omit empty headers" optimization. `errors` is a
// `Vec<(String, String)>` on the Rust side, which serialises as an array of
// 2-element arrays.

// MARK: - Request vocabulary (decoded `payload_json`)

/// Capability-private request payload. Mirrors the Rust `NostrRelayRequest`
/// (`#[serde(tag = "type")]`, no `rename_all` — so the tag values are the
/// PascalCase variant names `"Publish"` / `"Subscribe"`).
///
/// `Subscribe.filter` is a `serde_json::Value` on the Rust side — an arbitrary
/// NIP-01 filter object. We keep it as a raw `[String: Any]` (decoded via
/// `JSONSerialization`) and forward it verbatim into the `["REQ", …]` frame
/// rather than modelling its keys with `Codable`.
enum NostrRelayRequest {
    case publish(eventJSON: String, relayURLs: [String])
    case subscribe(subID: String, filter: [String: Any], relayURLs: [String], timeoutMs: UInt64)
}

// MARK: - Result vocabulary (encoded `result_json`)

/// Capability-private result payload. Mirrors the Rust `NostrRelayResult`
/// (`#[serde(tag = "type")]`, PascalCase tags `"Published"` / `"Events"` /
/// `"Error"`).
enum NostrRelayResult {
    /// Outcome of a `publish`. `ok` is true iff at least one relay accepted.
    case published(ok: Bool, acceptedRelays: [String], errors: [(String, String)])
    /// Events collected from a `subscribe`, plus whether EOSE was seen.
    case events(events: [Any], eose: Bool)
    /// Top-level transport / parse error.
    case error(message: String)

    /// Serialise to the exact JSON shape the kernel's `serde_json::from_str`
    /// expects. Built with `JSONSerialization` because `Events.events` carries
    /// arbitrary relay-supplied JSON objects.
    func jsonString() -> String {
        let object: [String: Any]
        switch self {
        case let .published(ok, acceptedRelays, errors):
            object = [
                "type": "Published",
                "ok": ok,
                "accepted_relays": acceptedRelays,
                // Vec<(String, String)> ⇒ array of 2-element arrays.
                "errors": errors.map { [$0.0, $0.1] },
            ]
        case let .events(events, eose):
            object = [
                "type": "Events",
                "events": events,
                "eose": eose,
            ]
        case let .error(message):
            object = [
                "type": "Error",
                "message": message,
            ]
        }
        guard
            let data = try? JSONSerialization.data(withJSONObject: object),
            let string = String(data: data, encoding: .utf8)
        else {
            // Last-resort error literal — still a valid `NostrRelayResult`.
            return "{\"type\":\"Error\",\"message\":\"result-encode-failed\"}"
        }
        return string
    }
}

// MARK: - URLSessionWebSocketTask-backed capability

/// `URLSessionWebSocketTask` implementation of the Nostr relay capability.
///
/// Publishes a pre-signed event to every named relay concurrently and reports
/// which accepted it; or subscribes and collects events until EOSE/timeout.
/// The call blocks the calling (actor) thread until the relay round-trips
/// complete — see the synchronous-socket note at the top of this file.
final class NostrRelayCapability {
    static let namespace = "nostr_relay"

    /// Resolution of a single relay publish attempt (used by the transport
    /// extension's one-shot completion gate).
    enum PublishOutcome {
        case success
        case failure(String)
    }

    /// Fixed wall-clock ceiling for a `publish` round-trip per relay. Matches
    /// the headless executor's `Duration::from_secs(15)` — `Publish` carries no
    /// `timeout_ms` on the wire. (`Subscribe` carries its own `timeout_ms`.)
    ///
    /// Not `private`: the transport logic lives in
    /// `NostrRelayCapability+Transport.swift`, and a cross-file extension can't
    /// reach `private` members.
    let publishTimeout: TimeInterval

    /// Dedicated session so WebSocket completions run on a private background
    /// `OperationQueue` (never the main queue) — the blocking waits below can
    /// therefore never deadlock against a completion handler. Not `private` for
    /// the same cross-file-extension reason as `publishTimeout`.
    let session: URLSession

    private var started = false

    init(publishTimeout: TimeInterval = 15) {
        self.publishTimeout = publishTimeout
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        let queue = OperationQueue()
        queue.name = "io.f7z.podcast.NostrRelayCapability"
        self.session = URLSession(configuration: config, delegate: nil, delegateQueue: queue)
    }

    // MARK: Lifecycle (idempotent)

    /// Idempotent. Marks the capability active so requests are served.
    func start() {
        started = true
    }

    /// Idempotent. Marks the handler inactive so late requests are reported as
    /// data (`NostrRelayResult.error`), not crashes. Does not cancel in-flight
    /// sockets.
    func stop() {
        started = false
    }

    var isStarted: Bool { started }

    // MARK: Envelope handling (never throws — D6)

    /// Decode → execute → encode. Any failure (malformed request, capability
    /// stopped, transport error) is returned inside the envelope's
    /// `result_json`, never raised.
    func handle(_ request: CapabilityRequest) -> CapabilityEnvelope {
        let result = process(request)
        return CapabilityEnvelope(
            namespace: Self.namespace,
            correlationID: request.correlationID,
            resultJSON: result.jsonString())
    }

    /// Convenience entry point for FFI bridges that hand us the raw kernel
    /// `CapabilityRequest` JSON and want raw `CapabilityEnvelope` JSON back.
    /// Honors D6 end to end: malformed input yields an error envelope string.
    func handleJSON(_ requestJSON: String) -> String {
        guard
            let data = requestJSON.data(using: .utf8),
            let request = try? JSONDecoder().decode(CapabilityRequest.self, from: data)
        else {
            let env = CapabilityEnvelope(
                namespace: Self.namespace,
                correlationID: "",
                resultJSON: NostrRelayResult.error(message: "malformed-request").jsonString())
            return Self.encode(env) ?? "{}"
        }
        return Self.encode(handle(request)) ?? "{}"
    }

    // MARK: - Internals

    private func process(_ request: CapabilityRequest) -> NostrRelayResult {
        guard started else { return .error(message: "capability-stopped") }
        guard let parsed = Self.parseRequest(request.payloadJSON) else {
            return .error(message: "malformed-payload")
        }
        switch parsed {
        case let .publish(eventJSON, relayURLs):
            return publish(eventJSON: eventJSON, relayURLs: relayURLs)
        case let .subscribe(subID, filter, relayURLs, timeoutMs):
            return subscribe(
                subID: subID,
                filter: filter,
                relayURLs: relayURLs,
                timeout: TimeInterval(timeoutMs) / 1000.0)
        }
    }

    /// Decode the `payload_json` into a `NostrRelayRequest`. Uses
    /// `JSONSerialization` so the `Subscribe.filter` arbitrary object survives
    /// verbatim. Returns `nil` for any structural mismatch (→ `malformed-payload`).
    static func parseRequest(_ payloadJSON: String) -> NostrRelayRequest? {
        guard
            let data = payloadJSON.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String
        else {
            return nil
        }

        switch type {
        case "Publish":
            guard
                let eventJSON = object["event_json"] as? String,
                let relayURLs = object["relay_urls"] as? [String]
            else {
                return nil
            }
            return .publish(eventJSON: eventJSON, relayURLs: relayURLs)
        case "Subscribe":
            guard
                let subID = object["sub_id"] as? String,
                let filter = object["filter"] as? [String: Any],
                let relayURLs = object["relay_urls"] as? [String],
                let timeoutMs = object["timeout_ms"] as? NSNumber
            else {
                return nil
            }
            return .subscribe(
                subID: subID,
                filter: filter,
                relayURLs: relayURLs,
                timeoutMs: timeoutMs.uint64Value)
        default:
            return nil
        }
    }

    private static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
