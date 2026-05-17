import Foundation
@preconcurrency import NDKSwiftCore
import SwiftUI

struct RelayDiagnosticsSnapshot: Equatable {
    var relays: [RelayViewModel] = []

    var connectedCount: Int {
        relays.filter(\.state.isConnected).count
    }

    var activeSubscriptionCount: Int {
        relays.reduce(0) { $0 + $1.activeSubscriptions.count }
    }

    var messagesReceived: Int {
        relays.reduce(0) { $0 + $1.stats.messagesReceived }
    }

    var messagesSent: Int {
        relays.reduce(0) { $0 + $1.stats.messagesSent }
    }
}

struct RelayViewModel: Identifiable, Equatable {
    let id: String
    var url: String
    var source: String
    var state: RelayConnectionState
    var roles: [RelayRoleViewModel]
    var stats: RelayStatsViewModel
    var activeSubscriptions: [RelaySubscriptionViewModel]
    var relayInfo: RelayInfoViewModel?
    var authenticated: Bool
    var managedByNDK: Bool
    var statusDetail: String?
    var activityLines: [RelayActivityLine]

    var displayURL: String {
        RelayDiagnosticsURL.display(url)
    }

    var sortedRoles: [RelayRoleViewModel] {
        roles.sorted { $0.sortOrder < $1.sortOrder }
    }

    static func configured(
        url: String,
        roles: Set<RelayRoleViewModel>,
        source: String,
        statusDetail: String
    ) -> RelayViewModel {
        RelayViewModel(
            id: RelayDiagnosticsURL.canonical(url),
            url: url,
            source: source,
            state: .disconnected,
            roles: Array(roles).sorted { $0.sortOrder < $1.sortOrder },
            stats: RelayStatsViewModel(),
            activeSubscriptions: [],
            relayInfo: nil,
            authenticated: false,
            managedByNDK: false,
            statusDetail: statusDetail,
            activityLines: [
                RelayActivityLine(
                    level: .info,
                    timestamp: nil,
                    message: statusDetail
                ),
            ]
        )
    }
}

enum RelayConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case authRequired(String?)
    case authenticating
    case authenticated
    case failed(String)

    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .disconnecting: return "Disconnecting"
        case .authRequired: return "Auth required"
        case .authenticating: return "Authenticating"
        case .authenticated: return "Authenticated"
        case .failed: return "Failed"
        }
    }

    var detail: String? {
        switch self {
        case .authRequired(let challenge):
            guard let challenge, !challenge.isEmpty else { return "Relay requested authentication." }
            return "Relay requested authentication: \(challenge)"
        case .failed(let message):
            return message
        default:
            return nil
        }
    }

    var isConnected: Bool {
        self == .connected || self == .authenticated
    }

    var color: Color {
        switch self {
        case .connected, .authenticated:
            return .green
        case .connecting, .disconnecting, .authenticating:
            return .orange
        case .authRequired:
            return .yellow
        case .disconnected:
            return .secondary
        case .failed:
            return .red
        }
    }

    init(_ state: NDKRelayConnectionState) {
        switch state {
        case .disconnected: self = .disconnected
        case .connecting: self = .connecting
        case .connected: self = .connected
        case .disconnecting: self = .disconnecting
        case .authRequired(let challenge): self = .authRequired(challenge)
        case .authenticating: self = .authenticating
        case .authenticated: self = .authenticated
        case .failed(let message): self = .failed(message)
        }
    }
}

