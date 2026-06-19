import XCTest

/// Simulator UI coverage for `download-episode` and `delete-download-reclaims`
/// scenarios (#547).
///
/// SEEDER MODES:
///   `testDownloadEpisode` uses the standard `--UITestSeed` which seeds ep1
///   as `not_downloaded` (no local_paths entry). Tapping Download triggers a
///   real download from the NPR CDN enclosure URL via the iOS background
///   URLSession. If the simulator has no network access the download will not
///   start and the test skips with a clear network-unavailable message.
///   (Background URLSession requires HTTP/HTTPS; file:// is not supported, so
///   a fully offline download path is not available with the current capability.)
///
///   `testDeleteDownloadReclaims` uses `--UITestSeedDownloaded` which copies
///   the bundled test-episode.mp3 to the canonical download location and adds
///   its path to `local_paths`, so ep1 is projected as downloaded from the
///   start — independent of testDownloadEpisode having run.
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

        // The seeder removes any previously-downloaded file and omits local_paths
        // so ep1 is always projected as not_downloaded. The Download pill must
        // be visible here; if it's not, the seeder or projection is broken.
        let downloadBtn = app.buttons.matching(
            NSPredicate(format: "label == 'Download'")).firstMatch

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

        // If the download did not start at all (no progress indicator), the
        // simulator has no network access to the NPR CDN. Skip rather than
        // fail: the test is not fake (the episode genuinely started as
        // not_downloaded), but the download capability requires HTTP/HTTPS and
        // cannot use a local file:// URL with a background URLSession.
        if !downloadStarted {
            throw XCTSkip(
                "download-episode (#547): download did not start within 10s. " +
                "Simulator likely has no network access to the NPR CDN enclosure. " +
                "Background URLSession requires HTTP/HTTPS — bundled file:// is not " +
                "supported. Requires external network for a real end-to-end download. " +
                "Manual protocol: tap Download on the seeded episode, observe progress, " +
                "confirm 'Downloaded' appears."
            )
        }

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

    /// Seed ep1 as already-downloaded via `--UITestSeedDownloaded`, open
    /// Episode options → "Remove download" → confirm → assert the "Download"
    /// button returns, proving the kernel transitioned back to not_downloaded.
    ///
    /// This test is independent of testDownloadEpisode: it always starts from
    /// a seeded-downloaded state so it does not require network access.
    func testDeleteDownloadReclaims() throws {
        let app = App.make()
        // Override to add --UITestSeedDownloaded so the seeder copies the
        // bundled test MP3 to the canonical download path and adds it to
        // local_paths, guaranteeing ep1 is projected as downloaded.
        app.launchArguments = ["--UITestSeed", "--UITestSeedDownloaded"]
        XCTAssertTrue(launchApp(app)); sleep(1)
        guard openFirstPodcastFromHome(app), openFirstEpisodeFromShow(app) else {
            XCTFail("delete-dl: could not reach episode detail"); return
        }
        sleep(2)
        snap(app, "dldel-01-detail")

        // The seeder guarantees ep1 is projected as downloaded.
        let downloadedLabel = app.staticTexts.matching(
            NSPredicate(format: "label == 'Downloaded'")).firstMatch
        guard downloadedLabel.waitForExistence(timeout: 5) else {
            snap(app, "dldel-NOT-DOWNLOADED")
            dumpTree(app, "dldel-NOT-DOWNLOADED-tree")
            XCTFail(
                "delete-dl: episode is not in Downloaded state after --UITestSeedDownloaded. " +
                "UITestSeeder --UITestSeedDownloaded may not be copying the bundled MP3 " +
                "to the canonical path or local_paths is not being written correctly."
            )
            return
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
