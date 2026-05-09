import Foundation

/// Parses `podcastr://` deep-links into typed ``Link`` values.
///
/// All work is pure URL parsing with no shared state, so no actor isolation is required.
enum DeepLinkHandler {
    /// The set of deep-link destinations recognised by the app.
    enum Link {
        /// Opens the Settings sheet.
        case settings
        /// Opens the Feedback sheet.
        case feedback
        /// Opens the AI agent (Ask) tab.
        case agent
        /// Opens the Add Friend sheet pre-filled with the sender's public key and display name.
        /// `npub` is the bech32-encoded public key; `name` is the optional display name.
        case addFriend(npub: String, name: String?)
    }

    /// Converts a URL into a ``Link``, or returns `nil` if the URL is not a recognised deep-link.
    static func resolve(_ url: URL) -> Link? {
        guard url.scheme == "podcastr" else { return nil }
        switch url.host {
        case "settings": return .settings
        case "feedback": return .feedback
        case "agent":    return .agent
        case "friend":
            guard url.path == "/add",
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let npub = components.queryItems?.first(where: { $0.name == "npub" })?.value,
                  !npub.isEmpty
            else { return nil }
            let name = components.queryItems?.first(where: { $0.name == "name" })?.value
            return .addFriend(npub: npub, name: name)
        default: return nil
        }
    }

    // MARK: - Link builder

    /// Builds an `podcastr://friend/add` URL suitable for sharing in an invite message.
    static func friendInviteURL(npub: String, name: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "podcastr"
        components.host = "friend"
        components.path = "/add"
        var items: [URLQueryItem] = [URLQueryItem(name: "npub", value: npub)]
        if let name, !name.isEmpty {
            items.append(URLQueryItem(name: "name", value: name))
        }
        components.queryItems = items
        return components.url
    }
}
