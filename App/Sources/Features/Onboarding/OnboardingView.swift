import SwiftUI

struct OnboardingView: View {
    @Environment(AppStateStore.self) private var store

    @State private var pageIndex: Int = 0
    @State private var apiKeyDraft: String = ""
    @State private var apiKeyError: String?
    @State private var apiKeySaving: Bool = false
    @State private var isConnectingBYOK: Bool = false
    @State private var byokConnect = BYOKConnectService()
    @State private var agentNameDraft: String = ""
    @State private var profilePictureDraft: String = ""

    private let pageCount: Int = 4

    private enum Layout {
        static let chipHorizontalPadding: CGFloat = 14
        static let chipVerticalPadding: CGFloat = 8
        /// Height of the top bar (back / skip buttons row).
        static let topBarHeight: CGFloat = 60
    }

    private enum Page {
        static let welcome = 0
        static let aiSetup = 1
        static let identity = 2
    }

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                pages
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Pages

    private var pages: some View {
        TabView(selection: $pageIndex) {
            OnboardingWelcomePage()
                .tag(0)
                .padding(.horizontal, AppTheme.Spacing.lg)

            OnboardingAISetupPage(
                apiKey: $apiKeyDraft,
                errorMessage: apiKeyError,
                isSaving: apiKeySaving || isConnectingBYOK,
                isConnectingBYOK: isConnectingBYOK,
                onConnectBYOK: { Task { await handleBYOKConnect() } }
            )
            .tag(1)
            .padding(.horizontal, AppTheme.Spacing.lg)

            OnboardingIdentityPage(
                agentName: $agentNameDraft,
                profilePicture: $profilePictureDraft
            )
            .tag(2)
            .padding(.horizontal, AppTheme.Spacing.lg)

            OnboardingReadyPage()
                .tag(3)
                .padding(.horizontal, AppTheme.Spacing.lg)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .animation(AppTheme.Animation.spring, value: pageIndex)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            if pageIndex > 0 { backButton }
            Spacer()
            if shouldShowSkip { skipButton }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.top, AppTheme.Spacing.md)
        .frame(height: Layout.topBarHeight)
    }

    private var backButton: some View {
        Button {
            Haptics.selection()
            withAnimation(AppTheme.Animation.spring) { pageIndex -= 1 }
        } label: {
            Label("Back", systemImage: "chevron.left")
                .font(AppTheme.Typography.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Layout.chipHorizontalPadding)
                .padding(.vertical, Layout.chipVerticalPadding)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private var skipButton: some View {
        Button {
            Haptics.selection()
            advanceOrFinish()
        } label: {
            Text("Skip")
                .font(AppTheme.Typography.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, Layout.chipHorizontalPadding)
                .padding(.vertical, Layout.chipVerticalPadding)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Button {
                Haptics.medium()
                primaryAction()
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Text(primaryButtonTitle)
                        .font(AppTheme.Typography.headline)
                    if pageIndex < pageCount - 1 {
                        Image(systemName: "arrow.right")
                            .font(AppTheme.Typography.headline)
                    } else {
                        Image(systemName: "sparkles")
                            .font(AppTheme.Typography.headline)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: OnboardingLayout.primaryButtonMinHeight)
                .padding(.vertical, OnboardingLayout.primaryButtonVerticalPadding)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(.white)
            .foregroundStyle(.black)
            .disabled(apiKeySaving)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.bottom, AppTheme.Spacing.lg)
        .padding(.top, AppTheme.Spacing.sm)
    }

    // MARK: - Logic

    private var shouldShowSkip: Bool {
        pageIndex == Page.identity
    }

    private var primaryButtonTitle: String {
        switch pageIndex {
        case Page.welcome: "Get Started"
        case Page.aiSetup: apiKeyDraft.isBlank ? "Skip for Now" : "Save Key"
        case Page.identity: agentNameDraft.isBlank ? "Skip for Now" : "Save"
        default: "Enter App"
        }
    }

    private func primaryAction() {
        switch pageIndex {
        case Page.aiSetup:
            handleAISetupContinue()
        case Page.identity:
            handleIdentityContinue()
        case pageCount - 1:
            finishOnboarding()
        default:
            advanceOrFinish()
        }
    }

    private func advanceOrFinish() {
        if pageIndex < pageCount - 1 {
            withAnimation(AppTheme.Animation.spring) { pageIndex += 1 }
        } else {
            finishOnboarding()
        }
    }

    private func handleAISetupContinue() {
        let trimmed = apiKeyDraft.trimmed
        guard !trimmed.isEmpty else {
            apiKeyError = nil
            advanceOrFinish()
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
            advanceOrFinish()
        } catch {
            apiKeySaving = false
            apiKeyError = "Could not save key. Tap Skip or try again."
            Haptics.error()
        }
    }

    private func handleBYOKConnect() async {
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
            advanceOrFinish()
        } catch BYOKConnectError.cancelled {
            // user cancelled — no error shown
        } catch {
            apiKeyError = error.localizedDescription
            Haptics.error()
        }
    }

    private func handleIdentityContinue() {
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
        advanceOrFinish()
    }

    private func finishOnboarding() {
        var s = store.state.settings
        s.hasCompletedOnboarding = true
        store.updateSettings(s)
        Haptics.success()
    }

    // MARK: - Background

    private var backgroundGradient: LinearGradient {
        AppTheme.Gradients.onboardingNebula
    }
}
