import Foundation

// MARK: - NIP-42 AUTH

extension RelayConnection {
    func handleAuthOK(accepted: Bool, message: String?) {
        guard accepted else {
            setStatus(.error("AUTH rejected: \(message ?? "")"))
            return
        }
        setStatus(.connected)
        // Re-issue REQs — auth-gated relays drop pre-auth subscriptions silently.
        for (subID, sub) in subscriptions {
            subscriptions[subID]?.sentAt = Date()
            subscriptions[subID]?.rttRecorded = false
            sendREQ(id: subID, filter: sub.filter)
        }
        // Re-send pending EVENT frames. The continuation key is the event id,
        // so the eventual OK resolves the original `send(event:)` call.
        for (_, event) in pendingPublishEvents {
            sendFrame(["EVENT", eventDict(event)])
        }
    }

    func handleAuthChallenge(_ array: [Any]) {
        guard array.count >= 2, let challenge = array[1] as? String else { return }
        setStatus(.authenticating)
        Task { [weak self] in
            guard let self else { return }
            let draft = NostrEventDraft(
                kind: 22242,
                content: "",
                tags: [["relay", self.url], ["challenge", challenge]]
            )
            do {
                let event = try await self.signer.sign(draft)
                self.pendingAuthEventIDs.insert(event.id)
                self.sendFrame(["AUTH", self.eventDict(event)])
            } catch {
                self.setStatus(.error("AUTH signing failed: \(error.localizedDescription)"))
            }
        }
    }
}
