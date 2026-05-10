import XCTest
@testable import Podcastr

/// Coverage for `ShowDetailView.descriptionNeedsToggle` — the
/// approximate "should we show a Show More button?" check on the show
/// detail's About blurb. The collapse-by-default + toggle path exists
/// because many feeds ship multi-paragraph descriptions that swamp the
/// surface; the threshold needs to (a) not appear for short single-line
/// blurbs and (b) appear for the long or multi-paragraph cases.
final class ShowDetailDescriptionToggleTests: XCTestCase {

    func testNoToggleForShortSingleParagraph() {
        let body = "A weekly podcast about coffee."
        XCTAssertFalse(ShowDetailView.descriptionNeedsToggle(body))
    }

    func testToggleAppearsForLongSingleParagraph() {
        // > 240 chars triggers the toggle even without paragraph breaks.
        let body = String(repeating: "Long form interviews and conversations. ", count: 8)
        XCTAssertTrue(ShowDetailView.descriptionNeedsToggle(body))
    }

    func testToggleAppearsForMultiParagraph() {
        // Multiple blocks — what `EpisodeShowNotesFormatter.collapseWhitespace`
        // produces — should always trigger the toggle even when each block
        // is brief, because vertical density adds up.
        let body = "First short blurb.\n\nSecond short blurb."
        XCTAssertTrue(ShowDetailView.descriptionNeedsToggle(body))
    }

    func testNoToggleForExactlyAtThreshold() {
        // 240-char single paragraph sits at the boundary; should NOT toggle
        // (the check is strictly greater than 240).
        let body = String(repeating: "x", count: 240)
        XCTAssertFalse(ShowDetailView.descriptionNeedsToggle(body))
    }

    func testToggleForJustOverThreshold() {
        let body = String(repeating: "x", count: 241)
        XCTAssertTrue(ShowDetailView.descriptionNeedsToggle(body))
    }
}
