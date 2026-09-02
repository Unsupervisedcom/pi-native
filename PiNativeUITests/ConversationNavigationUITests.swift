import XCTest

final class ConversationNavigationUITests: PiNativeUITestCase {
    func testMockConversationTranscriptPersistsAfterRelaunch() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeTranscriptPersistence-")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let promptText = "remember this transcript after relaunch"
        let responseText = "persisted assistant reply"

        var app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = projectURL.path
        app.launchEnvironment["PI_NATIVE_MOCK_RPC_RESPONSE"] = responseText
        app.launchEnvironment["PI_NATIVE_AUTOSUBMIT_AFTER_TYPING"] = "1"
        app.launchArguments.append("--ui-test-autosubmit")
        app.launch()

        // Select the project first so the new conversation persists in its
        // project session list across the reset-mode relaunch fixture.
        let projectRow = app.buttons["project.row"].firstMatch
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5))
        projectRow.click()
        let prompt = app.textViews["composer.textEditor"].firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.click()
        app.typeText(promptText)

        let userMessage = app.staticTexts["transcript.userMessage"]
        XCTAssertTrue(userMessage.waitForExistence(timeout: 10))
        XCTAssertTrue((userMessage.value as? String)?.contains(promptText) == true)

        let assistantMessage = app.staticTexts["transcript.assistantMessage"]
        XCTAssertTrue(assistantMessage.waitForExistence(timeout: 10))
        XCTAssertTrue((assistantMessage.value as? String)?.contains(responseText) == true)
        app.terminate()

        app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = projectURL.path
        app.launchEnvironment["PI_NATIVE_MOCK_RPC_RESPONSE"] = responseText
        app.launch()

        let restoredUserMessage = app.staticTexts["transcript.userMessage"]
        XCTAssertTrue(restoredUserMessage.waitForExistence(timeout: 10))
        XCTAssertTrue((restoredUserMessage.value as? String)?.contains(promptText) == true)

        let restoredAssistantMessage = app.staticTexts["transcript.assistantMessage"]
        XCTAssertTrue(restoredAssistantMessage.waitForExistence(timeout: 10))
        XCTAssertTrue((restoredAssistantMessage.value as? String)?.contains(responseText) == true)
    }

    func testSelectedChatIsReadyWhileRPCStartupIsStalled() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeReadiness-")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = projectURL.path
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_CHAT_TITLE"] = "seed readiness chat"
        app.launchEnvironment["PI_NATIVE_TEST_RPC_STALL"] = "1"
        app.launch()

        let chatTitle = app.staticTexts["chat.title"].firstMatch
        XCTAssertTrue(chatTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(chatTitle.value as? String, "seed readiness chat")

        // 2119: REQ-005.1.1
        let composer = app.textViews["composer.textEditor"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertTrue(composer.isHittable)
        // Type without clicking the composer first; the selected chat must request focus on display.
        app.typeText("typing is ready")
        XCTAssertTrue((composer.value as? String)?.contains("typing is ready") == true)

        // 2119: REQ-005.1.2
        let modelPicker = app.descendants(matching: .any)["composer.modelPicker"].firstMatch
        XCTAssertTrue(modelPicker.waitForExistence(timeout: 5))
        XCTAssertTrue(modelPicker.isEnabled)
        XCTAssertTrue(modelPicker.isHittable)
        modelPicker.click()
        XCTAssertTrue(app.popovers.firstMatch.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])

        // 2119: REQ-005.1.3
        let effortPicker = app.descendants(matching: .any)["composer.effortPicker"].firstMatch
        XCTAssertTrue(effortPicker.waitForExistence(timeout: 5))
        XCTAssertTrue(effortPicker.isEnabled)
        XCTAssertTrue(effortPicker.isHittable)
        effortPicker.click()
        XCTAssertTrue(app.popovers.firstMatch.waitForExistence(timeout: 5))

        XCTAssertFalse(app.staticTexts["chat.rpcStatus"].exists)
        XCTAssertTrue(composer.isHittable)
    }


    func testReturningToChatRestoresRecentTranscriptContent() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeTranscriptRestore-")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = projectURL.path
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_CHAT_TITLE"] = "newest restoration chat"
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_OLDER_CHAT_TITLE"] = "older restoration chat"
        app.launchEnvironment["PI_NATIVE_TEST_LONG_TRANSCRIPT"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_RPC_STALL"] = "1"
        app.launch()

        let newestChat = app.buttons["newest restoration chat"].firstMatch
        XCTAssertTrue(newestChat.waitForExistence(timeout: 10))
        newestChat.click()
        let oldestContent = app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "Older transcript line 1 for newest restoration chat", "Older transcript line 1 for newest restoration chat")).firstMatch
        let latestContent = app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "Latest restored content for newest restoration chat", "Latest restored content for newest restoration chat")).firstMatch
        XCTAssertTrue(oldestContent.waitForExistence(timeout: 5))
        XCTAssertTrue(latestContent.waitForExistence(timeout: 5))
        XCTAssertTrue(latestContent.isHittable)

        let olderChat = app.buttons["older restoration chat"].firstMatch
        XCTAssertTrue(olderChat.waitForExistence(timeout: 10))
        olderChat.click()
        XCTAssertEqual(app.staticTexts["chat.title"].firstMatch.value as? String, "older restoration chat")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "Latest restored content for older restoration chat", "Latest restored content for older restoration chat")).firstMatch.waitForExistence(timeout: 5))

        // 2119: REQ-003.1.2
        newestChat.click()
        XCTAssertEqual(app.staticTexts["chat.title"].firstMatch.value as? String, "newest restoration chat")
        XCTAssertTrue(latestContent.waitForExistence(timeout: 5))
        XCTAssertTrue(latestContent.isHittable)
    }

    func testUpdatingSelectedChatRevealsBottomOfLongTranscript() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeBottomReveal-")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let finalResponseMarker = "Unique final bottom marker"
        let tallResponse = ((1...60).map { "Streaming response line \($0)" } + [finalResponseMarker])
            .joined(separator: "\n")
        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = projectURL.path
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_CHAT_TITLE"] = "bottom reveal chat"
        app.launchEnvironment["PI_NATIVE_TEST_LONG_TRANSCRIPT"] = "1"
        app.launchEnvironment["PI_NATIVE_MOCK_RPC_RESPONSE"] = tallResponse
        app.launch()

        XCTAssertTrue(app.staticTexts["chat.title"].firstMatch.waitForExistence(timeout: 10))
        let previousBottom = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "Latest restored content for bottom reveal chat", "Latest restored content for bottom reveal chat")
        ).firstMatch
        XCTAssertTrue(previousBottom.waitForExistence(timeout: 5))
        XCTAssertTrue(previousBottom.isHittable)
        let composer = app.textViews["composer.textEditor"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.click()
        app.typeText("append at the bottom")
        app.buttons["Send"].firstMatch.click()

        // 2119: REQ-003.1.4
        let bottomResponse = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", finalResponseMarker, finalResponseMarker)
        ).firstMatch
        XCTAssertTrue(bottomResponse.waitForExistence(timeout: 10))
        XCTAssertTrue(bottomResponse.isHittable)
        XCTAssertFalse(previousBottom.isHittable, "The prior transcript bottom must leave the viewport after revealing the tall appended response.")
    }

    func testSidebarChatRowSelectsChatFromVisibleRowTarget() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeChatRowTarget-")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = projectURL.path
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_CHAT_TITLE"] = "target newest chat"
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_OLDER_CHAT_TITLE"] = "target older chat"
        app.launchEnvironment["PI_NATIVE_TEST_RPC_STALL"] = "1"
        app.launch()

        let olderChat = app.buttons["target older chat"].firstMatch
        XCTAssertTrue(olderChat.waitForExistence(timeout: 10))
        olderChat.click()
        XCTAssertEqual(app.staticTexts["chat.title"].firstMatch.value as? String, "target older chat")

        // 2119: REQ-003.2.2
        let newestChat = app.buttons["target newest chat"].firstMatch
        XCTAssertTrue(newestChat.waitForExistence(timeout: 5))
        // 2119: REQ-003.2.2
        // Leading, center, and trailing-corner samples verify the broad row
        // target while remaining outside the explicitly visible control area.
        for rowOffset in [
            CGVector(dx: 0.05, dy: 0.50),
            CGVector(dx: 0.50, dy: 0.50),
            CGVector(dx: 0.90, dy: 0.05),
        ] {
            olderChat.click()
            newestChat.coordinate(withNormalizedOffset: rowOffset).click()
            XCTAssertEqual(app.staticTexts["chat.title"].firstMatch.value as? String, "target newest chat")
        }

        olderChat.click()
        newestChat.hover()
        let archiveButton = app.buttons["chat.archiveButton"].firstMatch
        XCTAssertTrue(archiveButton.waitForExistence(timeout: 5))
        XCTAssertTrue(archiveButton.isHittable)
        let nonControlChatPoint = newestChat.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.50))
        nonControlChatPoint.click()
        XCTAssertEqual(app.staticTexts["chat.title"].firstMatch.value as? String, "target newest chat")

        olderChat.click()
        newestChat.hover()
        // 2119: REQ-003.2.2
        archiveButton.click()
        XCTAssertEqual(app.staticTexts["chat.title"].firstMatch.value as? String, "target older chat")
        XCTAssertFalse(newestChat.exists, "The visible archive control must perform its own action instead of selecting the chat row.")
    }

    func testProjectRowSelectsNewestVisibleUnpinnedChat() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeProjectSelection-")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let otherProjectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeOtherProject-")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: otherProjectURL, withIntermediateDirectories: true)

        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = projectURL.path
        app.launchEnvironment["PI_NATIVE_TEST_OTHER_PROJECT_PATH"] = otherProjectURL.path
        app.launchEnvironment["PI_NATIVE_TEST_OTHER_PROJECT_CHAT_TITLE"] = "globally newest other project chat"
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_CHAT_TITLE"] = "newest visible project chat"
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_OLDER_CHAT_TITLE"] = "older visible project chat"
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_ARCHIVED_CHAT_TITLE"] = "newer archived project chat"
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_PINNED_CHAT_TITLE"] = "newest pinned project chat"
        app.launchEnvironment["PI_NATIVE_TEST_DIFF_STATS"] = "1,0"
        app.launchEnvironment["PI_NATIVE_TEST_RPC_STALL"] = "1"
        app.launch()

        let pinnedChat = app.buttons["newest pinned project chat"].firstMatch
        XCTAssertTrue(pinnedChat.waitForExistence(timeout: 10))
        pinnedChat.click()
        let chatTitle = app.staticTexts["chat.title"].firstMatch
        XCTAssertTrue(chatTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(chatTitle.value as? String, "newest pinned project chat")

        // 2119: REQ-003.2.1
        // 2119: REQ-003.3.1
        // 2119: REQ-003.3.2
        // 2119: REQ-003.3.3
        let projectRow = app.buttons["project.row"].firstMatch
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5))
        // 2119: REQ-003.2.1
        let projectNewChatButton = app.buttons["project.newChatButton"].firstMatch
        let diffPill = app.buttons["project.diffPill"].firstMatch
        // Leading, center, and trailing-corner samples verify the broad row
        // target while remaining outside the explicitly visible controls.
        for rowOffset in [
            CGVector(dx: 0.05, dy: 0.50),
            CGVector(dx: 0.50, dy: 0.50),
            CGVector(dx: 0.90, dy: 0.05),
        ] {
            pinnedChat.click()
            projectRow.coordinate(withNormalizedOffset: rowOffset).click()
            XCTAssertEqual(chatTitle.value as? String, "newest visible project chat")
            XCTAssertNotEqual(chatTitle.value as? String, "newer archived project chat")
            XCTAssertNotEqual(chatTitle.value as? String, "newest pinned project chat")
            XCTAssertNotEqual(chatTitle.value as? String, "globally newest other project chat")
        }

        pinnedChat.click()
        projectRow.hover()
        XCTAssertTrue(projectNewChatButton.waitForExistence(timeout: 5))
        XCTAssertTrue(projectNewChatButton.isHittable)
        let nonControlProjectPoint = projectRow.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.50))
        nonControlProjectPoint.click()
        XCTAssertEqual(chatTitle.value as? String, "newest visible project chat")

        pinnedChat.click()
        projectRow.hover()
        XCTAssertTrue(diffPill.isHittable)
        // 2119: REQ-003.2.1
        diffPill.click()
        XCTAssertTrue(app.staticTexts["Pending Changes"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])

        projectRow.hover()
        // 2119: REQ-003.2.1
        projectNewChatButton.click()
        XCTAssertTrue(app.staticTexts["What should we work on?"].waitForExistence(timeout: 5))
    }

    func testHiddenHoverControlsDoNotBlockSidebarRowSelection() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeHiddenSidebarControls-")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = projectURL.path
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_CHAT_TITLE"] = "hidden-control newest chat"
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_OLDER_CHAT_TITLE"] = "hidden-control older chat"
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_PINNED_CHAT_TITLE"] = "hidden-control pinned chat"
        app.launchEnvironment["PI_NATIVE_TEST_DIFF_STATS"] = "1,0"
        app.launchEnvironment["PI_NATIVE_TEST_RPC_STALL"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_HIDE_SIDEBAR_HOVER_CONTROLS"] = "1"
        app.launch()

        let chatTitle = app.staticTexts["chat.title"].firstMatch
        let olderChat = app.buttons["hidden-control older chat"].firstMatch
        let newestChat = app.buttons["hidden-control newest chat"].firstMatch
        XCTAssertTrue(olderChat.waitForExistence(timeout: 10))
        XCTAssertTrue(newestChat.waitForExistence(timeout: 5))
        olderChat.click()

        // 2119: REQ-003.2.3
        newestChat.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.50)).click()
        XCTAssertEqual(chatTitle.value as? String, "hidden-control newest chat")
        XCTAssertFalse(app.buttons["chat.archiveButton"].firstMatch.isHittable)

        let pinnedChat = app.buttons["hidden-control pinned chat"].firstMatch
        XCTAssertTrue(pinnedChat.waitForExistence(timeout: 5))
        pinnedChat.click()
        let projectRow = app.buttons["project.row"].firstMatch
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5))

        // 2119: REQ-003.2.3
        projectRow.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.50)).click()
        XCTAssertEqual(chatTitle.value as? String, "hidden-control newest chat")
        XCTAssertFalse(app.buttons["project.newChatButton"].firstMatch.isHittable)
        XCTAssertFalse(app.buttons["project.diffPill"].firstMatch.isHittable)
    }

}
