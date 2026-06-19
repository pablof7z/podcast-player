import XCTest

/// Simulator UI coverage for `download-episode` and `delete-download-reclaims`
/// scenarios (#547).
///
/// NETWORK NOTE: The seeded episode's enclosure URL points to the NPR CDN
/// (a live remote file). In CI the simulator may or may not have network
/// access. `testDownloadEpisode` taps Download and waits up to 60s for
/// completion; if the download does not complete (network unavailable) the
/// test fails with a clear message pointing to the seeder's local MP3 path.
///
/// A follow-up option for reliability: extend UITestSeeder to write a local
/// HTTP server endpoint (or use the bundled test-episode.mp3 as the enclosure
/// URL via a file:// URL) so the download completes without network access.
/// Track in docs/BACKLOG.md under #547.
final class DownloadUITests: XCTestCase {

    override func setUp() { super.setUp(); continueAfterFailure = true }

    override func tearDown() {
        XCUIApplication(bundleIdentifier: App.bundleID).terminate()
        super.tearDown()
    }

    // MARK: - download-episode

    /// Open episode detail, tap Download, wait for the "Downloaded" label.
    /// Then navigate away and back to confirm state persists within the session.
    func testDownloadEpisode() throws {
        let app = App.make()
        XCTAssertTrue(launchApp(app)); sleep(1)
        guard openFirstPodcastFromHome(app), openFirstEpisodeFromShow(app) else {
            XCTFail("download: could not reach episode detail"); return
        }
        sleep(2)
        snap(app, "dl-01-episode-detail")
        dumpTree(app, "dl-01-tree")

        // The download pill is in EpisodeDetailHeroView. Its initial state
        // should be "Download" (not_downloaded) since the seed sets
        // "download_state": {"state": "not_downloaded"}.
        // Note: if a prior test run downloaded the episode and the local
        // file survived, the pill may already read "Downloaded". Accept that.
        let downloadBtn = app.buttons.matching(
            NSPredicate(format: "label == 'Download'")).firstMatch
        let alreadyDownloadedLabel = app.staticTexts.matching(
            NSPredicate(format: "label == 'Downloaded'")).firstMatch

        if alreadyDownloadedLabel.waitForExistence(timeout: 3) {
            // Episode was already downloaded (prior test run's local file
            // is still present). Skip the download step.
            snap(app, "dl-ALREADY-DOWNLOADED")
            // Proceed to the delete test (testDeleteDownloadReclaims) below
            // which will exercise the Remove Download path.
            return
        }

        guard downloadBtn.waitForExistence(timeout: 5) else {
            snap(app, "dl-NODOWNLOAD-BTN")
            dumpTree(app, "dl-NODOWNLOAD-tree")
            XCTFail(
                "FAIL download-episode: 'Download' button not found on episode detail" +
                " — EpisodeDetailHeroView.downloadPill may not be rendering for notDownloaded state"
            )
            return
        }

        downloadBtn.tap()
        snap(app, "dl-02-downloading")

        // Wait up to 60s for the download to complete (network-dependent).
        // A progress label "Downloading X%" appears while downloading.
        let downloadedLabel = app.staticTexts.matching(
            NSPredicate(format: "label == 'Downloaded'")).firstMatch

        // Poll for either "Downloaded" or a downloading-in-progress label.
        // NSPredicate created inline at each use to satisfy Swift 6 region-based
        // isolation checks (non-Sendable NSPredicate cannot be shared).
        let progressBtn = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Downloading'")).firstMatch
        let progressText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Downloading'")).firstMatch
        let downloadStarted = progressBtn.waitForExistence(timeout: 10)
            || progressText.waitForExistence(timeout: 2)
            || downloadedLabel.waitForExistence(timeout: 2)

        snap(app, "dl-03-download-progress")

        let downloadCompleted = downloadedLabel.waitForExistence(timeout: 60)
        snap(app, "dl-04-download-result")
        dumpTree(app, "dl-04-tree")

        XCTAssertTrue(
            downloadCompleted,
            "FAIL download-episode: 'Downloaded' label did not appear within 60s of tapping Download. " +
            "downloadStarted=\(downloadStarted). " +
            "Likely cause: simulator has no network access to the NPR CDN enclosure URL. " +
            "FOLLOW-UP: extend UITestSeeder with a local HTTP endpoint for the enclosure URL " +
            "so downloads complete without external network access (see #547 in BACKLOG)."
        )

        // Navigate away and back; the Download state must persist.
        let backBtn = app.navigationBars.buttons.element(boundBy: 0)
        if backBtn.waitForExistence(timeout: 3), backBtn.isHittable { backBtn.tap(); sleep(1) }
        guard openFirstEpisodeFromShow(app) else { return }
        sleep(2)
        snap(app, "dl-05-after-nav-back")

        let stillDownloaded = app.staticTexts.matching(
            NSPredicate(format: "label == 'Downloaded'")).firstMatch
        XCTAssertTrue(
            stillDownloaded.waitForExistence(timeout: 5),
            "FAIL download-episode: 'Downloaded' label absent after navigating back — download state was not persisted"
        )
    }

