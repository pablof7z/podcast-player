import SwiftUI

// MARK: - AddShowSheet

/// Modal "+ Add Show" sheet for the Library tab. Four segments:
///
///   - **Search**   — Apple Podcasts directory search → one-tap subscribe.
///                    The default segment because most users discover by
///                    name, not by URL.
///   - **Nostr**    — NIP-F4 kind:10154 shows from a configured Nostr relay.
///   - **From URL** — paste / type a feed URL → `SubscriptionService.addSubscription`.
///   - **OPML**     — hands off to `OPMLImportSheet` for the file picker
///                    + per-row enrichment flow.
///
/// Surfaces all `SubscriptionService.AddError` cases inline so the user knows
/// whether they pasted a typo, hit a network blip, or are already subscribed.
struct AddShowSheet: View {

    enum Mode: String, CaseIterable, Identifiable {
        case search = "Search"
        case nostr = "Nostr"
        case url = "From URL"
        case opml = "OPML"

        var id: String { rawValue }
    }

    let store: AppStateStore
    let onDismiss: () -> Void

    @State private var mode: Mode = .search

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LiquidGlassSegmentedPicker(
                    "Add show source",
                    selection: $mode,
                    segments: Mode.allCases.map { ($0, $0.rawValue) }
                )
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.top, AppTheme.Spacing.sm)
                .padding(.bottom, AppTheme.Spacing.sm)

                Group {
                    switch mode {
                    case .search:
                        DiscoverSearchForm(store: store, onAdded: handleAdded)
                    case .nostr:
                        NostrDiscoverForm(store: store, onAdded: handleAdded)
                    case .url:
                        ScrollView {
                            AddByURLForm(store: store, onAdded: handleAddedFromURL)
                        }
                        .scrollDismissesKeyboard(.interactively)
                    case .opml:
                        OPMLImportContent(store: store, onDismiss: onDismiss)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Add Show")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Haptics.light()
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close")
        }
    }

    private func handleAdded(_ podcast: Podcast) {
        // Intentionally NOT auto-dismissing here. The Search segment lets
        // users add multiple shows in one sitting (and we want them to
        // *see* the row flip to a green checkmark — auto-dismiss made the
        // tap read as a no-op). The "From URL" segment, by contrast, is
        // single-shot, so it dismisses via its own success path.
        Haptics.success()
    }

    /// Single-shot success path for the From-URL segment. Closes the sheet
    /// because that flow always adds exactly one feed at a time and there
    /// is no list-of-rows to re-render with a checkmark.
    private func handleAddedFromURL(_ podcast: Podcast) {
        Haptics.success()
        onDismiss()
    }
}

// MARK: - AddByURLForm

/// "From URL" segment body. Lives next to `AddShowSheet` because the two are
/// always presented together and share the dismissal closure.
struct AddByURLForm: View {

    let store: AppStateStore
    /// Invoked on a successful subscribe so the parent can close the sheet.
    let onAdded: (Podcast) -> Void

    @State private var feedURL: String = ""
    @State private var isWorking: Bool = false
    @State private var error: SubscriptionService.AddError?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("Feed URL")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(.secondary)

                TextField("https://example.com/feed.rss", text: $feedURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit { Task { await submit() } }
                    .padding(AppTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .accessibilityIdentifier("add-show-url-field")

                Button {
                    paste()
                } label: {
                    Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                        .font(AppTheme.Typography.caption)
                }
                .buttonStyle(.borderless)
            }

            if let error {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Tint.error)
            }

            Button {
                Task { await submit() }
            } label: {
                HStack {
                    if isWorking { ProgressView().controlSize(.small) }
                    Text(isWorking ? "Fetching feed…" : "Subscribe")
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, AppTheme.Spacing.sm)
            }
            .buttonStyle(.glassProminent)
            .disabled(isWorking || feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
    }

    private func paste() {
        guard let text = UIPasteboard.general.string else { return }
        feedURL = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Haptics.selection()
    }

