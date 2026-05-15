import Foundation

// MARK: - NIP-42 AUTH

extension RelayConnection {
    func handleAuthOK(accepted: Bool, message: String?) {
        guard accepted else {
            setStatus(.error("AUTH rejected: \(message ?? "")"))
            // Auth-required relays will keep refusing publishes until a fresh
            // AUTH succeeds, so any in-flight `send(event:)` waiters would
            // otherwise hang. Drop them (and the pending event buffer so a
            // future reconnect doesn't replay events doomed to fail again).
            failPendingPublishes(reason: "AUTH rejected: \(message ?? "")")
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
                // Without a signed AUTH event we can't reply to the challenge,
                // so the relay will keep rejecting publishes. Drain any
                // waiting `send(event:)` continuations rather than letting
                // them hang on a socket that will never make progress.
                self.failPendingPublishes(reason: "AUTH signing failed: \(error.localizedDescription)")
            }
        }
    }
}
