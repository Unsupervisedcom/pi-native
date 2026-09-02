import Darwin
import XCTest

final class ProjectUITests: PiNativeUITestCase {
    func testProjectsSettingsShowProjectFolderWithoutDocsOrProvenanceToggles() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        app.launch()

        let settingsButton = app.buttons["sidebar.settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.click()

        let projectsSection = app.buttons["Projects"].firstMatch
        XCTAssertTrue(projectsSection.waitForExistence(timeout: 5))
        projectsSection.click()

        XCTAssertTrue(app.staticTexts["Project folder"].waitForExistence(timeout: 5))
        let field = app.textFields["settings.projects.defaultCodeFolderField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Default code folder"].exists)
        XCTAssertFalse(app.staticTexts["Create docs folder"].exists)
        XCTAssertFalse(app.staticTexts["Include chat provenance"].exists)
    }


    func testProjectDiffPillOpensTargetedPendingChangesSummary() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeDiffTest-\(UUID().uuidString)")
        let otherProjectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeOtherDiffTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherProjectURL, withIntermediateDirectories: true)

        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = projectURL.path
        app.launchEnvironment["PI_NATIVE_TEST_OTHER_PROJECT_PATH"] = otherProjectURL.path
        app.launchEnvironment["PI_NATIVE_TEST_DIFF_STATS"] = "1,0"
        app.launchEnvironment["PI_NATIVE_TEST_DIFF_STATUS_PROJECT_PATH"] = projectURL.path
        app.launchEnvironment["PI_NATIVE_TEST_DIFF_STATUS_PROJECT_SUMMARY"] = "main|tracked.txt,M,1,0"
        app.launchEnvironment["PI_NATIVE_TEST_OTHER_DIFF_STATUS_PROJECT_PATH"] = otherProjectURL.path
        app.launchEnvironment["PI_NATIVE_TEST_OTHER_DIFF_STATUS_PROJECT_SUMMARY"] = "feature|other.txt,A,2,0"
        app.launch()

        let projectRow = app.buttons["project.row"].firstMatch
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))
        projectRow.hover()
        let firstDiffPill = app.buttons["project.diffPill"].firstMatch
        XCTAssertTrue(firstDiffPill.waitForExistence(timeout: 5))
        XCTAssertTrue(firstDiffPill.isHittable)
        firstDiffPill.click()

        // 2119: REQ-012.1.1
        XCTAssertTrue(app.staticTexts["Pending Changes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["main"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["tracked.txt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Files"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Added"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Deleted"].waitForExistence(timeout: 5))

        let otherProjectRow = app.buttons[otherProjectURL.lastPathComponent].firstMatch
        XCTAssertTrue(otherProjectRow.waitForExistence(timeout: 5))
        otherProjectRow.hover()
        let otherDiffPill = app.buttons["project.diffPill"].firstMatch
        XCTAssertTrue(otherDiffPill.waitForExistence(timeout: 5))
        XCTAssertTrue(otherDiffPill.isHittable)
        otherDiffPill.click()

        XCTAssertTrue(app.staticTexts["feature"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["other.txt"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["tracked.txt"].exists)
    }

    func testPendingChangesShowsInitialLoadingState() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeLoadingDiffTest-\(UUID().uuidString)")
        let fifoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeLoadingDiffGate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        if mkfifo(fifoURL.path, 0o600) != 0 {
            throw XCTSkip("Could not create FIFO for loading-state gate")
        }
        defer { try? FileManager.default.removeItem(at: fifoURL) }

        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = projectURL.path
        app.launchEnvironment["PI_NATIVE_TEST_DIFF_STATS"] = "1,0"
        app.launchEnvironment["PI_NATIVE_TEST_DIFF_STATUS_GATE_FIFO"] = fifoURL.path
        app.launchEnvironment["PI_NATIVE_TEST_DIFF_STATUS_SUMMARY"] = "main|loading.txt,M,1,0"
        app.launch()

        XCTAssertTrue(app.buttons["project.row"].waitForExistence(timeout: 10))
        app.menuItems["Pending Changes"].click()

        // 2119: REQ-012.2.2
        XCTAssertTrue(app.staticTexts["Loading Git status…"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Files"].exists)

        let writer = FileHandle(forWritingAtPath: fifoURL.path)
        writer?.write(Data("release\n".utf8))
        try writer?.close()
    }

    func testPendingChangesWithNoProjectShowsNoProjectState() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launch()

        // 2119: REQ-012.2.2
        app.menuItems["Pending Changes"].click()

        XCTAssertTrue(app.staticTexts["Pending Changes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Project"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Select a project to review its Git changes."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Files"].exists)
    }

    func testPendingChangesShowsCleanWorkingTreeState() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeCleanDiffTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = projectURL.path
        app.launchEnvironment["PI_NATIVE_TEST_DIFF_STATUS_SUMMARY"] = "main|"
        app.launch()

        // 2119: REQ-012.2.2
        app.menuItems["Pending Changes"].click()

        XCTAssertTrue(app.staticTexts["Pending Changes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Changes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The working tree has no uncommitted changes."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Files"].exists)
    }

    func testPendingChangesShowsGitFailureState() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeFailureDiffTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = projectURL.path
        app.launchEnvironment["PI_NATIVE_TEST_DIFF_STATS"] = "1,0"
        app.launchEnvironment["PI_NATIVE_TEST_DIFF_STATUS_ERROR"] = "not a git repository"
        app.launch()

        XCTAssertTrue(app.buttons["project.row"].waitForExistence(timeout: 10))
        app.menuItems["Pending Changes"].click()

        // 2119: REQ-012.2.2
        XCTAssertTrue(app.staticTexts["Pending Changes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Couldn’t load Git status"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Files"].exists)
    }

    func testArchiveChatRemovesItFromSidebar() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeArchiveTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_STANDALONE_CHAT_TITLES"] = "please archive this"
        app.launch()

        let chatText = app.staticTexts["please archive this"]
        let chatButton = app.buttons["please archive this"]
        XCTAssertTrue(chatText.waitForExistence(timeout: 5) || chatButton.waitForExistence(timeout: 5))
        let chatRow = chatButton.exists ? chatButton : chatText

        // Hover the row to reveal the archive control, then click it.
        chatRow.hover()
        let archiveButton = app.buttons["chat.archiveButton"].firstMatch
        XCTAssertTrue(archiveButton.waitForExistence(timeout: 5))
        archiveButton.click()

        // The chat leaves the sidebar and the app returns to the new-chat
        // screen (it was the only chat).
        XCTAssertTrue(app.descendants(matching: .any)["newChat.promptEditor"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["please archive this"].exists)
    }
}