enum RelayRoleViewModel: String, CaseIterable, Identifiable, Hashable {
    case inbox = "Inbox"
    case publishing = "Publishing"
    case discovery = "Discovery"
    case pairing = "Pairing"
    case comments = "Comments"
    case feedback = "Feedback"
    case profile = "Profile"
    case outbox = "Outbox"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .inbox: return "tray.and.arrow.down"
        case .publishing: return "paperplane"
        case .discovery: return "magnifyingglass"
        case .pairing: return "qrcode.viewfinder"
        case .comments: return "bubble.left.and.bubble.right"
        case .feedback: return "exclamationmark.bubble"
        case .profile: return "person.crop.circle"
        case .outbox: return "arrow.triangle.branch"
        }
    }

    var description: String {
        switch self {
        case .inbox: return "Agent inbox and peer mentions"
        case .publishing: return "Outbound podcast and clip events"
        case .discovery: return "Relay-list, profile, and podcast discovery"
        case .pairing: return "NIP-46 signer pairing"
        case .comments: return "Episode comments and threads"
        case .feedback: return "Feedback roots and replies"
        case .profile: return "Kind 0 profile reads and writes"
        case .outbox: return "NDK outbox-discovered relay"
        }
    }

    var sortOrder: Int {
        switch self {
        case .inbox: return 0
        case .publishing: return 1
        case .discovery: return 2
        case .pairing: return 3
        case .comments: return 4
        case .feedback: return 5
        case .profile: return 6
        case .outbox: return 7
        }
    }
}

struct RelayStatsViewModel: Equatable {
    var connectedAt: Date?
    var lastMessageAt: Date?
    var lastActivityAt: Date?
    var messagesSent: Int = 0
    var messagesReceived: Int = 0
    var bytesReceived: Int = 0
    var bytesSent: Int = 0
    var latency: TimeInterval?
    var connectionAttempts: Int = 0
    var successfulConnections: Int = 0
    var validatedSignatures: Int = 0
    var skippedSignatureChecks: Int = 0
    var signatureVerificationEnabled: Bool = true
    var isEvil: Bool = false
    var evilDetectedAt: Date?
    var evilEventId: String?
}

struct RelaySubscriptionViewModel: Identifiable, Equatable {
    let id: String
    var filterSummary: String
    var kinds: [Int]
    var createdAt: Date
    var eventCount: Int
    var lastEventAt: Date?

    init(_ subscription: NDKRelaySubscriptionInfo) {
        id = subscription.id
        filterSummary = subscription.filters.map(\.description).joined(separator: "\n")
        kinds = Array(Set(subscription.filters.flatMap { $0.kinds ?? [] })).sorted()
        createdAt = subscription.createdAt
        eventCount = subscription.eventCount
        lastEventAt = subscription.lastEventAt
    }
}

struct RelayInfoViewModel: Equatable {
    var name: String?
    var description: String?
    var software: String?
    var version: String?
    var supportedNips: [Int]
    var contact: String?
    var limitation: RelayLimitationViewModel?

    init(_ info: NDKRelayInformation) {
        name = info.name
        description = info.description
        software = info.software
        version = info.version
        supportedNips = info.supportedNips ?? []
        contact = info.contact
        limitation = info.limitation.map(RelayLimitationViewModel.init)
    }
}

struct RelayLimitationViewModel: Equatable {
    var maxMessageLength: Int?
    var maxSubscriptions: Int?
    var maxFilters: Int?
    var maxLimit: Int?
    var authRequired: Bool?
    var paymentRequired: Bool?
    var restrictedWrites: Bool?

    init(_ limitation: RelayLimitation) {
        maxMessageLength = limitation.maxMessageLength
        maxSubscriptions = limitation.maxSubscriptions
        maxFilters = limitation.maxFilters
        maxLimit = limitation.maxLimit
        authRequired = limitation.authRequired
        paymentRequired = limitation.paymentRequired
        restrictedWrites = limitation.restrictedWrites
    }
}

struct RelayActivityLine: Identifiable, Equatable {
    enum Level: Equatable {
        case info
        case warning
        case error

        var color: Color {
            switch self {
            case .info: return .primary
            case .warning: return .orange
            case .error: return .red
            }
        }
    }

    let id = UUID()
    var level: Level
    var timestamp: Date?
    var message: String
}
