import Foundation

extension PodcastHandle {
    func classifyNostrIntent(
        input: String,
        scopes: [NostrIntentScope],
        textTargets: NostrIntentTextTargets = .userPreferred
    ) -> NostrIntentClassificationEnvelope? {
        let request = NostrIntentRequest(
            input: input,
            scopes: scopes,
            textTargets: textTargets
        )
        guard let json = request.jsonString() else { return nil }
        let envelope: String? = json.withCString { requestPtr in
            guard let ptr = nmp_app_intent_classify(raw, requestPtr) else { return nil }
            defer { nmp_free_string(ptr) }
            return String(cString: ptr)
        }
        return envelope.flatMap(NostrIntentClassificationEnvelope.decode)
    }

    func dispatchNostrIntent(
        input: String,
        scopes: [NostrIntentScope],
        sessionID: String,
        textTargets: NostrIntentTextTargets = .userPreferred
    ) -> NostrIntentDispatchOutcome? {
        let request = NostrIntentRequest(
            input: input,
            scopes: scopes,
            textTargets: textTargets
        )
        guard let json = request.jsonString() else { return nil }
        let envelope: String? = json.withCString { requestPtr in
            sessionID.withCString { sessionPtr in
                guard let ptr = nmp_app_intent_dispatch(raw, requestPtr, sessionPtr) else {
                    return nil
                }
                defer { nmp_free_string(ptr) }
                return String(cString: ptr)
            }
        }
        return envelope.flatMap(NostrIntentDispatchOutcome.decode)
    }

    func decodeNostrRef(uri: String) -> DecodedNostrRefTarget? {
        let envelope: String? = uri.withCString { uriPtr in
            guard let ptr = nmp_nip21_decode_uri(uriPtr) else { return nil }
            defer { nmp_free_string(ptr) }
            return String(cString: ptr)
        }
        return envelope.flatMap(DecodedNostrRefTarget.decode)
    }
}
