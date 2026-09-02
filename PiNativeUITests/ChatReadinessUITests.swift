import XCTest

final class ChatReadinessUITests: PiNativeUITestCase {
    func testNonCatastrophicLoadingKeepsDisplayedChatComposerInteractive() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeReadinessLoading-")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = projectURL.path
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_CHAT_TITLE"] = "seed non-catastrophic loading chat"
        app.launchEnvironment["PI_NATIVE_TEST_RPC_STALL"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["seed non-catastrophic loading chat"].firstMatch.waitForExistence(timeout: 10))
        let composer = app.textViews["composer.textEditor"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))

        // 2119: REQ-005.2.1
        XCTAssertFalse(app.staticTexts["chat.rpcStatus"].exists)
        composer.click()
        app.typeText("loading remains interactive")
        XCTAssertTrue((composer.value as? String)?.contains("loading remains interactive") == true)
        let attachFiles = app.buttons["Attach files"].firstMatch
        XCTAssertTrue(attachFiles.waitForExistence(timeout: 5))
        XCTAssertTrue(attachFiles.isEnabled)
        XCTAssertTrue(attachFiles.isHittable)
    }

    func testSelectedChatShowsPiFailureAndDisablesComposer() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeReadinessFailure-")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = projectURL.path
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_CHAT_TITLE"] = "seed readiness failure chat"
        app.launchEnvironment["PI_NATIVE_TEST_PI_EXECUTABLE"] = "/tmp/pinative-missing-pi-executable"
        app.launch()

        XCTAssertTrue(app.staticTexts["seed readiness failure chat"].firstMatch.waitForExistence(timeout: 10))

        // 2119: REQ-005.2.1
        let rpcStatus = app.staticTexts["chat.rpcStatus"]
        XCTAssertTrue(rpcStatus.waitForExistence(timeout: 5))
        let statusValue = rpcStatus.value as? String
        XCTAssertTrue(statusValue?.contains("Failed to start pi:") == true)
        XCTAssertFalse(statusValue?.contains("RPC") == true)
        assertElementContainsVisibleRed(rpcStatus)
        let composer = app.textViews["composer.textEditor"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        let beforeValue = composer.value as? String
        composer.click()
        app.typeText("should not type")
        XCTAssertEqual(composer.value as? String, beforeValue)
        let attachFiles = app.buttons["Attach files"].firstMatch
        XCTAssertTrue(attachFiles.waitForExistence(timeout: 5))
        XCTAssertFalse(attachFiles.isEnabled)
        let send = app.buttons["Send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertFalse(send.isEnabled)
        let modelAndEffortPicker = app.menuButtons["composer.modelPicker"].firstMatch
        // Disabled SwiftUI menu buttons may be omitted from the macOS accessibility tree.
        XCTAssertTrue(!modelAndEffortPicker.exists || !modelAndEffortPicker.isEnabled)
    }

    func testSelectedChatShowsCatastrophicRPCFailureAndDisablesComposer() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeReadinessCatastrophicFailure-")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = projectURL.path
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_CHAT_TITLE"] = "seed catastrophic failure chat"
        app.launchEnvironment["PI_NATIVE_TEST_PI_EXECUTABLE"] = "/usr/bin/false"
        app.launch()

        XCTAssertTrue(app.staticTexts["seed catastrophic failure chat"].firstMatch.waitForExistence(timeout: 10))

        // 2119: REQ-005.2.1
        let rpcStatus = app.staticTexts["chat.rpcStatus"]
        XCTAssertTrue(rpcStatus.waitForExistence(timeout: 8))
        let statusValue = (rpcStatus.value as? String) ?? rpcStatus.label
        XCTAssertTrue(statusValue.contains("Failed to load session:"))
        assertElementContainsVisibleRed(rpcStatus)
        let composer = app.textViews["composer.textEditor"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        let beforeValue = composer.value as? String
        composer.click()
        app.typeText("should not type after catastrophic failure")
        XCTAssertEqual(composer.value as? String, beforeValue)
        let attachFiles = app.buttons["Attach files"].firstMatch
        XCTAssertTrue(attachFiles.waitForExistence(timeout: 5))
        XCTAssertFalse(attachFiles.isEnabled)
        let send = app.buttons["Send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertFalse(send.isEnabled)
        let modelAndEffortPicker = app.menuButtons["composer.modelPicker"].firstMatch
        // Disabled SwiftUI menu buttons may be omitted from the macOS accessibility tree.
        XCTAssertTrue(!modelAndEffortPicker.exists || !modelAndEffortPicker.isEnabled)
    }

}