    private func submit() async {
        let trimmed = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isWorking else { return }
        isWorking = true
        error = nil

        if await handleNostrIntentIfRecognized(trimmed) {
            return
        }

        let service = SubscriptionService(store: store)
        do {
            let added = try await service.addSubscription(feedURLString: trimmed)
            isWorking = false
            onAdded(added)
        } catch let addError as SubscriptionService.AddError {
            isWorking = false
            // "Already subscribed" is success-like — the show the user
            // wanted is already in their library. Mirror DiscoverSearchForm's
            // behaviour: light haptic, dismiss the sheet via onAdded with
            // the existing record; no angry red banner.
            if case .alreadySubscribed = addError,
               let url = SubscriptionService.normalizedFeedURL(from: trimmed),
               let existing = store.podcast(feedURL: url) {
                Haptics.light()
                onAdded(existing)
                return
            }
            error = addError
            Haptics.warning()
        } catch {
            isWorking = false
            self.error = .transport(error.localizedDescription)
            Haptics.warning()
        }
    }

    private func handleNostrIntentIfRecognized(_ input: String) async -> Bool {
        guard let envelope = store.classifyNostrDiscoveryIntent(input: input),
              envelope.ok,
              let classification = envelope.classification else {
            return false
        }
        switch classification {
        case .rejection(.secretLike):
            isWorking = false
            error = SubscriptionService.AddError.transport(
                "This looks like a Nostr private key. Do not paste private keys here.")
            Haptics.warning()
            return true
        case .rejection(.unparseable):
            return false
        case .rejection:
            isWorking = false
            error = SubscriptionService.AddError.transport(
                "That Nostr input is not available from Add Show yet.")
            Haptics.warning()
            return true
        case .candidates(let candidates):
            guard let target = candidates.first?.target else { return false }
            return await handleNostrIntentTarget(target, originalInput: input)
        }
    }

    private func handleNostrIntentTarget(
        _ target: NostrIntentTarget,
        originalInput: String
    ) async -> Bool {
        switch target {
        case .directRef(let uri):
            guard let decoded = store.decodeNostrRef(uri: uri) else {
                isWorking = false
                error = SubscriptionService.AddError.transport(
                    "That Nostr reference could not be decoded.")
                Haptics.warning()
                return true
            }
            switch decoded {
            case .profile(let pubkey), .address(let pubkey):
                await subscribeToNostrAuthor(pubkey)
                return true
            case .event:
                isWorking = false
                error = SubscriptionService.AddError.transport(
                    "Nostr event links are not subscribable from Add Show yet. Try an npub or nprofile.")
                Haptics.warning()
                return true
            }
        case .nip05(let identifier):
            await subscribeToNip05Identifier(identifier, originalInput: originalInput)
            return true
        case .relayURL, .textQuery:
            return false
        case .registered:
            isWorking = false
            error = SubscriptionService.AddError.transport(
                "That Nostr input is not supported here yet.")
            Haptics.warning()
            return true
        }
    }

    private func subscribeToNip05Identifier(
        _ identifier: String,
        originalInput: String
    ) async {
        let existingProfiles = store.resolvedNostrProfilePubkeys()
        let outcome = store.dispatchNostrDiscoveryIntent(
            input: originalInput,
            sessionID: "add-show-\(UUID().uuidString)"
        )
        guard case .dispatched(.nip05(identifier: _)) = outcome else {
            isWorking = false
            error = SubscriptionService.AddError.transport(
                "That NIP-05 address could not be resolved from Add Show.")
            Haptics.warning()
            return
        }
        guard let pubkey = await store.awaitResolvedNostrProfilePubkey(
            excluding: existingProfiles,
            timeout: .seconds(5)
        ) else {
            isWorking = false
            error = SubscriptionService.AddError.transport(
                "Could not resolve \(identifier). Try an npub or nprofile.")
            Haptics.warning()
            return
        }
        await subscribeToNostrAuthor(pubkey)
    }

    private func subscribeToNostrAuthor(_ pubkey: String) async {
        do {
            let added = try await store.kernelSubscribeNostr(authorPubkeyHex: pubkey)
            isWorking = false
            onAdded(added)
        } catch let addError as SubscriptionService.AddError {
            isWorking = false
            error = addError
            Haptics.warning()
        } catch {
            isWorking = false
            self.error = .transport(error.localizedDescription)
            Haptics.warning()
        }
    }
}
