import XCTest

final class PromoteToProjectUITests: PiNativeUITestCase {
    func testPromoteToProjectModalNameOnlyFlowOpensPromotedProjectChat() throws {
        let sandboxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativePromoteUISandbox-")
            .appendingPathComponent(UUID().uuidString)
        let projectURL = sandboxURL.appendingPathComponent("SettingsCodeFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try "outside destination sentinel".write(to: sandboxURL.appendingPathComponent("outside-destination.txt"), atomically: true, encoding: .utf8)
        let siblingProject = projectURL.appendingPathComponent("existing-sibling-project", isDirectory: true)
        try FileManager.default.createDirectory(at: siblingProject, withIntermediateDirectories: true)
        try "existing sibling data".write(to: siblingProject.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        let beforeOutsideDestination = try recursiveUTF8FileContents(in: sandboxURL)

        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROMOTE_CODE_FOLDER"] = projectURL.path
        app.launchEnvironment["PI_NATIVE_TEST_PROMOTE_STEP_DELAY_MS"] = "0"
        app.launchEnvironment["PI_NATIVE_MOCK_RPC_RESPONSE"] = "projectless planning response"
        app.launchEnvironment["PI_NATIVE_AUTOSUBMIT_AFTER_TYPING"] = "1"
        app.launchArguments.append("--ui-test-autosubmit")
        app.launch()

        clickNewChat(in: app)
        let prompt = app.textViews["composer.textEditor"].firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.click()
        app.typeText("promote this quick plan")
        XCTAssertTrue(app.staticTexts["transcript.assistantMessage"].waitForExistence(timeout: 10))

        app.buttons["chat.promoteProjectLink"].click()
        XCTAssertTrue(app.staticTexts["Promote to Project"].waitForExistence(timeout: 5))
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.click()
        nameField.typeKey("a", modifierFlags: [.command])
        nameField.typeText("Promoted UI Project")

        // 2119: REQ-002.1.1
        // 2119: REQ-002.1.2
        // 2119: REQ-002.1.5
        app.buttons["Promote"].firstMatch.click()

        // 2119: REQ-002.1.1
        // 2119: REQ-002.4.1
        XCTAssertTrue(app.buttons["promoted-ui-project"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["promoted-ui-project"].waitForExistence(timeout: 5), "The promoted chat header should show the project scope, not only the sidebar row.")
        let promotedContextMessage = app.staticTexts["transcript.userMessage"].firstMatch
        XCTAssertTrue(promotedContextMessage.waitForExistence(timeout: 10))
        let promotedContextText = (promotedContextMessage.value as? String) ?? promotedContextMessage.label
        XCTAssertTrue(promotedContextText.contains("promote this quick plan"))
        XCTAssertTrue(promotedContextText.contains("promoted-chat.md"))
        XCTAssertFalse(app.buttons["promote this quick plan"].exists)
        let promotedDestination = projectURL.appendingPathComponent("promoted-ui-project", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: promotedDestination.appendingPathComponent("promoted-chat.md").path))
        let afterOutsideDestination = try recursiveUTF8FileContents(in: sandboxURL)
        let changedFilesOutsideDestination = beforeOutsideDestination.filter { relativePath, contents in
            !relativePath.hasPrefix("SettingsCodeFolder/promoted-ui-project/") && afterOutsideDestination[relativePath] != contents
        }
        XCTAssertTrue(changedFilesOutsideDestination.isEmpty, "Promotion modified files outside the promoted destination: \(changedFilesOutsideDestination.keys.sorted())")
        XCTAssertEqual(try String(contentsOf: sandboxURL.appendingPathComponent("outside-destination.txt")), "outside destination sentinel")
        XCTAssertEqual(try String(contentsOf: siblingProject.appendingPathComponent("notes.txt")), "existing sibling data")
    }

    func testPromoteToProjectModalUsesPersistedSettingsFolderForDestination() throws {
        let sandboxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativePersistedPromoteSettings-")
            .appendingPathComponent(UUID().uuidString)
        let persistedSettingsFolder = sandboxURL.appendingPathComponent("PersistedSettingsCodeFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: persistedSettingsFolder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: sandboxURL)
            Self.deletePersistedAppDefault(key: "promote.defaultCodeFolder")
        }
        Self.writePersistedAppDefault(key: "promote.defaultCodeFolder", value: persistedSettingsFolder.path)

        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROMOTE_STEP_DELAY_MS"] = "0"
        app.launchEnvironment["PI_NATIVE_MOCK_RPC_RESPONSE"] = "persisted settings promote response"
        app.launchEnvironment["PI_NATIVE_AUTOSUBMIT_AFTER_TYPING"] = "1"
        app.launchArguments.append("--ui-test-autosubmit")
        app.launch()

        clickNewChat(in: app)
        let prompt = app.textViews["composer.textEditor"].firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.click()
        app.typeText("promote with persisted settings")
        XCTAssertTrue(app.staticTexts["transcript.assistantMessage"].waitForExistence(timeout: 10))

        app.buttons["chat.promoteProjectLink"].click()
        XCTAssertTrue(app.staticTexts["Promote to Project"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[persistedSettingsFolder.path].waitForExistence(timeout: 5))
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.click()
        nameField.typeKey("a", modifierFlags: [.command])
        nameField.typeText("Persisted Settings Project")

        // 2119: REQ-002.1.2
        app.buttons["Promote"].firstMatch.click()
        XCTAssertTrue(app.buttons["persisted-settings-project"].waitForExistence(timeout: 10))
        let promotedDestination = persistedSettingsFolder.appendingPathComponent("persisted-settings-project", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: promotedDestination.appendingPathComponent("promoted-chat.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandboxURL.appendingPathComponent("persisted-settings-project", isDirectory: true).path))
    }

    func testPromoteToProjectModalShowsCreationFailureWithoutOpenProjectAction() throws {
        // 2119: REQ-002.4.3
        let sandboxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativePromoteCreationFailureUI-")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sandboxURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: sandboxURL)
            Self.deletePersistedAppDefault(key: "promote.defaultCodeFolder")
        }
        let codeFolderFile = sandboxURL.appendingPathComponent("code-folder-is-file")
        try "not a directory".write(to: codeFolderFile, atomically: true, encoding: .utf8)
        Self.writePersistedAppDefault(key: "promote.defaultCodeFolder", value: codeFolderFile.path)

        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROMOTE_STEP_DELAY_MS"] = "0"
        app.launchEnvironment["PI_NATIVE_MOCK_RPC_RESPONSE"] = "projectless planning response"
        app.launchEnvironment["PI_NATIVE_AUTOSUBMIT_AFTER_TYPING"] = "1"
        app.launchArguments.append("--ui-test-autosubmit")
        app.launch()

        clickNewChat(in: app)
        let prompt = app.textViews["composer.textEditor"].firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.click()
        app.typeText("promote but fail creation")
        XCTAssertTrue(app.staticTexts["transcript.assistantMessage"].waitForExistence(timeout: 10))

        app.buttons["chat.promoteProjectLink"].click()
        XCTAssertTrue(app.staticTexts["Promote to Project"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[codeFolderFile.path].waitForExistence(timeout: 5))
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.click()
        nameField.typeKey("a", modifierFlags: [.command])
        nameField.typeText("Failed Creation Project")

        app.buttons["Promote"].firstMatch.click()

        XCTAssertTrue(app.staticTexts["Promote to Project"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["promoteToProject.errorMessage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Open Project"].exists)
        XCTAssertFalse(app.buttons["failed-creation-project"].exists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: codeFolderFile.appendingPathComponent("failed-creation-project", isDirectory: true).path))
    }

}
