import Foundation
import Observation
import os.log

@MainActor
@Observable
final class RelayConfigStore {
    private static let logger = Logger.app("RelayConfigStore")

    private(set) var relays: [RelayConfig] = []
    private let appStateStore: AppStateStore
    private var relayPool: RelayPool?

    init(appStateStore: AppStateStore) {
        self.appStateStore = appStateStore
        self.relays = appStateStore.state.settings.relayConfigs

        if relays.isEmpty {
            migrateFromLegacy()
        } else {
            applyAndPersist()
        }
    }

    /// Attach a pool so every mutation re-reconciles connections. The pool
    /// is constructed once the user's signer is available, which happens
    /// after this store has already loaded local configs, so this is a
    /// separate hook rather than an init parameter.
    func attachRelayPool(_ pool: RelayPool) {
        self.relayPool = pool
        pool.reconcile(with: relays)
    }

    /// Drop the pool reference on sign-out so subsequent mutations don't
    /// reconnect the previous user's sockets through a torn-down pool.
    func detachRelayPool() {
        relayPool = nil
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

    /// Merge relays imported from another source (NIP-65, NIP-78, peer import).
    /// All four role fields are OR'd in so kind:30078 `rooms`/`indexer` flags
    /// survive; brand-new relays are copied wholesale.
    func importRelays(_ newRelays: [RelayConfig]) {
        for newRelay in newRelays {
            if let idx = relays.firstIndex(where: { $0.url == newRelay.url }) {
                relays[idx].read = relays[idx].read || newRelay.read
                relays[idx].write = relays[idx].write || newRelay.write
                relays[idx].rooms = relays[idx].rooms || newRelay.rooms
                relays[idx].indexer = relays[idx].indexer || newRelay.indexer
            } else {
                relays.append(newRelay)
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

    // MARK: - Private

    /// Enforce pinned invariants, persist locally, and re-reconcile the pool
    /// so connections always match the current config. Call after every mutation.
    private func applyAndPersist() {
        RelayDefaults.enforcePinnedInvariants(&relays)
        persistLocally()
        relayPool?.reconcile(with: relays)
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
