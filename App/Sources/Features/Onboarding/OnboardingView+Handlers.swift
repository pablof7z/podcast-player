import SwiftUI

// MARK: - OnboardingView per-step handlers
//
// Extracted from `OnboardingView.swift` so the main view stays focused on
// layout and state management. Each handler mutates the shared `@State`
// stored on the view and persists the result via `AppStateStore`.

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
            var s = store.state.settings
            s.markOpenRouterManual()
            store.updateSettings(s)
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
            let token = try await byokConnect.connectOpenRouter()
            try OpenRouterCredentialStore.saveAPIKey(token.apiKey)
            var s = store.state.settings
            s.markOpenRouterBYOK(keyID: token.keyID, keyLabel: token.keyLabel)
            store.updateSettings(s)
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

    func handleElevenLabsContinue() {
        let trimmed = elevenKeyDraft.trimmed
        guard !trimmed.isEmpty else {
            elevenKeyError = nil
            advance()
            return
        }
        elevenKeySaving = true
        elevenKeyError = nil
        do {
            try ElevenLabsCredentialStore.saveAPIKey(trimmed)
            var s = store.state.settings
            s.markElevenLabsManual()
            store.updateSettings(s)
            elevenKeyDraft = ""
            elevenKeySaving = false
            Haptics.success()
            advance()
        } catch {
            elevenKeySaving = false
            elevenKeyError = "Could not save key. Tap Skip or try again."
            Haptics.error()
        }
    }

    func handleIdentityContinue() {
        var s = store.state.settings
        let nameTrimmed = agentNameDraft.trimmed
        let pictureTrimmed = profilePictureDraft.trimmed
        if !nameTrimmed.isEmpty {
            s.nostrProfileName = nameTrimmed
        }
        if !pictureTrimmed.isEmpty {
            s.nostrProfilePicture = pictureTrimmed
        }
        store.updateSettings(s)
        Haptics.success()
        advance()
    }

    func finishOnboarding() {
        var s = store.state.settings
        s.hasCompletedOnboarding = true
        store.updateSettings(s)
        Haptics.success()
    }
}
