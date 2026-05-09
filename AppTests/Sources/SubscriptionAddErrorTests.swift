import XCTest
@testable import Podcastr

/// Coverage for `SubscriptionService.AddError.errorDescription`.
///
/// These messages are user-facing — they surface inside `AddByURLForm`,
/// `OPMLImportSheet`, and `DiscoverSearchForm` whenever a subscribe call
/// fails. Tests lock the localized copy so a refactor can't silently
/// regress the string a user reads when they paste a typo or hit a
/// network blip.
@MainActor
final class SubscriptionAddErrorTests: XCTestCase {

    func testInvalidURLMessage() {
        let error = SubscriptionService.AddError.invalidURL
        XCTAssertEqual(
            error.errorDescription,
            "That doesn't look like a valid feed URL."
        )
    }

    func testAlreadySubscribedIncludesShowTitle() {
        let error = SubscriptionService.AddError.alreadySubscribed(title: "The Daily")
        XCTAssertEqual(
            error.errorDescription,
            "You're already subscribed to The Daily."
        )
    }

    func testAlreadySubscribedHandlesShowsWithSpecialCharacters() {
        // Title may contain quotes / ampersands / em-dashes — the
        // localized message must pass them through verbatim, not strip.
        let error = SubscriptionService.AddError.alreadySubscribed(title: "AT&T \"Tech\" — News")
        XCTAssertEqual(
            error.errorDescription,
            "You're already subscribed to AT&T \"Tech\" — News."
        )
    }

    func testTransportIncludesUnderlyingMessage() {
        let error = SubscriptionService.AddError.transport("network unreachable")
        XCTAssertEqual(
            error.errorDescription,
            "Couldn't reach the feed: network unreachable"
        )
    }

    func testHTTPStatusIncludesCode() {
        let error = SubscriptionService.AddError.http(404)
        XCTAssertEqual(
            error.errorDescription,
            "The feed server returned HTTP 404."
        )
    }

    func testHTTPStatus500() {
        let error = SubscriptionService.AddError.http(500)
        XCTAssertEqual(
            error.errorDescription,
            "The feed server returned HTTP 500."
        )
    }

    func testParseIncludesUnderlyingMessage() {
        let error = SubscriptionService.AddError.parse("malformed XML at line 42")
        XCTAssertEqual(
            error.errorDescription,
            "Couldn't read this feed: malformed XML at line 42"
        )
    }

    // MARK: - Equatable contract

    func testInvalidURLEqualsItself() {
        XCTAssertEqual(SubscriptionService.AddError.invalidURL, .invalidURL)
    }

    func testAlreadySubscribedEqualsByTitle() {
        XCTAssertEqual(
            SubscriptionService.AddError.alreadySubscribed(title: "Show"),
            .alreadySubscribed(title: "Show")
        )
        XCTAssertNotEqual(
            SubscriptionService.AddError.alreadySubscribed(title: "Show A"),
            .alreadySubscribed(title: "Show B")
        )
    }

    func testHTTPEqualsByStatusCode() {
        XCTAssertEqual(
            SubscriptionService.AddError.http(404),
            .http(404)
        )
        XCTAssertNotEqual(
            SubscriptionService.AddError.http(404),
            .http(500)
        )
    }

    func testTransportAndParseAreDistinct() {
        // Both wrap a String message but they're separate enum cases —
        // a transport error must never compare equal to a parse error.
        XCTAssertNotEqual(
            SubscriptionService.AddError.transport("oops"),
            .parse("oops")
        )
    }
}
