import Foundation

extension AppStateStore {
    func classifyNostrDiscoveryIntent(input: String) -> NostrIntentClassificationEnvelope? {
        kernel?.classifyNostrDiscoveryIntent(input: input)
    }

    @discardableResult
    func dispatchNostrDiscoveryIntent(input: String, sessionID: String) -> NostrIntentDispatchOutcome? {
        kernel?.dispatchNostrDiscoveryIntent(input: input, sessionID: sessionID)
    }

    func decodeNostrRef(uri: String) -> DecodedNostrRefTarget? {
        kernel?.decodeNostrRef(uri: uri)
    }

    func resolvedNostrProfilePubkeys() -> Set<String> {
        guard let profiles = kernel?.kernelIdentity.resolvedProfiles else { return [] }
        return Set(profiles.keys)
    }

    func awaitResolvedNostrProfilePubkey(
        excluding existing: Set<String>,
        timeout: Duration = .seconds(5)
    ) async -> String? {
        await awaitState(timeout: timeout) { [weak self] () -> String? in
            guard let profiles = self?.kernel?.kernelIdentity.resolvedProfiles else {
                return nil
            }
            return NostrResolvedProfileSelection.firstNewPubkey(
                in: profiles,
                excluding: existing)
        }
    }
}

enum NostrResolvedProfileSelection {
    static func firstNewPubkey(
        in profiles: [String: ResolvedProfile],
        excluding existing: Set<String>
    ) -> String? {
        profiles.keys
            .filter { !existing.contains($0) }
            .sorted()
            .first
    }
}
