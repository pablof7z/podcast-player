import SwiftUI

// MARK: - OnboardingView per-step handlers
//
// Extracted from `OnboardingView.swift` so the main view stays focused on
// layout and state management. Each handler advances the step after running
// any side effects (Keychain writes, BYOK connect calls, etc.).
//
// NMP migration note: handlers no longer mutate a Swift-side `Settings`
// struct. The Rust kernel does not yet expose a `settings` action namespace
// (no `op` for `nostrProfileName`, `nostrProfilePicture`,
// `markOpenRouterManual`, or `hasCompletedOnboarding`). Until the settings
// projection lands, these draft values are kept only in local view state and
// the side-effecting Keychain / BYOK writes still run. Tracked in
// `docs/BACKLOG.md` under "Onboarding settings dispatch — pending settings
// projection".

extension OnboardingView {

    func handleAISetupContinue() {
        let trimmed = apiKeyDraft.trimmed
        guard !trimmed.isEmpty else {
            apiKeyError = nil
            advance()
            return
        }
        apiKeySaving = true
        apiKeyError = nil
        do {
            try OpenRouterCredentialStore.saveAPIKey(trimmed)
            // TODO(NMP settings projection): dispatch `markOpenRouterManual`
            // through the Rust kernel once a settings action namespace exists.
            apiKeyDraft = ""
            apiKeySaving = false
            Haptics.success()
            advance()
        } catch {
            apiKeySaving = false
            apiKeyError = "Could not save key. Tap Skip or try again."
            Haptics.error()
        }
    }

    func handleBYOKConnect() async {
        isConnectingBYOK = true
        apiKeyError = nil
        defer { isConnectingBYOK = false }
        do {
            let tokens = try await byokConnect.connectPodcastProviders()
            // TODO(NMP settings projection): persist imported BYOK credentials
            // via a Rust-kernel action once the settings projection lands.
            // Until then we still enforce "at least one provider returned" so
            // the user sees an explicit error if BYOK comes back empty.
            guard !tokens.isEmpty else {
                throw BYOKConnectError.noProviderKeysReturned
            }
            apiKeyDraft = ""
            Haptics.success()
            advance()
        } catch BYOKConnectError.cancelled {
            // user cancelled — no error shown
        } catch {
            apiKeyError = error.localizedDescription
            Haptics.error()
        }
    }

    func handleIdentityContinue() {
        // TODO(NMP settings projection): dispatch `nostrProfileName` and
        // `nostrProfilePicture` updates through the Rust kernel once a
        // settings action namespace exists. The draft values live in local
        // view state today; the user can re-enter them in Settings later.
        Haptics.success()
        advance()
    }

    func finishOnboarding() {
        // TODO(NMP settings projection): dispatch `hasCompletedOnboarding`
        // through the Rust kernel once a settings action namespace exists.
        // The current shell does not gate any surface on this flag, so the
        // missing persistence is invisible to the user beyond a repeated
        // onboarding flow on next launch.
        Haptics.success()
    }
}
