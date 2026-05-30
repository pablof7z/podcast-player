import Foundation
import Network

/// Observes `NWPathMonitor` and fires `nmp.network.capability`
/// `ConnectivityChanged` reports so the Rust kernel knows whether
/// the device is on Wi-Fi. Rust uses this to honour per-subscription
/// Wi-Fi-only auto-download policies without iOS deciding which
/// episodes to queue (D7).
///
/// Usage: call `start(handle:)` once from `KernelModel.init()`, after
/// the podcast projection is registered.
@MainActor
final class NetworkCapability {
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "podcast.network-monitor", qos: .utility)
    private(set) var isOnWifi = true

    /// Begin monitoring and send an initial `ConnectivityChanged` event
    /// to prime the Rust-side state. No-op when `handle` is nil.
    func start(handle: UnsafeMutableRawPointer?) {
        guard let handle else { return }
        // Wrap the raw pointer in a value so the NWPathMonitor callback
        // (which is @Sendable) can capture it without a non-Sendable warning.
        let rawHandle = UInt(bitPattern: handle)
        monitor.pathUpdateHandler = { [weak self] path in
            let wifi = path.usesInterfaceType(.wifi)
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self,
                      let ptr = UnsafeMutableRawPointer(bitPattern: rawHandle)
                else { return }
                self.isOnWifi = wifi
                self.sendReport(
                    NetworkReport(isWifi: wifi, isConnected: connected),
                    handle: ptr)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    func stop() {
        monitor.cancel()
    }

    private func sendReport(_ report: NetworkReport, handle: UnsafeMutableRawPointer) {
        guard let json = try? JSONEncoder().encode(report),
              let jsonStr = String(data: json, encoding: .utf8)
        else { return }
        let result = jsonStr.withCString { nmp_app_podcast_network_report(handle, $0) }
        if let result { nmp_app_free_string(result) }
    }
}

// MARK: - Wire type

private struct NetworkReport: Encodable {
    enum CodingKeys: String, CodingKey {
        case type, isWifi = "is_wifi", isConnected = "is_connected"
    }
    let isWifi: Bool
    let isConnected: Bool
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("connectivity_changed", forKey: .type)
        try c.encode(isWifi, forKey: .isWifi)
        try c.encode(isConnected, forKey: .isConnected)
    }
}
