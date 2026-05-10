import Foundation

// MARK: - UserProfileDisplay
//
// Slice A reads only the read-only `UserIdentityStore` API. Until Slice B adds
// stored kind-0 fields (`name` / `display_name` / `about` / `picture`) on
// `UserIdentityStore`, this helper deterministically reproduces the same slug
// and dicebear URL the store emits via `publishGeneratedProfileIfNeeded`.
//
// Once Slice B merges, all call sites should switch to reading the live
// kind-0 fields directly off the identity store. Marker: `TODO Slice B`.

/// Stub for the user's kind-0 profile derived from `publicKeyHex`.
///
/// Mirrors `UserIdentityStore.generatedProfile(pubkey:)` exactly so the UI
/// never disagrees with what the store auto-published on first launch.
struct UserProfileDisplay {

    let displayName: String
    let slug: String
    let about: String
    let pictureURLString: String

    init(publicKeyHex: String) {
        let seed = String(publicKeyHex.prefix(16))
        let index = Self.stableIndex(seed)
        let adjectives = ["Bright", "Quiet", "Swift", "Kind", "Clear", "North"]
        let nouns = ["Signal", "Notebook", "Harbor", "Lantern", "Thread", "Field"]
        let adjective = adjectives[index % adjectives.count]
        let noun = nouns[(index / adjectives.count) % nouns.count]
        self.displayName = "\(adjective) \(noun)"
        self.slug = "\(adjective.lowercased())-\(noun.lowercased())-\(publicKeyHex.prefix(4))"
        self.about = ""
        self.pictureURLString = "https://api.dicebear.com/9.x/personas/svg?seed=\(seed)"
    }

    /// Convenience: returns `nil` when no identity exists yet.
    static func from(publicKeyHex: String?) -> UserProfileDisplay? {
        guard let hex = publicKeyHex, !hex.isEmpty else { return nil }
        return UserProfileDisplay(publicKeyHex: hex)
    }

    var pictureURL: URL? {
        guard let s = pictureURLString.isEmpty ? nil : pictureURLString,
              let url = URL(string: s),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    // MARK: - Hash helper

    /// Mirrors `UserIdentityStore.stableProfileIndex` so the picked
    /// adjective/noun pair stays stable between store and UI.
    private static func stableIndex(_ seed: String) -> Int {
        seed.utf8.reduce(0) { partial, byte in
            (partial &* 31 &+ Int(byte)) & 0x7fffffff
        }
    }
}

// MARK: - DicebearStyle (curated 6, per identity-05-synthesis §4.4)

/// The six curated dicebear styles offered to the user. Order matches the
/// horizontal rail in §4.4: personas, notionists, lorelei, shapes, glass,
/// identicon. Selected style is currently held only in local UI state — Slice B
/// will persist the user's pick into the kind-0 picture URL.
enum DicebearStyle: String, CaseIterable, Identifiable {
    case personas
    case notionists
    case lorelei
    case shapes
    case glass
    case identicon

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .personas:   "Personas"
        case .notionists: "Notionist"
        case .lorelei:    "Lorelei"
        case .shapes:     "Shapes"
        case .glass:      "Glass"
        case .identicon:  "Identicon"
        }
    }

    /// Builds the canonical dicebear URL for a pubkey-derived seed.
    func url(seed: String) -> URL? {
        URL(string: "https://api.dicebear.com/9.x/\(rawValue)/svg?seed=\(seed)")
    }
}
