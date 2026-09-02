import XCTest

final class PiStartupHealthUITests: PiNativeUITestCase {
    // 2119: REQ-011.2.4
    func testLiveConversationInteractiveQuestionShowsGlobalAndChatLocalRecovery() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeRuntimeAttention-")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("fake-pi.py")
        try """
        #!/usr/bin/python3
        import json, sys
        isolated_health_probe = "--no-session" in sys.argv
        sent_runtime_question = False
        for line in sys.stdin:
            request = json.loads(line)
            print(json.dumps({
                "type": "response",
                "id": request["id"],
                "command": request["type"],
                "success": True,
                "data": {}
            }), flush=True)
            if not isolated_health_probe and request["type"] == "get_state" and not sent_runtime_question:
                sent_runtime_question = True
                print(json.dumps({
                    "type": "extension_ui_request",
                    "id": "runtime-setup",
                    "method": "confirm",
                    "title": "Finish Pi setup",
                    "message": "Resolve the interactive question"
                }), flush=True)
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = root.path
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_CHAT_TITLE"] = "runtime attention chat"
        app.launchEnvironment["PI_NATIVE_TEST_PI_EXECUTABLE"] = "/usr/bin/python3"
        app.launchEnvironment["PI_NATIVE_TEST_PI_ARGUMENTS"] = String(
            data: try JSONEncoder().encode([executable.path]),
            encoding: .utf8
        )
        app.launch()

        XCTAssertTrue(app.staticTexts["runtime attention chat"].firstMatch.waitForExistence(timeout: 10))
        let localNotice = app.staticTexts["chat.notice"].firstMatch
        XCTAssertTrue(localNotice.waitForExistence(timeout: 10))

        let statusBar = app.groups["piHealth.statusBar"]
        XCTAssertTrue(statusBar.waitForExistence(timeout: 10))
        let globalMessageElement = app.staticTexts["piHealth.message"]
        let globalMessage = (globalMessageElement.value as? String) ?? globalMessageElement.label
        XCTAssertTrue(globalMessage.contains("Finish Pi setup"))
        XCTAssertTrue(globalMessage.contains("Resolve the interactive question"))
        XCTAssertTrue(app.buttons["piHealth.openTerminal"].exists)
        XCTAssertTrue(localNotice.exists)
    }

    // 2119: REQ-011.2.1
    // 2119: REQ-011.3.1
    func testFailureShowsBottomRecoveryBarAndResolveAction() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PI_EXECUTABLE"] = "/tmp/pinative-missing-health-pi"
        app.launch()
        app.activate()

        let statusBar = app.groups["piHealth.statusBar"]
        XCTAssertTrue(statusBar.waitForExistence(timeout: 10))
        let message = app.staticTexts["piHealth.message"]
        XCTAssertTrue(message.exists)
        let problemDescription = (message.value as? String) ?? message.label
        XCTAssertTrue(problemDescription.contains("pinative-missing-health-pi"))

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(abs(statusBar.frame.maxY - window.frame.maxY), 3)
        let composer = app.textViews["composer.textEditor"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertFalse(statusBar.frame.intersects(composer.frame))

        let action = app.buttons["piHealth.openTerminal"]
        XCTAssertEqual(action.label, "Resolve in Terminal")
        XCTAssertTrue(action.exists)
        XCTAssertLessThanOrEqual(message.frame.maxX, action.frame.minX)
    }

    // 2119: REQ-011.3.3
    func testReturningToPiNativeRechecksHealthAndClearsRecoveredStatus() throws {
        let sequenceFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeHealthSequence-\(UUID().uuidString)")
        let terminalCaptureFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeTerminalCapture-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: sequenceFile)
            try? FileManager.default.removeItem(at: terminalCaptureFile)
        }

        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PI_HEALTH_SEQUENCE_FILE"] = sequenceFile.path
        app.launchEnvironment["PI_NATIVE_TEST_PI_HEALTH_SEQUENCE"] = "Pi needs setup before retry.|Pi is still unavailable.|healthy"
        app.launchEnvironment["PI_NATIVE_TEST_TERMINAL_CAPTURE_FILE"] = terminalCaptureFile.path
        app.launch()
        app.activate()

        let statusBar = app.groups["piHealth.statusBar"]
        XCTAssertTrue(statusBar.waitForExistence(timeout: 10))
        let recoveryAction = app.buttons["piHealth.openTerminal"]
        XCTAssertTrue(recoveryAction.exists)
        recoveryAction.click()
        let terminalOpened = NSPredicate { _, _ in
            FileManager.default.fileExists(atPath: terminalCaptureFile.path)
        }
        expectation(for: terminalOpened, evaluatedWith: NSObject())
        waitForExpectations(timeout: 5)

        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let message = app.staticTexts["piHealth.message"]
        let refreshedFailure = NSPredicate { _, _ in
            ((message.value as? String) ?? message.label).contains("Pi is still unavailable")
        }
        expectation(for: refreshedFailure, evaluatedWith: NSObject())
        waitForExpectations(timeout: 10)
        XCTAssertTrue(statusBar.exists)
        XCTAssertEqual(
            try String(contentsOf: sequenceFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
            "2"
        )
        try FileManager.default.removeItem(at: terminalCaptureFile)
        recoveryAction.click()
        expectation(for: terminalOpened, evaluatedWith: NSObject())
        waitForExpectations(timeout: 5)

        finder.activate()
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(waitForNonExistence(statusBar, timeout: 10))
        XCTAssertEqual(
            try String(contentsOf: sequenceFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
            "3"
        )
    }
}
