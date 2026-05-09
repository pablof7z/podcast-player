import Foundation

/// Parses `apptemplate://` deep-links into typed ``Link`` values.
///
/// All work is pure URL parsing with no shared state, so no actor isolation is required.
enum DeepLinkHandler {
    /// The set of deep-link destinations recognised by the app.
    enum Link {
        /// Opens the Settings screen.
        case settings
        /// Opens the Feedback sheet.
        case feedback
        /// Creates a new item, optionally pre-filling its title from the query string.
        case newItem(title: String?)
        /// Navigates to Home and scrolls/focuses the Overdue section.
        case overdue
        /// Opens the AI agent chat sheet directly from Home.
        case agent
        /// Opens the Add Friend sheet pre-filled with the sender's public key and display name.
        /// `npub` is the bech32-encoded public key; `name` is the optional display name.
        case addFriend(npub: String, name: String?)
    }

    /// Converts a URL into a ``Link``, or returns `nil` if the URL is not a recognised deep-link.
    static func resolve(_ url: URL) -> Link? {
        guard url.scheme == "apptemplate" else { return nil }
        switch url.host {
        case "settings": return .settings
        case "feedback": return .feedback
        case "new-item":
            let title = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "title" })?.value
            return .newItem(title: title)
        case "overdue": return .overdue
        case "agent":   return .agent
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

    /// Builds an `apptemplate://friend/add` URL suitable for sharing in an invite message.
    static func friendInviteURL(npub: String, name: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "apptemplate"
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
