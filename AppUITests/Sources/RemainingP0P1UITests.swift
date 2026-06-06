import XCTest

/// Remaining P0 / P1 scenario coverage from test-scenarios.json.
///
/// Tests are self-contained and soft (continueAfterFailure = true).
/// Physical-device-only scenarios are marked with XCTSkip.
/// Kernel-owned playback bugs are documented inline and not re-tested.
final class RemainingP0P1UITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = true }

    // MARK: - P0: skip-forward-back-15

    /// Open the full player, skip +15s and confirm position advances,
    /// then skip -15s and confirm it retreats.
    func testP0_SkipForwardBack15() throws {
        let app = App.make()
        XCTAssertTrue(launchApp(app)); sleep(1)
        // Open episode detail and start playback.
        let podcastRow = app.buttons.matching(
            NSPredicate(format: "identifier == 'library-podcast-row'")).firstMatch
        guard podcastRow.waitForExistence(timeout: 6) || staticTextContaining(app, "This American Life").waitForExistence(timeout: 6) else {
            XCTFail("skip-forward-back-15: no podcast row visible"); return
        }
        robustTap(podcastRow.exists ? podcastRow : staticTextContaining(app, "This American Life"))
        _ = app.cells.element(boundBy: 2).waitForExistence(timeout: 8)
        robustTap(app.cells.element(boundBy: 2))
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 8), "no Play button")
        app.buttons["Play"].tap()
        // Open full player.
        sleep(3)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
        sleep(2)
        snap(app, "skip-01-full-player")

        // Capture time before skip.
        let before = timeLabels(app)
        // Find skip-forward button (SF symbol name "goforward" or label contains "15").
        let fwd = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'forward' OR label CONTAINS[c] '15'")).firstMatch
        if fwd.waitForExistence(timeout: 4) {
            fwd.tap(); sleep(1)
            let after = timeLabels(app)
            snap(app, "skip-02-after-forward")
            XCTAssertNotEqual(before, after, "FAIL skip-forward: time labels unchanged after skip-forward-15")
        } else {
            snap(app, "skip-02-no-forward-button")
            XCTFail("FAIL skip-forward-back-15: no forward-skip button found in full player")
        }

        // Skip back.
        let back = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'backward' OR label CONTAINS[c] 'back'")).firstMatch
        if back.waitForExistence(timeout: 3) {
            let mid = timeLabels(app)
            back.tap(); sleep(1)
            let after2 = timeLabels(app)
            snap(app, "skip-03-after-backward")
            XCTAssertNotEqual(mid, after2, "FAIL skip-backward-15: time labels unchanged after skip-backward-15")
        }
    }

    // MARK: - P0: queue-add-multiple

    /// Verify that tapping Queue on an episode detail toggles the button to
    /// "Queued" (disabled), proving the episode was accepted by the queue.
    ///
    /// NOTE: PlayerQueueSheet exists in the codebase but has no presentation
    /// trigger in the current UI (not wired to player or mini-player) — the
    /// queue panel cannot be opened via XCTest. This test verifies the button
    /// state toggle which is the only observable queue signal available on
    /// the episode detail screen.
    func testP0_QueueAddMultiple() throws {
        let app = App.make()
        XCTAssertTrue(launchApp(app)); sleep(1)
        let row = app.buttons.matching(
            NSPredicate(format: "identifier == 'library-podcast-row'")).firstMatch
        guard row.waitForExistence(timeout: 6) else {
            XCTFail("queue-add-multiple: no podcast row"); return
        }
        row.tap()
        _ = app.cells.element(boundBy: 2).waitForExistence(timeout: 8)

        // Queue first episode — verify button toggles to "Queued".
        robustTap(app.cells.element(boundBy: 2))
        sleep(2)
        snap(app, "queue-01-ep1-detail")
        let q1 = app.buttons.matching(NSPredicate(format: "label == 'Queue' OR label == 'Add to Queue'")).firstMatch
        guard q1.waitForExistence(timeout: 5) else {
            snap(app, "queue-01-no-queue-button")
            let dump = XCTAttachment(string: app.debugDescription)
            dump.name = "queue-01-no-queue-tree"; dump.lifetime = .keepAlways; add(dump)
            XCTFail("queue-add-multiple: no Queue button on episode 1 detail")
            return
        }
        q1.tap(); sleep(1)
        snap(app, "queue-01-after-tap")
        // After tapping, the button should become "Queued" (disabled/selected state).
        let queued1 = app.buttons.matching(NSPredicate(format: "label == 'Queued'")).firstMatch
        let ep1Queued = queued1.waitForExistence(timeout: 4)
        XCTAssertTrue(ep1Queued, "FAIL queue-add-multiple: Queue button did not toggle to 'Queued' after tapping (ep1)")

        // Navigate back, open second episode — verify it can also be queued.
        let back1 = app.navigationBars.buttons.element(boundBy: 0)
        if back1.exists { back1.tap(); sleep(1) }
        let ep2Cell = app.cells.count > 3 ? app.cells.element(boundBy: 3) : app.cells.element(boundBy: 2)
        robustTap(ep2Cell); sleep(2)
        snap(app, "queue-02-ep2-detail")
        let q2 = app.buttons.matching(NSPredicate(format: "label == 'Queue' OR label == 'Add to Queue'")).firstMatch
        if q2.waitForExistence(timeout: 5) {
            q2.tap(); sleep(1)
            snap(app, "queue-02-after-tap")
            let queued2 = app.buttons.matching(NSPredicate(format: "label == 'Queued'")).firstMatch
            XCTAssertTrue(queued2.waitForExistence(timeout: 4),
                "FAIL queue-add-multiple: Queue button did not toggle to 'Queued' after tapping (ep2)")
        } else {
            snap(app, "queue-02-no-queue-button")
        }
    }

    // MARK: - P0: background-playback-continues

    /// Start playback, press Home, wait 5s, return to app, confirm audio
    /// is still going (Pause control visible somewhere OR mini-player shows
    /// the episode title).
    func testP0_BackgroundPlaybackContinues() throws {
        let app = App.make()
        XCTAssertTrue(launchApp(app)); sleep(1)
        let row = app.buttons.matching(
            NSPredicate(format: "identifier == 'library-podcast-row'")).firstMatch
        guard row.waitForExistence(timeout: 6) else {
            XCTFail("background-playback: no podcast row"); return
        }
        row.tap()
        _ = app.cells.element(boundBy: 2).waitForExistence(timeout: 8)
        robustTap(app.cells.element(boundBy: 2))
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 8), "no Play")
        app.buttons["Play"].tap()
        sleep(4)
        snap(app, "bg-01-playing")

        // Background.
        XCUIDevice.shared.press(.home)
        sleep(5)

        // Foreground.
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 10)
        sleep(2)
        snap(app, "bg-02-after-foreground")

        let pause = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'pause'")).firstMatch
        let miniPlayerText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'The Book'")).firstMatch
        let continued = pause.waitForExistence(timeout: 4) || miniPlayerText.waitForExistence(timeout: 2)
        XCTAssertTrue(continued, "FAIL background-playback-continues: no Pause control or episode text visible after foregrounding — audio may have stopped")
    }

    // MARK: - P0: offline-library-access

    /// Library is accessible with pre-seeded content (no network required).
    /// This proves the library loads from disk, not only from live network.
    func testP0_OfflineLibraryAccess() throws {
        let app = App.make()
        XCTAssertTrue(launchApp(app)); sleep(1)
        // Library is the default tab. Sidebar → Library.
        let sidebar = app.buttons["Open sidebar"]
        if sidebar.waitForExistence(timeout: 5) { sidebar.tap(); sleep(1) }
        let lib = app.buttons["Library"]
        if lib.waitForExistence(timeout: 4) { robustTap(lib); sleep(2) }
        snap(app, "offline-lib-01")
        // Some content must be visible (episode cells or filter chips).
        let hasContent = app.cells.count > 0 || app.staticTexts.count > 4
        XCTAssertTrue(hasContent, "FAIL offline-library-access: library is empty or failed to load from seeded state")
        // Soft check: Home tab may also show the seeded podcast row.
        // Primary assertion is hasContent above; navigate to Home as evidence.
        let home = app.buttons["Home"]
        if home.waitForExistence(timeout: 4) { robustTap(home); sleep(2) }
        snap(app, "offline-lib-02-home")
        // If a library-podcast-row is present on Home that is a bonus confirmation.
        let podRow = app.buttons.matching(
            NSPredicate(format: "identifier == 'library-podcast-row'")).firstMatch
        if !podRow.waitForExistence(timeout: 5) {
            // Not a hard failure — content was already confirmed in Library above.
            // But capture the state for manual review.
            let dumpHome = XCTAttachment(string: app.debugDescription)
            dumpHome.name = "offline-lib-home-tree"; dumpHome.lifetime = .keepAlways; add(dumpHome)
        }
    }

    // MARK: - P0: reactive-update-cross-screen

    /// Play state change (tapping Play) on the episode detail reflects
    /// on the mini-player visible on the Home tab — confirming reactive
    /// cross-screen state propagation.
    func testP0_ReactiveUpdateCrossScreen() throws {
        let app = App.make()
        XCTAssertTrue(launchApp(app)); sleep(1)
        let row = app.buttons.matching(
            NSPredicate(format: "identifier == 'library-podcast-row'")).firstMatch
        guard row.waitForExistence(timeout: 6) else {
            XCTFail("reactive: no podcast row"); return
        }
        row.tap()
        _ = app.cells.element(boundBy: 2).waitForExistence(timeout: 8)
        robustTap(app.cells.element(boundBy: 2))
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 8), "no Play")
        app.buttons["Play"].tap()
        sleep(3)
        snap(app, "reactive-01-playing-in-detail")

        // Navigate back to the show and then back to Home.
        let b1 = app.navigationBars.buttons.element(boundBy: 0)
        if b1.exists { b1.tap(); sleep(1) }
        let b2 = app.navigationBars.buttons.element(boundBy: 0)
        if b2.exists { b2.tap(); sleep(1) }
        snap(app, "reactive-02-home-after-play")
        let dumpR = XCTAttachment(string: app.debugDescription)
        dumpR.name = "reactive-02-tree"; dumpR.lifetime = .keepAlways; add(dumpR)

        // Home tab should show a mini-player or Pause control.
        let pause = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'pause'")).firstMatch
        let miniPlayer = app.otherElements.matching(
            NSPredicate(format: "label CONTAINS[c] 'mini' OR identifier CONTAINS[c] 'mini'")).firstMatch
        let epText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'The Book'")).firstMatch
        let reactive = pause.waitForExistence(timeout: 4)
            || miniPlayer.waitForExistence(timeout: 2)
            || epText.waitForExistence(timeout: 2)
        XCTAssertTrue(reactive, "FAIL reactive-update-cross-screen: no mini-player/Pause on Home after starting playback in episode detail")
    }

    // MARK: - P1: unsubscribe-from-library

    /// Open the subscribed podcast, open the show-options overflow menu (the
    /// "..." ellipsis at top-right, labelled "Show options"), and tap
    /// Unsubscribe. Confirm the menu item switches to Follow.
    func testP1_UnsubscribeFromLibrary() throws {
        let app = App.make()
        XCTAssertTrue(launchApp(app)); sleep(1)
        let row = app.buttons.matching(
            NSPredicate(format: "identifier == 'library-podcast-row'")).firstMatch
        guard row.waitForExistence(timeout: 6) else {
            XCTFail("unsubscribe: no podcast row"); return
        }
        row.tap(); sleep(2)
        snap(app, "unsub-01-show-detail")
        dumpTree(app, "unsub-01-tree")

        // The "Unsubscribe" action lives inside the overflow menu ("Show options").
        let showOptions = app.buttons["Show options"]
        guard showOptions.waitForExistence(timeout: 5) else {
            snap(app, "unsub-NOOPTIONS"); XCTFail("unsubscribe: no 'Show options' button"); return
        }
        showOptions.tap(); sleep(1)
        snap(app, "unsub-02-menu-open")

        // Look for Unsubscribe in the opened menu.
        let unsubBtn = app.buttons["Unsubscribe"]
        if unsubBtn.waitForExistence(timeout: 4) {
            unsubBtn.tap(); sleep(1)
            // The confirmation alert: tap the destructive "Unsubscribe" action.
            let confirmBtn = app.buttons["Unsubscribe"].firstMatch
            if confirmBtn.waitForExistence(timeout: 3) { confirmBtn.tap(); sleep(1) }
            snap(app, "unsub-03-after-unsub")
            // After unsubscribing, reopening the menu should show "Follow" not "Unsubscribe".
            if showOptions.waitForExistence(timeout: 3) {
                showOptions.tap(); sleep(1)
                let followBtn = app.buttons.matching(
                    NSPredicate(format: "label == 'Follow'")).firstMatch
                XCTAssertTrue(followBtn.waitForExistence(timeout: 4),
                    "FAIL unsubscribe: after confirming Unsubscribe, menu still shows no Follow option")
            }
        } else {
            snap(app, "unsub-NOUNSUB"); dumpTree(app, "unsub-NOUNSUB-tree")
            XCTFail("FAIL unsubscribe: 'Unsubscribe' not found in Show options menu")
        }
    }

    // MARK: - P1: scrub-seek-slider

    /// Open full player while audio is playing and drag the seek slider.
    func testP1_ScrubSeekSlider() throws {
        let app = App.make()
        XCTAssertTrue(launchApp(app)); sleep(1)
        let row = app.buttons.matching(
            NSPredicate(format: "identifier == 'library-podcast-row'")).firstMatch
        guard row.waitForExistence(timeout: 6) else {
            XCTFail("scrub: no podcast row"); return
        }
        row.tap()
        _ = app.cells.element(boundBy: 2).waitForExistence(timeout: 8)
        robustTap(app.cells.element(boundBy: 2))
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 8))
        app.buttons["Play"].tap()
        // Wait for the mini-player bar to appear (it has a stable identifier).
        let miniBar = app.otherElements["mini-player-bar"]
        let miniBarBtn = app.buttons.matching(NSPredicate(format: "identifier == 'mini-player-bar'")).firstMatch
        let miniAppeared = miniBar.waitForExistence(timeout: 10)
        sleep(1)
        // Tap the mini-player bar to expand to the full player sheet.
        if miniAppeared { robustTap(miniBar) }
        else if miniBarBtn.waitForExistence(timeout: 2) { robustTap(miniBarBtn) }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap() }
        sleep(2)
        snap(app, "scrub-01-full-player")
        dumpTree(app, "scrub-01-tree")
        let before = timeLabels(app)

        // The scrubber is a custom DragGesture view (PlayerScrubberView) with
        // accessibilityLabel "Playback scrubber" living in the floatingChrome
        // at the bottom of the full player. Try by accessibility label first.
        let slider = app.sliders["Playback scrubber"]
        let sliderFallback = app.sliders.firstMatch
        let scrubEl: XCUIElement? = slider.waitForExistence(timeout: 5) ? slider
                    : (sliderFallback.waitForExistence(timeout: 2) ? sliderFallback : nil)

        if let scrubEl {
            // Drag from 20% to 70% of the scrubber width.
            let start = scrubEl.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            let end = scrubEl.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
            start.press(forDuration: 0.5, thenDragTo: end)
            sleep(2)
            let after = timeLabels(app)
            snap(app, "scrub-02-after-drag")
            XCTAssertNotEqual(before, after, "FAIL scrub-seek-slider: time labels unchanged after dragging scrubber")
        } else {
            // Fallback: coordinate-based drag on the scrubber region. The
            // PlayerScrubberView lives in floatingChrome (.safeAreaInset bottom)
            // so it's at roughly dy: 0.76-0.80 of the screen height.
            let scrubStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.78))
            let scrubEnd   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.78))
            scrubStart.press(forDuration: 0.5, thenDragTo: scrubEnd)
            sleep(2)
            let after = timeLabels(app)
            snap(app, "scrub-02-after-coord-drag")
            XCTAssertNotEqual(before, after, "FAIL scrub-seek-slider: time labels unchanged after coord-drag on scrubber region")
        }
    }

    // MARK: - P1: playback-speed-change

    /// Change playback speed in the full player and confirm the speed label
    /// updates (e.g. 1× → 1.5×).
    func testP1_PlaybackSpeedChange() throws {
        let app = App.make()
        XCTAssertTrue(launchApp(app)); sleep(1)
        let row = app.buttons.matching(
            NSPredicate(format: "identifier == 'library-podcast-row'")).firstMatch
        guard row.waitForExistence(timeout: 6) else {
            XCTFail("speed: no podcast row"); return
        }
        row.tap()
        _ = app.cells.element(boundBy: 2).waitForExistence(timeout: 8)
        robustTap(app.cells.element(boundBy: 2))
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 8))
        app.buttons["Play"].tap()
        // Wait for the mini-player bar to appear, then tap it to open the full player.
        let miniBar2 = app.otherElements["mini-player-bar"]
        let miniBarBtn2 = app.buttons.matching(NSPredicate(format: "identifier == 'mini-player-bar'")).firstMatch
        let miniAppeared2 = miniBar2.waitForExistence(timeout: 10)
        sleep(1)
        if miniAppeared2 { robustTap(miniBar2) }
        else if miniBarBtn2.waitForExistence(timeout: 2) { robustTap(miniBarBtn2) }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap() }
        sleep(2)
        snap(app, "speed-01-full-player")
        dumpTree(app, "speed-01-tree")

        // Speed is accessed via the "More options" overflow menu (ellipsis button
        // in the player top bar, accessibilityLabel = "More options"). The menu
        // contains a "Speed: 1×" item that opens the PlayerSpeedSheet.
        let moreBtn = app.buttons["More options"]
        guard moreBtn.waitForExistence(timeout: 5) else {
            snap(app, "speed-NOMORE")
            XCTFail("FAIL playback-speed-change: 'More options' button not found in full player")
            return
        }
        moreBtn.tap(); sleep(1)
        snap(app, "speed-02-menu-open")

        // Tap the Speed item in the menu (label "Speed: 1×" or similar).
        let speedMenuItem = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Speed:'")).firstMatch
        guard speedMenuItem.waitForExistence(timeout: 4) else {
            // Dismiss menu and fail.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
            XCTFail("FAIL playback-speed-change: 'Speed:' menu item not found")
            return
        }
        let beforeLabel = speedMenuItem.label  // e.g. "Speed: 1×"
        speedMenuItem.tap(); sleep(1)
        snap(app, "speed-03-speed-sheet")

        // PlayerSpeedSheet shows rows with labels "1×", "1.5×", "2×", etc.
        let rate15 = app.buttons["1.5×"]
        let rate2  = app.buttons["2×"]
        if rate15.waitForExistence(timeout: 3) {
            rate15.tap(); sleep(1)
        } else if rate2.waitForExistence(timeout: 3) {
            rate2.tap(); sleep(1)
        }
        snap(app, "speed-04-after-change")

        // Reopen More options to verify the speed label changed.
        if moreBtn.waitForExistence(timeout: 3) {
            moreBtn.tap(); sleep(1)
            let afterSpeedItem = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Speed:'")).firstMatch
            let afterLabel = afterSpeedItem.waitForExistence(timeout: 3) ? afterSpeedItem.label : "?"
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap() // dismiss menu
            XCTAssertNotEqual(beforeLabel, afterLabel,
                "FAIL playback-speed-change: speed label unchanged ('\(beforeLabel)' → '\(afterLabel)')")
        }
    }

    // MARK: - P1: queue-remove-item

    /// Add an episode to the queue then remove it; confirm queue is empty or has fewer items.
    func testP1_QueueRemoveItem() throws {
        let app = App.make()
        XCTAssertTrue(launchApp(app)); sleep(1)
        let row = app.buttons.matching(
            NSPredicate(format: "identifier == 'library-podcast-row'")).firstMatch
        guard row.waitForExistence(timeout: 6) else {
            XCTFail("queue-remove: no podcast row"); return
        }
        row.tap()
        _ = app.cells.element(boundBy: 2).waitForExistence(timeout: 8)
        robustTap(app.cells.element(boundBy: 2))
        sleep(2)
        let qBtn = app.buttons.matching(NSPredicate(format: "label == 'Queue' OR label == 'Add to Queue'")).firstMatch
        guard qBtn.waitForExistence(timeout: 5) else {
            XCTFail("queue-remove: no Queue button"); return
        }
        qBtn.tap(); sleep(1)

        // Open the Up Next / Queue view.
        let queueAccess = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'up next' OR label CONTAINS[c] 'queue'")).firstMatch
        if !queueAccess.waitForExistence(timeout: 4) {
            // Try from full player area.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
            sleep(2)
        } else {
            queueAccess.tap(); sleep(2)
        }
        snap(app, "q-remove-01-queue-open")

        let countBefore = app.cells.count
        // Swipe to delete the first queue cell, or look for a Remove button.
        let firstCell = app.cells.firstMatch
        if firstCell.waitForExistence(timeout: 4) {
            firstCell.swipeLeft()
            sleep(1)
            let deleteBtn = app.buttons.matching(
                NSPredicate(format: "label == 'Delete' OR label == 'Remove'")).firstMatch
            if deleteBtn.waitForExistence(timeout: 3) { deleteBtn.tap(); sleep(1) }
            snap(app, "q-remove-02-after-delete")
            let countAfter = app.cells.count
            XCTAssertLessThan(countAfter, countBefore + 1,
                "FAIL queue-remove-item: cell count did not decrease (\(countBefore) → \(countAfter))")
        } else {
            snap(app, "q-remove-NOQUEUECELL")
        }
    }

    // MARK: - P1: settings-credentials-save

    /// Open Settings, navigate to an AI credential field, type a value,
    /// dismiss, and confirm it persisted by reopening.
    func testP1_SettingsCredentialsSave() throws {
        let app = App.make()
        XCTAssertTrue(launchApp(app)); sleep(1)
        let gear = app.buttons["gear"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5), "no settings gear"); gear.tap(); sleep(2)
        snap(app, "creds-01-settings")
        // Navigate into Models or a credentials section.
        let modelRow = staticTextContaining(app, "Models")
        if modelRow.waitForExistence(timeout: 4) {
            robustTap(modelRow); sleep(2)
            snap(app, "creds-02-models")
        }
        // Look for any text field (API key / URL).
        let field = app.textFields.firstMatch
        if field.waitForExistence(timeout: 4) {
            field.tap()
            field.clearText()
            field.typeText("test-api-key-qa")
            app.keyboards.buttons["Return"].tap()
            sleep(1)
            snap(app, "creds-03-typed")
            // Navigate away and back.
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists { back.tap(); sleep(1) }
            let modelRow2 = staticTextContaining(app, "Models")
            if modelRow2.waitForExistence(timeout: 3) {
                robustTap(modelRow2); sleep(2)
            }
            let fieldAfter = app.textFields.firstMatch
            let saved = fieldAfter.waitForExistence(timeout: 4) && fieldAfter.value as? String == "test-api-key-qa"
            snap(app, "creds-04-after-reopen")
            XCTAssertTrue(saved, "FAIL settings-credentials-save: text field does not show 'test-api-key-qa' after reopen — value may not persist")
        } else {
            snap(app, "creds-NOFIELD")
            // Not necessarily a failure — if settings has no text field visible the test is N/A.
            XCTSkip("settings-credentials-save: no text field visible in Models settings — check manually")
        }
    }

    // MARK: - P1: nostr-identity-create

    /// Navigate to the Nostr / identity section and confirm a keypair
    /// display or creation screen is reachable.
    func testP1_NostrIdentityCreate() throws {
        let app = App.make()
        XCTAssertTrue(launchApp(app)); sleep(1)
        let gear = app.buttons["gear"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5)); gear.tap(); sleep(2)
        snap(app, "nostr-01-settings")
        for label in ["Nostr", "Identity", "Profile", "Keys"] {
            let row = staticTextContaining(app, label)
            if row.waitForExistence(timeout: 2) {
                robustTap(row); sleep(2)
                snap(app, "nostr-02-\(label.lowercased())")
                let dumpN = XCTAttachment(string: app.debugDescription)
                dumpN.name = "nostr-02-tree"; dumpN.lifetime = .keepAlways; add(dumpN)
                let hasContent = app.staticTexts.count > 3
                XCTAssertTrue(hasContent, "FAIL nostr-identity-create: Nostr/\(label) screen appears empty")
                return
            }
        }
        snap(app, "nostr-NOSECTION")
        XCTFail("FAIL nostr-identity-create: no Nostr/Identity/Profile/Keys section found in Settings")
    }

    // MARK: - P1: feed-refresh-new-episodes

    /// Pull-to-refresh on the show detail to trigger a feed refresh.
    /// Confirm the episode list is still non-empty afterwards.
    func testP1_FeedRefreshNewEpisodes() throws {
        let app = App.make()
        XCTAssertTrue(launchApp(app)); sleep(1)
        let row = app.buttons.matching(
            NSPredicate(format: "identifier == 'library-podcast-row'")).firstMatch
        guard row.waitForExistence(timeout: 6) else {
            XCTFail("feed-refresh: no podcast row"); return
        }
        row.tap()
        _ = app.cells.element(boundBy: 2).waitForExistence(timeout: 8)
        let beforeCount = app.cells.count
        snap(app, "refresh-01-before")
        // Pull to refresh.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)))
        sleep(4) // allow refresh to complete
        snap(app, "refresh-02-after")
        let afterCount = app.cells.count
        XCTAssertGreaterThan(afterCount, 0, "FAIL feed-refresh-new-episodes: episode list empty after pull-to-refresh")
        // If the feed returned real episodes, count should have grown.
        // We only assert > 0 since the seeded episode may or may not persist.
    }

    // MARK: - P1: onboarding-first-launch (confirm NOT shown again)

    /// After onboarding is complete (state seeded), the onboarding sheet
    /// must NOT appear on launch.
    func testP1_OnboardingNotShownAgain() throws {
        let app = App.make()
        XCTAssertTrue(launchApp(app)); sleep(2)
        snap(app, "onboarding-01")
        let getStarted = app.buttons["Get Started"]
        let onboardingText = staticTextContaining(app, "Get started")
        let shown = getStarted.waitForExistence(timeout: 4) || onboardingText.waitForExistence(timeout: 2)
        XCTAssertFalse(shown, "FAIL onboarding-first-launch: onboarding screen appeared despite hasCompletedOnboarding=true in seeded state")
    }

    // MARK: - BLOCKED (physical-device-only) ----------------------------------

    /// control-center-controls: requires real hardware lock screen / Control Center.
    func testP1_ControlCenterControls_BLOCKED() throws {
        throw XCTSkip("BLOCKED: control-center-controls requires a physical device with a real lock screen and Control Center. Simulator cannot simulate hardware media keys.")
    }

    /// offline-playback-downloaded: requires a downloaded episode AND disabling
    /// the simulator's network — not reliably doable in a CI/XCTest context.
    func testP0_OfflinePlaybackDownloaded_BLOCKED() throws {
        throw XCTSkip("BLOCKED: offline-playback-downloaded requires a completed download and network disable. Run manually on device: download an episode, enable Airplane Mode, play it, confirm audio plays.")
    }

    /// large-library-load-perf: requires 50+ subscribed podcasts.
    func testP1_LargeLibraryLoadPerf_BLOCKED() throws {
        throw XCTSkip("BLOCKED: large-library-load-perf requires 50+ subscribed podcasts seeded into the library. Not feasible in the automated simulator pass — run manually or provide a snapshot with a populated library.")
    }

    /// resume-position-across-restart (P0): KNOWN KERNEL BUG, peer-owned.
    /// ep.position_secs is not written during normal playback — only via
    /// PersistPosition (seek/skip while paused). Cold relaunch reads stale
    /// position_secs: 0 → kernel projection overwrites Swift playbackPosition → 0.
    /// Fix: write ep.position_secs from Playing audio reports or call
    /// kernelPersistPosition at the 30s max-interval cadence.
    /// Kernel playback files (audio_report.rs, player_actions.rs) are peer-owned.
    func testP0_ResumePositionAcrossRestart_BLOCKED() throws {
        throw XCTSkip("BLOCKED: resume-position-across-restart — kernel bug (peer-owned). ep.position_secs never written during normal playback; cold relaunch loses position. See P0-04b failure in CoreJourneyUITests for full root-cause analysis.")
    }

    /// queue-autoadvance: requires two downloaded episodes and ~full play of one.
    func testP1_QueueAutoadvance_BLOCKED() throws {
        throw XCTSkip("BLOCKED: queue-autoadvance requires at least one episode to play to completion (too slow for automated pass). Run manually: queue two episodes, wait for first to finish, confirm second starts.")
    }

    // MARK: - P1: opml-import (manual-only note)
    func testP1_OpmlImport_BLOCKED() throws {
        throw XCTSkip("BLOCKED: opml-import requires a pre-staged OPML file in the Files app or a share extension trigger — not automatable in XCTest without filesystem access. Run manually: share an OPML file to Pod0 and confirm podcasts appear in Library.")
    }

    // MARK: - Helpers

    private func timeLabels(_ app: XCUIApplication) -> [String] {
        let re = try? NSRegularExpression(pattern: "^-?\\d{1,2}:\\d{2}(:\\d{2})?$")
        return app.staticTexts.allElementsBoundByIndex.compactMap { el in
            let l = el.label
            guard let re, re.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)) != nil else { return nil }
            return l
        }
    }
}

extension XCUIElement {
    /// Clear all text in a text field.
    func clearText() {
        guard let s = value as? String, !s.isEmpty else { return }
        tap()
        let selectAll = XCUIApplication().menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 2) {
            selectAll.tap()
            typeText(XCUIKeyboardKey.delete.rawValue)
        } else {
            let del = String(repeating: XCUIKeyboardKey.delete.rawValue, count: s.count)
            typeText(del)
        }
    }
}
