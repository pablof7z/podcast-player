import SwiftUI

// MARK: - EditProfileView
//
// Push from `IdentityRootView`. Per identity-05-synthesis §4.3. Save publishes
// kind-0; until Slice B wires `UserIdentityStore.publishProfile`, save is a
// local-only stub (TODO Slice B).
//
// Field rules from §4.3:
//   - Display name: 0-48 chars, empty allowed (falls back to slug)
//   - Username:     1-32 chars (unicode allowed)
//   - About:        0-280 chars; counter visible only when remaining ≤ 50
//   - Save disabled until dirty; .alert on cancel-with-dirty
//   - Errors: inline footer banner, never alert (except cancel-discard)

struct EditProfileView: View {

    private enum Limits {
        static let displayNameMax = 48
        static let usernameMax = 32
        static let usernameMin = 1
        static let aboutMax = 280
        static let aboutCounterThreshold = 50
    }

    @Environment(UserIdentityStore.self) private var identity
    @Environment(\.dismiss) private var dismiss

    // Local edit state — Slice A stores only on this device.
    @State private var displayName: String = ""
    @State private var username: String = ""
    @State private var about: String = ""
    @State private var pictureURL: String = ""
    @State private var pictureSheetPresented = false
    @State private var discardConfirmPresented = false
    @State private var saveBanner: SaveBanner?

    /// Captures the initial values so dirty-detection can compare and
    /// cancel-with-dirty can offer a Discard alert.
    @State private var initialSnapshot: Snapshot?

    @FocusState private var nameFocused: Bool
    @FocusState private var usernameFocused: Bool
    @FocusState private var aboutFocused: Bool

    var body: some View {
        Form {
            Section {
                heroRow
            }
            Section("Display name") {
                TextField("e.g. Bright Signal", text: $displayName)
                    .textInputAutocapitalization(.words)
                    .focused($nameFocused)
                    .onChange(of: displayName) { _, new in
                        if new.count > Limits.displayNameMax {
                            displayName = String(new.prefix(Limits.displayNameMax))
                        }
                    }
            }
            Section {
                TextField("bright-signal-a3f2", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($usernameFocused)
                    .onSubmit { restoreUsernameIfBlank() }
                    .onChange(of: username) { _, new in
                        if new.count > Limits.usernameMax {
                            username = String(new.prefix(Limits.usernameMax))
                        }
                    }
            } header: {
                Text("Username")
            } footer: {
                Text("Used to sign your contributions. Letters, numbers, and dashes work best.")
            }
            aboutSection
            if let banner = saveBanner {
                Section { savedBannerView(banner) }
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { Task { await save() } }
                    .disabled(!isDirty)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { handleCancel() }
            }
        }
        .alert("Discard changes?", isPresented: $discardConfirmPresented) {
            Button("Keep editing", role: .cancel) {}
            Button("Discard", role: .destructive) { dismiss() }
        }
        .sheet(isPresented: $pictureSheetPresented) {
            ChangePhotoSheet(pictureURL: $pictureURL)
        }
        .onAppear { hydrateFromIdentity() }
    }

    // MARK: - Hero

    private var heroRow: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            IdentityAvatarView(
                url: previewURL,
                initial: displayName.first ?? identityProfile?.displayName.first,
                size: 88
            )
            Button {
                pictureSheetPresented = true
            } label: {
                Text("Change photo")
                    .font(AppTheme.Typography.caption)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    private var previewURL: URL? {
        if let url = URL(string: pictureURL.trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }
        return identityProfile?.pictureURL
    }

    // MARK: - About section

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                if about.isEmpty {
                    Text("Tell people who you are.")
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $about)
                    .frame(minHeight: 80)
                    .focused($aboutFocused)
                    .onChange(of: about) { _, new in
                        if new.count > Limits.aboutMax {
                            about = String(new.prefix(Limits.aboutMax))
                        }
                    }
            }
        } header: {
            Text("About")
        } footer: {
            HStack {
                Spacer()
                if Limits.aboutMax - about.count <= Limits.aboutCounterThreshold {
                    Text("\(Limits.aboutMax - about.count) characters left")
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Saved banner

    private struct SaveBanner: Equatable {
        let message: String
        let isWarning: Bool
    }

    @ViewBuilder
    private func savedBannerView(_ banner: SaveBanner) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: banner.isWarning ? "wifi.exclamationmark" : "checkmark.circle.fill")
                .foregroundStyle(banner.isWarning ? .orange : .green)
            Text(banner.message)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Snapshot / dirty / hydrate

    private struct Snapshot: Equatable {
        var displayName: String
        var username: String
        var about: String
        var pictureURL: String
    }

    private var currentSnapshot: Snapshot {
        Snapshot(
            displayName: displayName,
            username: username,
            about: about,
            pictureURL: pictureURL
        )
    }

    private var isDirty: Bool {
        guard let initial = initialSnapshot else { return false }
        return initial != currentSnapshot
    }

    private var identityProfile: UserProfileDisplay? {
        UserProfileDisplay.from(publicKeyHex: identity.publicKeyHex)
    }

    private func hydrateFromIdentity() {
        guard initialSnapshot == nil else { return }
        // TODO Slice B: hydrate from UserIdentityStore's stored kind-0 fields
        // once they exist. Today we seed with the deterministic display name
        // and slug emitted by `publishGeneratedProfileIfNeeded`.
        let p = identityProfile
        displayName = p?.displayName ?? ""
        username    = p?.slug ?? ""
        about       = p?.about ?? ""
        pictureURL  = p?.pictureURLString ?? ""
        initialSnapshot = currentSnapshot
    }

    private func restoreUsernameIfBlank() {
        if username.trimmed.isEmpty, let prior = initialSnapshot?.username, !prior.isEmpty {
            username = prior
            Haptics.light()
        }
    }

    // MARK: - Actions

    private func handleCancel() {
        if isDirty {
            discardConfirmPresented = true
        } else {
            dismiss()
        }
    }

    private func save() async {
        // TODO Slice B: call `identity.publishProfile(name:displayName:about:picture:)`
        // (new method) — sign + publish kind-0 to FeedbackRelayClient.profileRelayURLs.
        // For Slice A we accept the edit, post a success haptic, and pop.
        Haptics.success()
        initialSnapshot = currentSnapshot
        saveBanner = SaveBanner(
            message: "Saved on this device. Sync arrives with Slice B.",
            isWarning: true
        )
        try? await Task.sleep(for: .seconds(0.3))
        dismiss()
    }
}

// MARK: - End — see ChangePhotoSheet.swift for the photo chooser used above.
