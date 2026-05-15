import Foundation
import Observation
import os.log

@MainActor
@Observable
final class RelayConfigStore {
    private static let logger = Logger.app("RelayConfigStore")

    private(set) var relays: [RelayConfig] = []
    private let appStateStore: AppStateStore

    init(appStateStore: AppStateStore) {
        self.appStateStore = appStateStore
        self.relays = appStateStore.state.settings.relayConfigs

        if relays.isEmpty {
            migrateFromLegacy()
        } else {
            applyAndPersist()
        }
    }

    // MARK: - Mutations

    func addRelay(_ config: RelayConfig) {
        guard !relays.contains(where: { $0.url == config.url }) else { return }
        relays.append(config)
        applyAndPersist()
    }

    func removeRelay(url: String) {
        let normalized = RelayConfig.normalizeURL(url)
        relays.removeAll { $0.url == normalized }
        applyAndPersist()
    }

    func updateRoles(url: String, read: Bool, write: Bool, rooms: Bool, indexer: Bool) {
        let normalized = RelayConfig.normalizeURL(url)
        guard let idx = relays.firstIndex(where: { $0.url == normalized }) else { return }
        relays[idx].read = read
        relays[idx].write = write
        relays[idx].rooms = rooms
        relays[idx].indexer = indexer
        applyAndPersist()
    }

    /// Merge relays imported from another user. Existing `rooms`/`indexer` flags
    /// are preserved because those are app-specific; only `read`/`write` are OR'd in.
    func importRelays(_ newRelays: [RelayConfig]) {
        for newRelay in newRelays {
            if let idx = relays.firstIndex(where: { $0.url == newRelay.url }) {
                relays[idx].read = relays[idx].read || newRelay.read
                relays[idx].write = relays[idx].write || newRelay.write
            } else {
                relays.append(RelayConfig(
                    url: newRelay.url,
                    read: newRelay.read,
                    write: newRelay.write,
                    rooms: false,
                    indexer: false
                ))
            }
        }
        applyAndPersist()
    }

    // MARK: - Nostr Persistence

    func publishToNostr(signer: any NostrSigner) async {
        let snapshot = relays
        do {
            try await NIP65Publisher.publish(configs: snapshot, signer: signer)
        } catch {
            Self.logger.warning("NIP-65 publish failed at signer step: \(error.localizedDescription, privacy: .public)")
        }
        do {
            try await NIP78RelayStore.publish(configs: snapshot, signer: signer)
        } catch {
            Self.logger.warning("NIP-78 publish failed at signer step: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Placeholder for Phase 2. RelayPool-based fetch wiring lands when the pool exists;
    /// resolves the indexer/fallback URLs the fetch will target so the surface is settled.
    func fetchAndMergeFromNostr(pubkey _: String) async {
        let indexerURLs = relays.filter(\.indexer).map(\.url)
        let fallbackURLs = ["wss://purplepag.es", "wss://relay.primal.net"].map(RelayConfig.normalizeURL)
        _ = indexerURLs.isEmpty ? fallbackURLs : indexerURLs
    }

    // MARK: - Private

    /// Enforce pinned invariants, then persist. Call after every mutation.
    private func applyAndPersist() {
        RelayDefaults.enforcePinnedInvariants(&relays)
        persistLocally()
    }

    private func persistLocally() {
        var settings = appStateStore.state.settings
        settings.relayConfigs = relays
        appStateStore.updateSettings(settings)
    }

    private func migrateFromLegacy() {
        let settings = appStateStore.state.settings
        var migrated: [RelayConfig] = []

        if !settings.nostrRelayURL.isEmpty {
            migrated.append(RelayConfig(
                url: settings.nostrRelayURL,
                read: true,
                write: true
            ))
        }

        if migrated.isEmpty {
            migrated = RelayDefaults.seedRelays
        }

        relays = migrated
        applyAndPersist()
    }
}