    // MARK: - delete-download-reclaims

    /// If the episode is downloaded, open Episode options → "Remove download"
    /// → confirm → assert "Download" button returns (UI reflects kernel deletion).
    ///
    /// This test is independent — it will remove the download if present,
    /// regardless of whether testDownloadEpisode ran first.
    func testDeleteDownloadReclaims() throws {
        let app = App.make()
        XCTAssertTrue(launchApp(app)); sleep(1)
        guard openFirstPodcastFromHome(app), openFirstEpisodeFromShow(app) else {
            XCTFail("delete-dl: could not reach episode detail"); return
        }
        sleep(2)
        snap(app, "dldel-01-detail")

        // Check if the episode is downloaded.
        let downloadedLabel = app.staticTexts.matching(
            NSPredicate(format: "label == 'Downloaded'")).firstMatch
        guard downloadedLabel.waitForExistence(timeout: 5) else {
            // Not downloaded — test cannot prove deletion reclaims space.
            // This is expected if testDownloadEpisode skipped or failed.
            throw XCTSkip(
                "delete-download-reclaims (#547): episode is not in Downloaded state. " +
                "Run testDownloadEpisode first (requires network), or extend the seeder " +
                "to seed the episode in .downloaded state so this test runs independently."
            )
        }

        // Open the Episode options menu (ellipsis button, accessibilityLabel "Episode options").
        let epOptions = app.buttons["Episode options"]
        guard epOptions.waitForExistence(timeout: 5) else {
            snap(app, "dldel-NOOPTIONS")
            dumpTree(app, "dldel-NOOPTIONS-tree")
            XCTFail("delete-dl: 'Episode options' button not found in episode detail navigation bar")
            return
        }
        epOptions.tap(); sleep(1)
        snap(app, "dldel-02-options-menu")

        // Tap "Remove download".
        let removeBtn = app.buttons["Remove download"]
        guard removeBtn.waitForExistence(timeout: 4) else {
            snap(app, "dldel-NOREMOVE")
            dumpTree(app, "dldel-NOREMOVE-tree")
            XCTFail("delete-dl: 'Remove download' not found in Episode options menu — expected for .downloaded state")
            return
        }
        removeBtn.tap(); sleep(1)
        snap(app, "dldel-03-confirm-dialog")

        // Confirm the deletion in the alert.
        let confirmRemove = app.buttons["Remove"]
        if confirmRemove.waitForExistence(timeout: 3) {
            confirmRemove.tap(); sleep(2)
        }
        snap(app, "dldel-04-after-remove")
        dumpTree(app, "dldel-04-tree")

        // Assert: "Download" button is back (not_downloaded state returned).
        let downloadBtnBack = app.buttons.matching(
            NSPredicate(format: "label == 'Download'")).firstMatch
        XCTAssertTrue(
            downloadBtnBack.waitForExistence(timeout: 5),
            "FAIL delete-download-reclaims: 'Download' button did not reappear after removing download" +
            " — kernel may not have sent the download_state update back to the UI"
        )
    }
}
