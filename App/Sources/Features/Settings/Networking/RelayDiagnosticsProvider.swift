import Foundation
@preconcurrency import NDKSwiftCore

@MainActor
enum RelayDiagnosticsProvider {
    static func load(store: AppStateStore) async -> RelayDiagnosticsSnapshot {
        let settings = store.state.settings
        let configured = configuredRelays(settings: settings)
        var relaysByID: [String: RelayViewModel] = [:]

        if let ndk = NostrStack.shared.ndk {
            for relay in await ndk.poolRelays {
                let id = RelayDiagnosticsURL.canonical(relay.url)
                let origin = await relay.origin
                let configuredRoles = configured[id]?.roles ?? []
                let roles = mergedRoles(
                    configuredRoles,
                    inferredRoles(for: relay.url, settings: settings, origin: origin)
                )
                relaysByID[id] = await relayViewModel(
                    relay: relay,
                    id: id,
                    roles: roles,
                    source: sourceLabel(origin: origin)
                )
            }
        }

        for relay in configured.values where relaysByID[relay.id] == nil {
            relaysByID[relay.id] = .configured(
                url: relay.url,
                roles: relay.roles,
                source: relay.source,
                statusDetail: relay.statusDetail
            )
        }

        let relays = relaysByID.values.sorted { lhs, rhs in
            if lhs.state.isConnected != rhs.state.isConnected {
                return lhs.state.isConnected && !rhs.state.isConnected
            }
            if lhs.managedByNDK != rhs.managedByNDK {
                return lhs.managedByNDK && !rhs.managedByNDK
            }
            return lhs.displayURL.localizedCaseInsensitiveCompare(rhs.displayURL) == .orderedAscending
        }
        return RelayDiagnosticsSnapshot(relays: relays, refreshedAt: Date())
    }

    private static func relayViewModel(
        relay: NDKRelay,
        id: String,
        roles: [RelayRoleViewModel],
        source: String
    ) async -> RelayViewModel {
        let state = RelayConnectionState(await relay.connectionState)
        let stats = await relay.stats
        let activeSubscriptions = await relay.activeSubscriptions
        let info = await relay.info
        let authenticated = await relay.isAuthenticated
        let statsModel = RelayStatsViewModel(
            connectedAt: stats.connectedAt,
            lastMessageAt: stats.lastMessageAt,
            lastActivityAt: stats.lastActivityAt,
            messagesSent: stats.messagesSent,
            messagesReceived: stats.messagesReceived,
            bytesReceived: stats.bytesReceived,
            bytesSent: stats.bytesSent,
            latency: stats.latency,
            connectionAttempts: stats.connectionAttempts,
            successfulConnections: stats.successfulConnections,
            validatedSignatures: stats.signatureStats.validatedCount,
            skippedSignatureChecks: stats.signatureStats.nonValidatedCount,
            signatureVerificationEnabled: stats.signatureStats.verificationEnabled,
            isEvil: stats.isEvil,
            evilDetectedAt: stats.evilDetectedAt,
            evilEventId: stats.evilEventId
        )
        return RelayViewModel(
            id: id,
            url: relay.url,
            source: source,
            state: state,
            roles: roles,
            stats: statsModel,
            activeSubscriptions: activeSubscriptions.map(RelaySubscriptionViewModel.init),
            relayInfo: info.map(RelayInfoViewModel.init),
            authenticated: authenticated,
            managedByNDK: true,
            statusDetail: state.detail,
            activityLines: activityLines(state: state, stats: statsModel)
        )
    }

    private static func activityLines(
        state: RelayConnectionState,
        stats: RelayStatsViewModel
    ) -> [RelayActivityLine] {
        var lines: [RelayActivityLine] = []
        if let detail = state.detail {
            let level: RelayActivityLine.Level
            if case .failed = state {
                level = .error
            } else {
                level = .warning
            }
            lines.append(RelayActivityLine(
                level: level,
                timestamp: Date(),
                message: detail
            ))
        }
        if let lastMessageAt = stats.lastMessageAt {
            lines.append(RelayActivityLine(
                level: .info,
                timestamp: lastMessageAt,
                message: "Received relay message \(stats.messagesReceived.formatted())"
            ))
        }
        if let connectedAt = stats.connectedAt {
            lines.append(RelayActivityLine(
                level: .info,
                timestamp: connectedAt,
                message: "Connected after \(stats.connectionAttempts.formatted()) attempt(s)"
            ))
        }
        if stats.isEvil {
            lines.append(RelayActivityLine(
                level: .error,
                timestamp: stats.evilDetectedAt,
                message: "Invalid signature detected for event \(stats.evilEventId ?? "unknown")"
            ))
        }
        if lines.isEmpty {
            lines.append(RelayActivityLine(
                level: .info,
                timestamp: nil,
                message: "No relay activity recorded yet."
            ))
        }
        return lines.sorted { lhs, rhs in
            switch (lhs.timestamp, rhs.timestamp) {
            case let (lhs?, rhs?): return lhs > rhs
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.message < rhs.message
            }
        }
    }

