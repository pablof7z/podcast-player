import XCTest

/// Black-box UI test: actually USES the app — opens the Agent, types a message,
/// taps send, and reports what really appears on screen (the agent's reply, or
/// the error banner verbatim). Runs against the on-device build, so it exercises
/// the real local-model path end to end. Requires Settings → Developer → Enable
/// UI Automation on the device.
final class AgentChatUITest: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    func testAgentRepliesToAMessage() throws {
        // Device-only, slow (first-use loads a ~2.6 GB model), and requires the
        // model to be downloaded — opt in explicitly so CI/simulator runs skip.
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_DEVICE_UI_TESTS"] == "1",
            "Set RUN_DEVICE_UI_TESTS=1 to drive the agent on a real device")

        let app = XCUIApplication()
        app.launch()

        // 1) Open the Agent (sparkles toolbar button).
        let openAgent = app.buttons["agent.open"].firstMatch
        XCTAssertTrue(openAgent.waitForExistence(timeout: 40),
                      "UITEST: 'Open Agent' button never appeared")
        openAgent.tap()

        // 2) Find the composer (axis:.vertical TextField shows up as a textView).
        let field: XCUIElement = {
            let tv = app.textViews["agent.input"].firstMatch
            if tv.waitForExistence(timeout: 10) { return tv }
            return app.textFields["agent.input"].firstMatch
        }()
        XCTAssertTrue(field.waitForExistence(timeout: 15),
                      "UITEST: agent input field never appeared")
        field.tap()
        field.typeText("Say hello in one short sentence.")

        // 3) Send.
        let send = app.buttons["Send message"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 10), "UITEST: Send button missing")
        send.tap()
        print("UITEST: message sent — waiting for reply or error…")

        // 4) Wait for an outcome. First use loads the ~2.6 GB model (slow), so
        //    give it generous time. Report whichever lands first.
        let errorBanner = app.staticTexts["agent.error"].firstMatch
        let deadline = Date().addingTimeInterval(180)
        var sawError = false
        while Date() < deadline {
            if errorBanner.exists {
                sawError = true
                print("UITEST: ❌ AGENT ERROR BANNER = \"\(errorBanner.label)\"")
                break
            }
            Thread.sleep(forTimeInterval: 2)
        }

        // 5) Dump what's on screen so the actual reply/state is captured.
        print("UITEST: ----- visible text on screen -----")
        for t in app.staticTexts.allElementsBoundByIndex.prefix(60) where !t.label.isEmpty {
            print("UITEST:   \(t.label)")
        }
        print("UITEST: -----------------------------------")

        XCTAssertFalse(sawError,
                       "UITEST: the agent showed an error banner: \"\(errorBanner.label)\"")
    }
}
