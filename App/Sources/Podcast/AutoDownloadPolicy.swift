import Foundation

/// Per-subscription auto-download behaviour.
///
/// Mirrors the baseline matrix in `docs/spec/baseline-podcast-features.md` §3:
/// off / latest-N / all-new plus a Wi-Fi-only guard. Modelled as a struct so
/// the mode and the Wi-Fi guard evolve independently.
struct AutoDownloadPolicy: Codable, Sendable, Hashable {
    enum Mode: Codable, Sendable, Hashable {
        /// Never auto-download. User-initiated downloads still allowed.
        case off
        /// Keep the latest N episodes auto-downloaded; older ones may auto-prune.
        case latestN(Int)
        /// Auto-download every new episode the feed reports.
        case allNew
    }

    var mode: Mode
    /// When true, auto-download is gated on the device having a Wi-Fi route.
    var wifiOnly: Bool

    init(mode: Mode = .off, wifiOnly: Bool = true) {
        self.mode = mode
        self.wifiOnly = wifiOnly
    }

    /// Convenience: app default for new subscriptions.
    static let `default` = AutoDownloadPolicy(mode: .off, wifiOnly: true)
}
