import SwiftUI

/// Twitter-style slide-in sidebar. Triggered by tapping the user avatar in the
/// navigation bar. Shows a left-anchored panel with the user's identity and
/// navigation shortcuts. Tap the darkened overlay to dismiss.
struct AppSidebarView: View {
    @Binding var selectedTab: RootTab
    @Binding var isPresented: Bool
    @Binding var showSettings: Bool

    @Environment(UserIdentityStore.self) private var userIdentity

    private let panelWidth: CGFloat = 300

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            panel
            dismissArea
        }
        .ignoresSafeArea()
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            avatarHeader
                .padding(.top, AppTheme.Spacing.xl + AppTheme.Spacing.lg)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.md)

            Divider()
                .padding(.bottom, AppTheme.Spacing.sm)

            navItems

            Spacer()
        }
        .frame(width: panelWidth)
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private var dismissArea: some View {
        Color.black.opacity(0.35)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { dismiss() }
    }

    // MARK: - Avatar header

    private var avatarHeader: some View {
        let profile = UserProfileDisplay.from(identity: userIdentity)
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            IdentityAvatarView(
                url: profile?.pictureURL,
                initial: profile?.displayName.first,
                size: 64
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(profile?.displayName ?? "Welcome")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(.primary)
                if let slug = profile?.slug, !slug.isEmpty {
                    Text("@\(slug)")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Navigation items

    private var navItems: some View {
        VStack(alignment: .leading, spacing: 0) {
            navButton("Home", icon: "house.fill", isActive: selectedTab == .home) {
                selectedTab = .home
                dismiss()
            }
            navButton("Clippings", icon: "scissors", isActive: selectedTab == .clippings) {
                selectedTab = .clippings
                dismiss()
            }
            navButton("Wiki", icon: "book.closed.fill", isActive: selectedTab == .wiki) {
                selectedTab = .wiki
                dismiss()
            }

            Divider()
                .padding(.vertical, AppTheme.Spacing.sm)
                .padding(.horizontal, AppTheme.Spacing.lg)

            navButton("Settings", icon: "gear", isActive: false) {
                showSettings = true
                dismiss()
            }
        }
    }

    private func navButton(
        _ title: String,
        icon: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: isActive ? .bold : .medium))
                    .foregroundStyle(isActive ? Color.accentColor : .primary)
                    .frame(width: 28)
                Text(title)
                    .font(isActive ? AppTheme.Typography.headline : AppTheme.Typography.title3)
                    .foregroundStyle(isActive ? Color.accentColor : .primary)
                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.sm + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dismiss

    private func dismiss() {
        Haptics.selection()
        withAnimation(AppTheme.Animation.spring) {
            isPresented = false
        }
    }
}
