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

        // 2119: REQ-003.5.2
        XCTAssertFalse(app.staticTexts["transcript.assistantMessage"].waitForExistence(timeout: 3))

        // 2119: REQ-003.5.3
        let composer = app.textViews["composer.textEditor"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.click()
        app.typeText("later prompt remains editable")
        XCTAssertTrue((composer.value as? String)?.contains("later prompt remains editable") == true)
        let userMessageCountBeforeLaterPrompt = app.staticTexts.matching(identifier: "transcript.userMessage").count
        app.buttons["Send"].firstMatch.click()
        XCTAssertGreaterThan(app.staticTexts.matching(identifier: "transcript.userMessage").count, userMessageCountBeforeLaterPrompt)
    }
}
