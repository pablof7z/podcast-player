import XCTest

/// Simulator UI coverage for `chapter-list-renders` and `chapter-tap-seeks`
/// scenarios (#547).
///
/// SEEDER LIMITATION: the UITestSeeder writes `podcasts.json` with no chapter
/// data — the kernel's chapter store is populated separately (via
/// `podcast.fetch_chapters` or `podcast.chapters.compile`), and neither path
/// is triggered by the seed alone on a cold launch. Chapters are therefore
/// not present in the seeded episode on a standard `--UITestSeed` launch.
///
/// These tests detect whether chapters are available after the player opens
/// and skip (XCTSkip) with a clear message if none are found. The
/// accessibility identifiers (`chapter-<uuid>`) are already added to the
/// production `PlayerChaptersScrollView` (see #547) so the tests will run
/// fully once a `--UITestSeedChapters` seeder path is added or a real
/// chapter-capable episode is present in the device library.
///
/// FOLLOW-UP REQUIRED: Extend UITestSeeder with a `--UITestSeedChapters` flag
/// that writes chapter data in a format the kernel accepts (check if the kernel
/// supports a `chapters` field in `podcasts.json` or needs a separate file).
/// Track in docs/BACKLOG.md under #547 follow-up.
final class PlayerChaptersUITests: XCTestCase {

    override func setUp() { super.setUp(); continueAfterFailure = true }

    override func tearDown() {
        XCUIApplication(bundleIdentifier: App.bundleID).terminate()
        super.tearDown()
    }

    // MARK: - chapter-list-renders

    func testChapterListRenders() throws {
        let app = App.make()
        XCTAssertTrue(launchApp(app)); sleep(1)
        guard openFirstPodcastFromHome(app), openFirstEpisodeFromShow(app) else {
            XCTFail("chapters: could not reach episode detail"); return
        }

        // Start playback and open the full player.
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 8), "no Play")
        app.buttons["Play"].tap(); sleep(2)
        guard openFullPlayerFromMiniPlayer(app) else {
            XCTFail("chapters: mini-player did not appear"); return
        }
        sleep(2)
        snap(app, "chapters-01-full-player")
        dumpTree(app, "chapters-01-tree")

        // Detect whether any chapter row (identifier: "chapter-<uuid>") is visible.
        // Chapter rows only render when the kernel has populated chapter data for the
        // playing episode. With the default seed, there are no chapters.
        let chapterRowPred = NSPredicate(format: "identifier BEGINSWITH 'chapter-'")
        let firstChapterRow = app.buttons.matching(chapterRowPred).firstMatch
        let chaptersPresent = firstChapterRow.waitForExistence(timeout: 5)

        snap(app, "chapters-02-chapter-rail")

        guard chaptersPresent else {
            // XCTSkip rather than XCTFail: the scenario is blocked by the
            // seeder gap (no chapter data), not by a production code bug.
            // Once --UITestSeedChapters is implemented this skip should be
            // removed and the assertions below should run unconditionally.
            throw XCTSkip(
                "chapter-list-renders (#547): no chapter rows (identifier 'chapter-*') found in the full player. " +
                "The seeder does not currently write chapter data — the kernel populates chapters " +
                "via fetch_chapters/compile which is not triggered by --UITestSeed. " +
                "FOLLOW-UP: add --UITestSeedChapters to UITestSeeder.swift so these tests run deterministically."
            )
        }

        // Chapter rows are present — assert the rail is accessible.
        XCTAssertTrue(
            chaptersPresent,
            "FAIL chapter-list-renders: PlayerChaptersScrollView renders no chapter-* rows despite " +
            "chapter data being available — check accessibilityIdentifier on chapterRow button"
        )

        // Verify at least two chapters are visible (a well-formed episode has multiple).
        let allChapterRows = app.buttons.matching(chapterRowPred)
        let chapterCount = allChapterRows.count
        XCTAssertGreaterThan(
            chapterCount, 1,
            "FAIL chapter-list-renders: only \(chapterCount) chapter row found — expected multiple for a chaptered episode"
        )
        snap(app, "chapters-03-rows-present")
    }

    // MARK: - chapter-tap-seeks

    func testChapterTapSeeks() throws {
        let app = App.make()
        XCTAssertTrue(launchApp(app)); sleep(1)
        guard openFirstPodcastFromHome(app), openFirstEpisodeFromShow(app) else {
            XCTFail("chapter-seek: could not reach episode detail"); return
        }

        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 8), "no Play")
        app.buttons["Play"].tap(); sleep(2)
        guard openFullPlayerFromMiniPlayer(app) else {
            XCTFail("chapter-seek: mini-player did not appear"); return
        }
        sleep(2)
        snap(app, "chseek-01-full-player")

        let chapterRowPred = NSPredicate(format: "identifier BEGINSWITH 'chapter-'")
        let allChapterRows = app.buttons.matching(chapterRowPred)
        let firstChapterRow = allChapterRows.element(boundBy: 0)
        guard firstChapterRow.waitForExistence(timeout: 5) else {
            throw XCTSkip(
                "chapter-tap-seeks (#547): no chapter rows found in the full player (same seeder gap as " +
                "testChapterListRenders). FOLLOW-UP: add --UITestSeedChapters to UITestSeeder.swift."
            )
        }

        // Capture timecodes before tapping.
        let timesBefore = currentTimeLabels(app)
        snap(app, "chseek-02-before-tap")

        // Tap the SECOND chapter row (index 1). Tapping chapter 0 (at 0:00)
        // would seek to position 0 which might not change the displayed timecode.
        // If there's only one chapter, tap chapter 0 anyway (still verifies the
        // accessibility action fires without crashing).
        let rowToTap = allChapterRows.count > 1
            ? allChapterRows.element(boundBy: 1)
            : firstChapterRow
        robustTap(rowToTap); sleep(2)
        snap(app, "chseek-03-after-tap")

        let timesAfter = currentTimeLabels(app)

        // The playhead must have moved. Accept either a different timecode label
        // OR the absence of the timecode we had before (seek to a later position
        // can temporarily clear the label before it updates).
        XCTAssertNotEqual(
            timesBefore, timesAfter,
            "FAIL chapter-tap-seeks: time labels unchanged after tapping chapter row — " +
            "navigationalSeek may not have fired or the chapter row is not hittable"
        )
    }

    // MARK: - Helpers

    private func currentTimeLabels(_ app: XCUIApplication) -> [String] {
        let re = try? NSRegularExpression(pattern: "^-?\\d{1,2}:\\d{2}(:\\d{2})?$")
        return app.staticTexts.allElementsBoundByIndex.compactMap { el in
            let l = el.label
            guard let re, re.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)) != nil else { return nil }
            return l
        }
    }
}
