import SwiftUI

/// Lets the user log in with an nsec key for posting feedback under their
/// Nostr identity. Completely separate from the agent's identity.
struct UserIdentityView: View {

    // MARK: - Layout constants

    private enum Layout {
        /// Horizontal padding for the "Coming soon" chip.
        static let chipHorizontalPadding: CGFloat = 8
        /// Vertical padding for the "Coming soon" chip.
        static let chipVerticalPadding: CGFloat = 3
        /// Point size of the hero identity icon.
        static let heroIconSize: CGFloat = 56
    }
    @Environment(UserIdentityStore.self) private var identity
    @Environment(\.dismiss) private var dismiss

    @State private var nsecInput = ""
    @State private var bunkerInput = ""
    @State private var showClearConfirm = false
    @State private var showCopied = false
    @State private var isSaving = false
    @State private var isConnectingRemote = false
    @FocusState private var nsecFocused: Bool

    var body: some View {
        @Bindable var identityBindable = identity
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {
                    heroSection

                    if identity.hasIdentity {
                        identityCard
                        signOutButton
                    } else {
                        importCard
                        generateCard
                    }

                    nip46Card

                    footerNote
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.xl)
            }
            .navigationTitle("Your Identity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { nsecFocused = !identity.hasIdentity }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: identity.hasIdentity ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle.badge.plus")
                .font(.system(size: Layout.heroIconSize))
                .foregroundStyle(identity.hasIdentity ? Color.accentColor : Color(.tertiaryLabel))
                .symbolRenderingMode(.hierarchical)

            if identity.hasIdentity {
                Text("Signed in")
                    .font(AppTheme.Typography.headline)
                if let short = identity.npubShort {
                    Text(short)
                        .font(AppTheme.Typography.mono)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Connect your Nostr identity")
                    .font(AppTheme.Typography.headline)
                Text("Feedback you post will be signed with your key.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Identity card (when logged in)

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Label("Public key", systemImage: "key.fill")
                .font(AppTheme.Typography.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            if let npub = identity.npub {
                Text(npub)
                    .font(AppTheme.Typography.mono)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)

                copyNpubButton(npub: npub)
            }
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppTheme.Corner.md))
    }

    private func copyNpubButton(npub: String) -> some View {
        Button {
            copyToClipboard(npub, isCopied: $showCopied)
        } label: {
            Label(showCopied ? "Copied!" : "Copy npub", systemImage: showCopied ? "checkmark" : "doc.on.doc")
                .font(AppTheme.Typography.caption)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
        }
        .buttonStyle(.bordered)
        .tint(showCopied ? .green : .accentColor)
    }

    // MARK: - Import nsec card

    private var importCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Label("Sign in with nsec", systemImage: "key.horizontal.fill")
                .font(AppTheme.Typography.headline)

            SecureField("nsec1…", text: $nsecInput)
                .font(AppTheme.Typography.mono)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($nsecFocused)
                .padding(AppTheme.Spacing.sm)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: AppTheme.Corner.sm))
                .dismissKeyboardToolbar()

            if let error = identity.loginError {
                Text(error)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await saveNsec() }
            } label: {
                Label(isSaving ? "Importing…" : "Import key", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .disabled(nsecInput.isBlank || isSaving)
        }
        .padding(AppTheme.Spacing.md)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppTheme.Corner.md))
    }

    // MARK: - Generate card

    private var generateCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Label("Generate a new key", systemImage: "sparkles")
                .font(AppTheme.Typography.headline)
            Text("Creates a fresh Nostr identity stored only on this device.")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)
            Button {
                do {
                    try identity.generateKey()
                    Haptics.success()
                } catch {
                    Haptics.error()
                }
            } label: {
                Label("Generate key", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.sm)
            }
            .buttonStyle(.bordered)
        }
        .padding(AppTheme.Spacing.md)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppTheme.Corner.md))
    }

    // MARK: - NIP-46 (real)

    @ViewBuilder
    private var nip46Card: some View {
        Nip46ConnectCard(
            bunkerInput: $bunkerInput,
            isConnectingRemote: $isConnectingRemote,
            connect: { await connectRemoteSigner() },
            disconnect: { await identity.disconnectRemoteSigner() }
        )
        .environment(identity)
    }

    private func connectRemoteSigner() async {
        let trimmed = bunkerInput.trimmed
        guard !trimmed.isEmpty else { return }
        isConnectingRemote = true
        await identity.connectRemoteSigner(uri: trimmed)
        isConnectingRemote = false
        if identity.isRemoteSigner {
            bunkerInput = ""
            Haptics.success()
        } else {
            Haptics.error()
        }
    }

    // MARK: - Sign out

    private var signOutButton: some View {
        Button(role: .destructive) {
            showClearConfirm = true
        } label: {
            Label("Remove key from this device", systemImage: "trash")
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.sm)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        // `.alert` rather than `.confirmationDialog` — iOS 26's
        // popover-promotion can elide the Cancel button on dialogs
        // anchored to a tappable element (the red Remove button below).
        // Particularly important here: deleting the private key is
        // irreversible if the user doesn't have their nsec backed up
        // elsewhere. See same fix in ShowDetailView et al.
        .alert(
            "Remove your Nostr identity from this device?",
            isPresented: $showClearConfirm
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                identity.clearIdentity()
                Haptics.medium()
            }
        } message: {
            Text("Your private key will be deleted. Import your nsec again to restore access.")
        }
    }

    private var footerNote: some View {
        Text("Your private key is stored in the iOS Keychain and never leaves this device.")
            .font(AppTheme.Typography.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppTheme.Spacing.lg)
    }

    // MARK: - Actions

    private func saveNsec() async {
        isSaving = true
        let trimmed = nsecInput.trimmed
        do {
            try identity.importNsec(trimmed)
            nsecInput = ""
            Haptics.success()
        } catch {
            Haptics.error()
        }
        isSaving = false
    }
}