    private static func configuredRelays(settings: Settings) -> [String: ConfiguredRelay] {
        var relays: [String: ConfiguredRelay] = [:]
        func add(_ url: String, roles: Set<RelayRoleViewModel>, source: String) {
            let trimmed = url.trimmed
            guard !trimmed.isEmpty else { return }
            let id = RelayDiagnosticsURL.canonical(trimmed)
            if var existing = relays[id] {
                existing.roles.formUnion(roles)
                existing.source = uniqueSources([existing.source, source]).joined(separator: ", ")
                relays[id] = existing
            } else {
                relays[id] = ConfiguredRelay(
                    id: id,
                    url: trimmed,
                    roles: roles,
                    source: source,
                    statusDetail: "Configured, but not currently in the shared NDK relay pool."
                )
            }
        }

        add(settings.nostrRelayURL, roles: [.inbox, .comments], source: "Agent relay")
        for relay in settings.nostrPublicRelays {
            add(relay, roles: [.publishing], source: "Publishing relay")
        }
        if settings.nostrPublicRelays.isEmpty {
            for relay in NIP65RelayFetcher.defaultRelays {
                add(relay, roles: [.publishing, .discovery], source: "Publishing fallback")
            }
        }
        add(FeedbackRelayClient.feedbackRelayURL.absoluteString, roles: [.feedback], source: "Feedback")
        for relay in FeedbackRelayClient.profileRelayURLs {
            add(relay.absoluteString, roles: [.profile], source: "Profile")
        }
        add(RemoteSigner.nostrConnectDefaultRelay.absoluteString, roles: [.pairing], source: "NIP-46 pairing")
        add("wss://relay.primal.net", roles: [.discovery], source: "Discovery")
        return relays
    }

    private static func uniqueSources(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for source in values.flatMap({ $0.split(separator: ",").map { String($0).trimmed } }) {
            guard !source.isEmpty, seen.insert(source).inserted else { continue }
            result.append(source)
        }
        return result
    }

    private static func inferredRoles(
        for url: String,
        settings: Settings,
        origin: NDKRelayOrigin
    ) -> Set<RelayRoleViewModel> {
        var roles: Set<RelayRoleViewModel> = []
        let id = RelayDiagnosticsURL.canonical(url)
        if id == RelayDiagnosticsURL.canonical(settings.nostrRelayURL) {
            roles.formUnion([.inbox, .comments])
        }
        if settings.nostrPublicRelays.map(RelayDiagnosticsURL.canonical).contains(id) {
            roles.insert(.publishing)
        }
        if id == RelayDiagnosticsURL.canonical("wss://relay.primal.net") {
            roles.insert(.discovery)
        }
        switch origin {
        case .appRelays:
            break
        case .discovery:
            roles.insert(.discovery)
        case .outbox:
            roles.insert(.outbox)
        }
        return roles
    }

    private static func mergedRoles(
        _ lhs: Set<RelayRoleViewModel>,
        _ rhs: Set<RelayRoleViewModel>
    ) -> [RelayRoleViewModel] {
        lhs.union(rhs).sorted { $0.sortOrder < $1.sortOrder }
    }

    private static func sourceLabel(origin: NDKRelayOrigin) -> String {
        switch origin {
        case .appRelays: return "App relay"
        case .discovery: return "Discovery relay"
        case .outbox(let pubkey): return "Outbox \(pubkey.prefix(8))"
        }
    }
}

private struct ConfiguredRelay {
    var id: String
    var url: String
    var roles: Set<RelayRoleViewModel>
    var source: String
    var statusDetail: String
}

enum RelayDiagnosticsURL {
    static func canonical(_ url: String) -> String {
        var value = url.trimmed.lowercased()
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    static func display(_ url: String) -> String {
        canonical(url)
            .replacingOccurrences(of: "wss://", with: "")
            .replacingOccurrences(of: "ws://", with: "")
    }
}
