import Foundation

// MARK: - Profile fetching (kind:0)
//
// Routes all kind:0 profile resolution through the NMP kernel via
// `KernelModel.claimProfile`. NMP fetches over its relay pool and surfaces
// the result in `projections.resolved_profiles` → `AppStateStore.nostrProfileCache`.
// Swift never opens a WebSocket for profile data.

extension UserIdentityStore {

    /// Ask the kernel to fetch `pubkeyHex`'s kind:0 profile via its relay pool.
    /// The result arrives reactively through `projections.resolved_profiles` —
    /// no WebSocket opened here.
    func claimProfile(pubkeyHex: String) async {
        KernelModel.shared?.claimProfile(pubkeyHex: pubkeyHex,
                                         consumerID: "UserIdentityStore.ownProfile")
    }
}
