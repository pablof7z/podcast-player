import Foundation
import SwiftUI

struct RelayDiagnosticsSnapshot: Equatable {
    var relayURL: String = ""
    var isEnabled: Bool = false
}

enum RelayRoleViewModel: String, CaseIterable, Identifiable {
    case agentInbox = "Agent Inbox"
    case profile = "Profile Publishing"
    case pairing = "Pairing"
    case podcastPublishing = "Podcast Publishing"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .agentInbox: return "tray.fill"
        case .profile: return "person.crop.circle"
        case .pairing: return "qrcode"
        case .podcastPublishing: return "waveform"
        }
    }

    var description: String {
        switch self {
        case .agentInbox:
            return "Receives kind:1 messages directed at your agent pubkey."
        case .profile:
            return "Publishes your kind:0 profile when you update your identity."
        case .pairing:
            return "Facilitates NIP-46 NostrConnect pairing with external signers."
        case .podcastPublishing:
            return "Publishes NIP-F4 kind:10154/54 events for owned podcasts."
        }
    }
}
