import Foundation

@MainActor
extension KernelModel {
    func classifyNostrDiscoveryIntent(input: String) -> NostrIntentClassificationEnvelope? {
        kernel.classifyNostrIntent(
            input: input,
            scopes: [.nostrRef, .nip50Profiles]
        )
    }

    func dispatchNostrDiscoveryIntent(
        input: String,
        sessionID: String
    ) -> NostrIntentDispatchOutcome? {
        kernel.dispatchNostrIntent(
            input: input,
            scopes: [.nostrRef, .nip50Profiles],
            sessionID: sessionID
        )
    }

    func decodeNostrRef(uri: String) -> DecodedNostrRefTarget? {
        kernel.decodeNostrRef(uri: uri)
    }
}
