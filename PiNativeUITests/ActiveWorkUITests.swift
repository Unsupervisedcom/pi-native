import XCTest

final class ActiveWorkUITests: PiNativeUITestCase {
    func testRunningChatShowsIndicator() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        app.launchEnvironment["PI_NATIVE_MOCK_RPC_RESPONSE"] = "running indicator test complete"
        app.launchEnvironment["PI_NATIVE_MOCK_RPC_RESPONSE_DELAY_MS"] = "2500"
        app.launch()

        clickNewChat(in: app)
        let prompt = app.textViews["composer.textEditor"].firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.click()
        app.typeText("show the running indicator")
        app.buttons["Send"].firstMatch.click()

        let indicator = app.descendants(matching: .any)["chat.runningSpinner"].firstMatch
        XCTAssertTrue(indicator.waitForExistence(timeout: 5))
    }

    func testVisibleStopButtonStopsLateOutputAndLeavesComposerUsable() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        app.launchEnvironment["PI_NATIVE_MOCK_RPC_RESPONSE"] = "late output after stop"
        app.launchEnvironment["PI_NATIVE_MOCK_RPC_RESPONSE_DELAY_MS"] = "2500"
        app.launch()

        clickNewChat(in: app)
        let prompt = app.textViews["composer.textEditor"].firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.click()
        app.typeText("start stop test")
        app.buttons["Send"].firstMatch.click()

        // 2119: REQ-003.5.1
        let stop = app.buttons["Stop"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        let transitionDeadline = Date().addingTimeInterval(1)
        stop.click()
        let remainingTransitionTime = transitionDeadline.timeIntervalSinceNow
        XCTAssertGreaterThan(remainingTransitionTime, 0)
        XCTAssertTrue(waitForNonExistence(stop, timeout: remainingTransitionTime))
        let send = app.buttons["Send"].firstMatch
        XCTAssertTrue(send.exists)
        XCTAssertFalse(app.descendants(matching: .any)["chat.runningSpinner"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "late output after stop", "late output after stop")).firstMatch.exists)

        // 2119: REQ-003.5.3
        XCTAssertTrue(app.staticTexts["Stopped."].waitForExistence(timeout: 1))

        // 2119: REQ-003.5.2
        XCTAssertFalse(app.staticTexts["transcript.assistantMessage"].waitForExistence(timeout: 3))

        // 2119: REQ-003.5.1
        let composer = app.textViews["composer.textEditor"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.click()
        app.typeText("later prompt remains editable")
        XCTAssertTrue((composer.value as? String)?.contains("later prompt remains editable") == true)
        let userMessageCountBeforeLaterPrompt = app.staticTexts.matching(identifier: "transcript.userMessage").count
        app.buttons["Send"].firstMatch.click()
        XCTAssertGreaterThan(app.staticTexts.matching(identifier: "transcript.userMessage").count, userMessageCountBeforeLaterPrompt)
    }

    /// Opt-in evidence for the real authenticated Pi lifecycle. Deterministic
    /// UI runs leave this skipped; invoke it explicitly with the temporary
    /// authorization marker created by the local test command.
    @MainActor
    func testEscapeInterruptsLivePiAndPersistsAcrossRelaunch() throws {
        let authorizationMarker = "/tmp/pinative-run-real-pi-interruption-test"
        guard FileManager.default.fileExists(atPath: authorizationMarker) else {
            throw XCTSkip("Requires explicit live Pi provider authorization")
        }
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "--ui-test-autosubmit"]
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        app.launchEnvironment["PI_NATIVE_AUTOSUBMIT_AFTER_TYPING"] = "1"
        app.launch()

        let projectRow = app.buttons["project.row"].firstMatch
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))
        projectRow.hover()
        let projectNewChat = app.buttons["project.newChatButton"].firstMatch
        XCTAssertTrue(projectNewChat.waitForExistence(timeout: 5))
        XCTAssertTrue(projectNewChat.isHittable)
        projectNewChat.click()
        let newChatPrompt = app.textViews["composer.textEditor"].firstMatch
        XCTAssertTrue(newChatPrompt.waitForExistence(timeout: 5))
        newChatPrompt.click()
        app.typeText("Run this exact shell command now and do nothing else until it finishes: sleep 20; printf LIVE_PI_INTERRUPTED_OUTPUT")

        XCTAssertTrue(app.staticTexts["Running a project check"].waitForExistence(timeout: 60))
        app.typeKey(.escape, modifierFlags: [])

        // 2119: REQ-003.5.1
        // 2119: REQ-003.5.3
        XCTAssertTrue(app.staticTexts["Stopped."].waitForExistence(timeout: 1))
        let composer = app.textViews["composer.textEditor"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.click()
        app.typeText("Reply with exactly LIVE_PI_INTERRUPT_RECOVERED and do nothing else.")
        let send = app.buttons["Send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: send)
        waitForExpectations(timeout: 30)
        send.click()

        let recoveredReply = app.staticTexts.matching(NSPredicate(
            format: "identifier == %@ AND (value CONTAINS %@ OR label CONTAINS %@)",
            "transcript.assistantMessage",
            "LIVE_PI_INTERRUPT_RECOVERED",
            "LIVE_PI_INTERRUPT_RECOVERED"
        )).firstMatch
        XCTAssertTrue(recoveredReply.waitForExistence(timeout: 60))
        XCTAssertFalse(app.staticTexts.matching(identifier: "transcript.assistantMessage").matching(NSPredicate(
            format: "value CONTAINS %@ OR label CONTAINS %@",
            "LIVE_PI_INTERRUPTED_OUTPUT",
            "LIVE_PI_INTERRUPTED_OUTPUT"
        )).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Stopped."].exists)

        app.terminate()
        app.launch()

        XCTAssertTrue(app.staticTexts["Stopped."].waitForExistence(timeout: 30))
        XCTAssertTrue(recoveredReply.waitForExistence(timeout: 30))
    }
}
