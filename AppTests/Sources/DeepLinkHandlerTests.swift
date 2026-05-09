import XCTest
@testable import Podcastr

/// Coverage for `DeepLinkHandler.resolve` and `friendInviteURL`. The
/// parser sits behind every quick-action, push-notification tap, and
/// share-sheet target, so a regression in URL parsing means
/// "tapping Open Agent does nothing" or "shared friend invite goes
/// to a blank Add Friend sheet."
@MainActor
final class DeepLinkHandlerTests: XCTestCase {

    // MARK: - Simple hosts

    func testResolvesSettings() {
        let url = URL(string: "podcastr://settings")!
        guard case .settings = DeepLinkHandler.resolve(url) else {
            XCTFail("Expected .settings"); return
        }
    }

    func testResolvesFeedback() {
        let url = URL(string: "podcastr://feedback")!
        guard case .feedback = DeepLinkHandler.resolve(url) else {
            XCTFail("Expected .feedback"); return
        }
    }

    func testResolvesAgent() {
        let url = URL(string: "podcastr://agent")!
        guard case .agent = DeepLinkHandler.resolve(url) else {
            XCTFail("Expected .agent"); return
        }
    }

    // MARK: - Friend

    func testResolvesFriendWithNpubAndName() {
        let url = URL(string: "podcastr://friend/add?npub=npub1abc&name=Alice")!
        guard case .addFriend(let npub, let name) = DeepLinkHandler.resolve(url) else {
            XCTFail("Expected .addFriend"); return
        }
        XCTAssertEqual(npub, "npub1abc")
        XCTAssertEqual(name, "Alice")
    }

    func testResolvesFriendWithNpubOnly() {
        let url = URL(string: "podcastr://friend/add?npub=npub1xyz")!
        guard case .addFriend(let npub, let name) = DeepLinkHandler.resolve(url) else {
            XCTFail("Expected .addFriend"); return
        }
        XCTAssertEqual(npub, "npub1xyz")
        XCTAssertNil(name)
    }

    func testFriendMissingNpubReturnsNil() {
        let url = URL(string: "podcastr://friend/add?name=Alice")!
        XCTAssertNil(DeepLinkHandler.resolve(url))
    }

    func testFriendEmptyNpubReturnsNil() {
        let url = URL(string: "podcastr://friend/add?npub=&name=Alice")!
        XCTAssertNil(DeepLinkHandler.resolve(url))
    }

    func testFriendWrongPathReturnsNil() {
        let url = URL(string: "podcastr://friend/something-else?npub=npub1abc")!
        XCTAssertNil(DeepLinkHandler.resolve(url))
    }

    // MARK: - Episode

    func testResolvesEpisodeWithValidUUID() {
        let id = UUID()
        let url = URL(string: "podcastr://episode/\(id.uuidString)")!
        guard case .episode(let parsed) = DeepLinkHandler.resolve(url) else {
            XCTFail("Expected .episode"); return
        }
        XCTAssertEqual(parsed, id)
    }

    func testEpisodeWithInvalidUUIDReturnsNil() {
        let url = URL(string: "podcastr://episode/not-a-uuid")!
        XCTAssertNil(DeepLinkHandler.resolve(url))
    }

    func testEpisodeWithoutPathComponentReturnsNil() {
        let url = URL(string: "podcastr://episode")!
        XCTAssertNil(DeepLinkHandler.resolve(url))
    }

    // MARK: - Subscription

    func testResolvesSubscriptionWithValidUUID() {
        let id = UUID()
        let url = URL(string: "podcastr://subscription/\(id.uuidString)")!
        guard case .subscription(let parsed) = DeepLinkHandler.resolve(url) else {
            XCTFail("Expected .subscription"); return
        }
        XCTAssertEqual(parsed, id)
    }

    func testSubscriptionWithInvalidUUIDReturnsNil() {
        let url = URL(string: "podcastr://subscription/not-a-uuid")!
        XCTAssertNil(DeepLinkHandler.resolve(url))
    }

    // MARK: - Failure surface

    func testRejectsForeignScheme() {
        let url = URL(string: "https://settings")!
        XCTAssertNil(DeepLinkHandler.resolve(url))
    }

    func testRejectsUnknownHost() {
        let url = URL(string: "podcastr://nope")!
        XCTAssertNil(DeepLinkHandler.resolve(url))
    }

    // MARK: - friendInviteURL builder

    func testFriendInviteURLIncludesNameWhenProvided() throws {
        let url = try XCTUnwrap(DeepLinkHandler.friendInviteURL(npub: "npub1abc", name: "Alice"))

        XCTAssertEqual(url.scheme, "podcastr")
        XCTAssertEqual(url.host, "friend")
        XCTAssertEqual(url.path, "/add")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "npub" })?.value, "npub1abc")
        XCTAssertEqual(items.first(where: { $0.name == "name" })?.value, "Alice")
    }

    func testFriendInviteURLOmitsEmptyName() throws {
        let url = try XCTUnwrap(DeepLinkHandler.friendInviteURL(npub: "npub1abc", name: ""))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertNil(items.first(where: { $0.name == "name" }),
                     "Empty name should not surface as ?name= in the invite URL")
    }

    func testFriendInviteURLOmitsNilName() throws {
        let url = try XCTUnwrap(DeepLinkHandler.friendInviteURL(npub: "npub1abc", name: nil))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertNil(items.first(where: { $0.name == "name" }))
    }

    // MARK: - Round-trip

    func testInviteURLRoundTripsThroughResolver() throws {
        let url = try XCTUnwrap(DeepLinkHandler.friendInviteURL(npub: "npub1abc", name: "Alice"))
        guard case .addFriend(let npub, let name) = DeepLinkHandler.resolve(url) else {
            XCTFail("Expected the builder's URL to parse back via resolve()"); return
        }
        XCTAssertEqual(npub, "npub1abc")
        XCTAssertEqual(name, "Alice")
    }
}
