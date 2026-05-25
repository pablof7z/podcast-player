import Foundation

/// Capability injection point for Podcast.
///
/// The kernel grants the app a set of capability *sockets*; the app supplies
/// the platform implementation. This holder is the one place those
/// implementations are constructed and started, mirroring the thin-bridge
/// pattern in `Bridge/KernelBridge.swift`.
///
/// It owns:
///   - `KeychainCapability`    — generic NMP keyring (`nmp.keyring.capability`)
///   - `PcstIdentityCapability` — podcast-app identity/BYOK slots (`pcst.identity.capability`)
///   - `HttpCapability`        — host HTTP transport
///   - `LegacyIOCapability`    — one-shot legacy-data reader (`pcst.legacy_io.capability`).
///                                Used only on first launch to migrate data
///                                from the pre-NMP Swift app; idle thereafter.
///                                iOS-only — Android/web targets stub this out.
///   - `AudioCapability`       — AVPlayer-backed audio (`nmp.audio.capability`)
///   - `DownloadCapability`    — URLSession background downloads
///                                (`nmp.download.capability`)
///
/// Rust decides when and what to call; Swift only executes the request and
/// reports the raw result (D7).
///
/// There is a single C capability callback (`nmp_app_set_capability_callback`);
/// it routes by the `namespace` field of the incoming `CapabilityRequest` —
/// see [`handleJSON(_:)`].
@MainActor
final class PodcastCapabilities {
    /// Process-wide instance.
    ///
    /// Background `URLSession` delegate events can arrive before SwiftUI's
    /// `@State` initialisers run (notably when the OS relaunches the app
    /// into the background to drain an in-flight download), so the
    /// capability holder must be reachable from the
    /// `UIApplicationDelegate` hook regardless of view-graph state. The
    /// `PodcastAppDelegate` forwards
    /// `application(_:handleEventsForBackgroundURLSession:completionHandler:)`
    /// into `shared.download.handleEventsForBackgroundURLSession(...)`.
    ///
    /// This is the same "singleton holder" pattern the legacy
    /// `EpisodeDownloadService.shared` used; the iOS-side capability
    /// surface owns the OS hook regardless of where the kernel wires it.
    static let shared = PodcastCapabilities()

    let keyring: KeychainCapability
    let identity: PcstIdentityCapability
    let http: HttpCapability
    let legacyIO: LegacyIOCapability
    let audio: AudioCapability
    let download: DownloadCapability

    init(
        keyring: KeychainCapability = KeychainCapability(),
        identity: PcstIdentityCapability = PcstIdentityCapability(),
        http: HttpCapability = HttpCapability(),
        legacyIO: LegacyIOCapability = LegacyIOCapability(),
        audio: AudioCapability = AudioCapability(),
        download: DownloadCapability = DownloadCapability()
    ) {
        self.keyring = keyring
        self.identity = identity
        self.http = http
        self.legacyIO = legacyIO
        self.audio = audio
        self.download = download
    }

    /// Idempotent: start all owned capabilities. Safe to call on every app
    /// foreground.
    func start() {
        keyring.start()
        identity.start()
        http.start()
        legacyIO.start()
        audio.start()
        download.start()
    }

    /// Idempotent: mark capabilities inactive. Does not erase stored secrets.
    func stop() {
        keyring.stop()
        identity.stop()
        http.stop()
        legacyIO.stop()
        audio.stop()
        download.stop()
    }

    /// Single capability-callback entry point. Routes the raw kernel
    /// `CapabilityRequest` JSON to the capability owning its `namespace` and
    /// returns the raw `CapabilityEnvelope` JSON.
    ///
    /// D6: an unparseable request or an unknown namespace yields a populated
    /// error envelope string, never a thrown error and never `nil`.
    func handleJSON(_ requestJSON: String) -> String {
        guard
            let data = requestJSON.data(using: .utf8),
            let request = try? JSONDecoder().decode(CapabilityRequest.self, from: data)
        else {
            // Cannot even read the namespace — return a generic error envelope.
            let env = CapabilityEnvelope(
                namespace: "",
                correlationID: "",
                resultJSON: "{\"status\":\"error\",\"message\":\"malformed-request\"}")
            return Self.encode(env) ?? "{}"
        }

        switch request.namespace {
        case KeychainCapability.namespace:
            return keyring.handleJSON(requestJSON)
        case PcstIdentityCapability.namespace:
            return identity.handleJSON(requestJSON)
        case HttpCapability.namespace:
            return http.handleJSON(requestJSON)
        case LegacyIOCapability.namespace:
            return legacyIO.handleJSON(requestJSON)
        case AudioCapability.namespace:
            return audio.handleJSON(requestJSON)
        case DownloadCapability.namespace:
            return download.handleJSON(requestJSON)
        default:
            // D6 — an unknown namespace is data, not a crash. Echo the
            // correlation id so the issuing kernel module can still correlate.
            let env = CapabilityEnvelope(
                namespace: request.namespace,
                correlationID: request.correlationID,
                resultJSON: "{\"status\":\"error\",\"message\":\"unknown-namespace\"}")
            return Self.encode(env) ?? "{}"
        }
    }

    private static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
