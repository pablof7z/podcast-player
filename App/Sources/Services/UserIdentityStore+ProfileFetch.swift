import Foundation

// MARK: - Profile fetching (kind:0)
//
// Fetches the user's real Nostr kind:0 profile from relays after a key is
// adopted and caches it in UserDefaults so subsequent launches don't flash
// "generated → real" during the relay round-trip.
//
// Relay I/O now goes through the Rust core via `PodcastrCoreBridge`. We
// subscribe for the single pubkey, drain `ProfileRecord` deltas through
// the bridge, and unsubscribe on EOSE or after a short deadline.

extension UserIdentityStore {

    static let kind0CachePrefix = "io.f7z.podcast.kind0.v1."

    /// Subscription deadline for profile fetch. Slightly more generous than
    /// the one-shot `NostrProfileFetcher` (4s) — adopting an identity is a
    /// foreground action so we can afford a beat longer to wait for relays.
    private static let profileFetchTimeout: Duration = .seconds(5)

    /// Fetch the most-recent kind:0 event for `pubkeyHex` via the Rust core,
    /// parse its fields, and update the store's published profile fields
    /// (when `pubkeyHex` is the active identity). Silently no-ops on
    /// network failure so callers need not handle errors.
    func fetchAndCacheProfile(pubkeyHex: String) async {
        let bridge = PodcastrCoreBridge.shared

        // Track the freshest profile seen, then write once after teardown
        // to avoid touching `@Observable` state from the delta callback
        // (the bridge already hops to MainActor, but we want a single
        // write to keep behaviour identical to the pre-cutover code).
        let collector = ProfileCollector()

        let handle = bridge.register { delta in
            // Bridge already hops to MainActor before invoking us.
            MainActor.assumeIsolated {
                if case .profileUpdated(_, let profile) = delta.change {
                    collector.observe(profile)
                } else if case .subscriptionEose = delta.change {
                    collector.markEose()
                }
            }
        }

        let subID: String
        do {
            subID = try await bridge.core.subscribeProfiles(
                pubkeys: [pubkeyHex],
                callbackSubscriptionId: handle.callbackID
            )
        } catch {
            bridge.unregister(handle)
            return
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await collector.waitForEose()
            }
            group.addTask {
                try? await Task.sleep(for: Self.profileFetchTimeout)
            }
            await group.next()
            group.cancelAll()
        }

        await bridge.core.unsubscribeProfiles(subId: subID)
        bridge.unregister(handle)

        guard let profile = collector.latest else { return }

        let displayName = nonEmptyString(profile.displayName)
        let name        = nonEmptyString(profile.name)
        let about       = nonEmptyString(profile.about)
        let picture     = nonEmptyString(profile.picture)

        let payload: [String: String] = [
            "display_name": displayName ?? "",
            "name":         name        ?? "",
            "about":        about       ?? "",
            "picture":      picture     ?? "",
        ]
        if let cacheData = try? JSONSerialization.data(withJSONObject: payload) {
            UserDefaults.standard.set(cacheData, forKey: Self.kind0CachePrefix + pubkeyHex)
        }

        guard self.publicKeyHex == pubkeyHex else { return }
        self.profileDisplayName = displayName
        self.profileName        = name
        self.profileAbout       = about
        self.profilePicture     = picture
    }

    /// Load profile fields from the UserDefaults cache for instant display
    /// before the relay fetch completes. Called synchronously inside `adoptLocal`.
    /// Pure UserDefaults read — no Nostr I/O.
    func loadCachedProfile(for pubkeyHex: String) {
        guard let data = UserDefaults.standard.data(forKey: Self.kind0CachePrefix + pubkeyHex),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return }
        profileDisplayName = nonEmptyString(json["display_name"])
        profileName        = nonEmptyString(json["name"])
        profileAbout       = nonEmptyString(json["about"])
        profilePicture     = nonEmptyString(json["picture"])
    }

    private func nonEmptyString(_ s: String?) -> String? {
        s.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }
}

// MARK: - Profile collector

/// Holds the freshest `ProfileRecord` seen for the subscription and a
/// single-resume EOSE signal. MainActor-isolated because the bridge
/// delivers every delta on the MainActor — sharing this object keeps the
/// callback path single-threaded.
@MainActor
private final class ProfileCollector {
    private(set) var latest: ProfileRecord?
    private var eoseFired = false
    private var continuation: CheckedContinuation<Void, Never>?

    func observe(_ profile: ProfileRecord) {
        if let current = latest, current.createdAt >= profile.createdAt { return }
        latest = profile
    }

    func markEose() {
        guard !eoseFired else { return }
        eoseFired = true
        if let cont = continuation {
            continuation = nil
            cont.resume()
        }
    }

    func waitForEose() async {
        if eoseFired { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                if eoseFired || Task.isCancelled {
                    cont.resume()
                } else {
                    self.continuation = cont
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let cont = self.continuation {
                    self.continuation = nil
                    cont.resume()
                }
            }
        }
    }
}
