import Foundation

// MARK: - Profile fetching (kind:0)
//
// Routes all kind:0 profile resolution through the NMP kernel via
// `KernelModel.claimProfile`. NMP fetches over its relay pool and surfaces
// the result in `projections.resolved_profiles` → `AppStateStore.nostrProfileCache`.
// Swift never opens a WebSocket for profile data.

extension UserIdentityStore {

    static let kind0CachePrefix = "io.f7z.podcast.kind0.v1."

    /// Ask the kernel to fetch `pubkeyHex`'s kind:0 profile via its relay pool.
    /// The result arrives reactively through `projections.resolved_profiles` —
    /// no WebSocket opened here.
    func fetchAndCacheProfile(pubkeyHex: String) async {
        KernelModel.shared?.claimProfile(pubkeyHex: pubkeyHex,
                                         consumerID: "UserIdentityStore.ownProfile")
    }

    /// Load profile fields from the UserDefaults cache for instant display
    /// before the relay fetch completes. Called when the active pubkey changes (reconcile path).
    func loadCachedProfile(for pubkeyHex: String) {
        guard let data = UserDefaults.standard.data(forKey: Self.kind0CachePrefix + pubkeyHex),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return }
        profileDisplayName = nonEmptyString(json["display_name"])
        profileName        = nonEmptyString(json["name"])
        profileAbout       = nonEmptyString(json["about"])
        profilePicture     = nonEmptyString(json["picture"])
    }

    private func nonEmptyString(_ s: String?) -> String? {
        s.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }
}
