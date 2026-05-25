import SwiftUI

// MARK: - RelayListView
//
// NIP-65 (kind:10002) relay-list management. Lets the user view, add, and
// remove the relays advertised in their outbox/inbox metadata.
//
// State source:
//   The kernel snapshot does not yet surface the user's NIP-65 relay set
//   (the routing substrate's `InMemoryMailboxCache` is consumed internally
//   by the router; there is no projection field for it). Until that
//   projection lands the view holds its own list in `@AppStorage("nip65.relays")`
//   as JSON-encoded `[String]`, seeded on first read with the same primal +
//   damus defaults `NIP65RelayFetcher.defaultRelays` uses for the bootstrap
//   fetch in the legacy `App/Sources` codepath.
//
// Mutations:
//   The `nmp.nip65.publish_relay_list` action takes the FULL relay list,
//   not an incremental add/remove (see
//   `nmp-router/src/publish_relay_list.rs`). Add/remove therefore update
//   the local list, then dispatch the full new list. The action also
//   refuses an empty list (kernel-side guard against accidentally clearing
//   the cache), so the UI blocks removing the last relay.
//
// Mount point:
//   Linked from `AdvancedView` ("Advanced" under Identity) — relay
//   management is power-user territory and the rest of `AdvancedView`
//   already groups account-level / Nostr-protocol settings.

struct RelayListView: View {

    @Environment(KernelModel.self) private var model

    /// JSON-encoded `[String]` of relay URLs. Seeded with primal + damus
    /// on first read (see `relays` computed binding). Each mutation writes
    /// back the new JSON before dispatching.
    @AppStorage("nip65.relays") private var relaysJSON: String = ""

    @State private var showAddSheet: Bool = false
    @State private var pendingRemoval: String?
    @State private var publishStatus: PublishStatus = .idle

    // MARK: - Body

    var body: some View {
        Form {
            Section {
                if relays.isEmpty {
                    emptyStateRow
                } else {
                    ForEach(relays, id: \.self) { url in
                        relayRow(url)
                    }
                    .onDelete(perform: handleSwipeDelete)
                }
            } header: {
                Label("Your relays", systemImage: "antenna.radiowaves.left.and.right")
            } footer: {
                Text(footerText)
            }

            Section {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add relay", systemImage: "plus")
                }
            }

            if case let .failed(message) = publishStatus {
                Section {
                    Text(message)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Relays")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddSheet) {
            AddRelaySheet(onSubmit: handleAdd)
                .presentationDetents([.medium])
        }
        .confirmationDialog(
            "Remove this relay from your published list?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { url in
            Button("Remove", role: .destructive) { confirmRemove(url) }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { url in
            Text(url)
        }
        .onAppear { seedDefaultsIfNeeded() }
    }

    // MARK: - Rows

    @ViewBuilder
    private func relayRow(_ url: String) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(AppTheme.Typography.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(url)
                .font(AppTheme.Typography.monoCallout)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingRemoval = url
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .disabled(relays.count <= 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Relay \(url)")
    }

    private var emptyStateRow: some View {
        Text("No relays configured. Add one below to advertise where your Nostr posts get published.")
            .font(AppTheme.Typography.callout)
            .foregroundStyle(.secondary)
    }

    private var footerText: String {
        let base = "Your NIP-65 relay list (kind:10002) tells other Nostr clients where to read your posts and where to publish to reach you. Swipe to remove."
        if relays.count <= 1 {
            return base + "\n\nAt least one relay must stay in the list."
        }
        return base
    }

    // MARK: - Backing list

    /// Current decoded relay list. First read seeds with primal + damus
    /// defaults and writes them back so subsequent reads return the same
    /// stable order. Mutations go through `persist(_:)` directly — there is
    /// no setter here because every write also needs to dispatch the full
    /// list to the kernel (`publish(_:previous:)`).
    private var relays: [String] {
        decodedRelays()
    }

    private func decodedRelays() -> [String] {
        // Pure read — no mutation here so SwiftUI body evaluation stays
        // idempotent. The first-launch seed runs from `.onAppear` via
        // `seedDefaultsIfNeeded()`.
        if relaysJSON.isEmpty { return Self.defaultRelays }
        guard let data = relaysJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return Self.defaultRelays
        }
        return decoded
    }

    /// Write the default seed to `@AppStorage` on first appearance so the
    /// stored representation matches the rendered list. Runs once per cold
    /// launch (idempotent — re-entry is a no-op once non-empty).
    private func seedDefaultsIfNeeded() {
        guard relaysJSON.isEmpty else { return }
        persist(Self.defaultRelays)
    }

    private func persist(_ urls: [String]) {
        guard let data = try? JSONEncoder().encode(urls),
              let json = String(data: data, encoding: .utf8) else { return }
        relaysJSON = json
    }

    // MARK: - Defaults
    //
    // Mirror `App/Sources/Services/NIP65RelayFetcher.defaultRelays`. Two
    // widely-replicated public relays so a freshly-installed client has a
    // working baseline before the user customises.

    static let defaultRelays: [String] = [
        "wss://relay.primal.net",
        "wss://relay.damus.io",
    ]

    // MARK: - Mutations

    private func handleAdd(_ rawURL: String) {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidRelayURL(trimmed) else {
            publishStatus = .failed("Relay URL must start with wss:// (or ws://) and parse as a valid URL.")
            return
        }
        var next = relays
        guard !next.contains(trimmed) else {
            publishStatus = .failed("\(trimmed) is already in your relay list.")
            return
        }
        next.append(trimmed)
        publish(next, previous: relays)
        showAddSheet = false
    }

    private func handleSwipeDelete(at offsets: IndexSet) {
        // SwiftUI swipe-delete on a single-item list would empty it; guard
        // before mutating. The disabled state on the swipe button already
        // prevents this in practice, but defence-in-depth keeps the action
        // from ever firing.
        guard relays.count > 1 else { return }
        for index in offsets {
            let url = relays[index]
            pendingRemoval = url
        }
    }

    private func confirmRemove(_ url: String) {
        defer { pendingRemoval = nil }
        var next = relays
        next.removeAll(where: { $0 == url })
        guard !next.isEmpty else {
            publishStatus = .failed("At least one relay must remain in the list.")
            return
        }
        publish(next, previous: relays)
    }

    /// Persist optimistically, dispatch the full list, revert on rejection.
    private func publish(_ next: [String], previous: [String]) {
        persist(next)
        publishStatus = .publishing

        let entries = next.map { ["url": $0, "marker": "both"] }
        let result = model.dispatch(
            namespace: "nmp.nip65.publish_relay_list",
            body: ["relays": entries]
        )
        switch result {
        case .accepted:
            publishStatus = .idle
            Haptics.success()
        case .failure(let message):
            // Revert optimistic write so the UI stays in sync with what was
            // actually published.
            persist(previous)
            publishStatus = .failed(message)
            Haptics.warning()
        }
    }

    // MARK: - Validation

    private func isValidRelayURL(_ raw: String) -> Bool {
        guard raw.hasPrefix("wss://") || raw.hasPrefix("ws://") else { return false }
        guard let url = URL(string: raw), let host = url.host, !host.isEmpty else { return false }
        return true
    }

    // MARK: - Status

    private enum PublishStatus: Equatable {
        case idle
        case publishing
        case failed(String)
    }
}
