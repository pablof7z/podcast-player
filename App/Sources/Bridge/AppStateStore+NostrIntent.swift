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
}
