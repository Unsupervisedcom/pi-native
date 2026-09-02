import XCTest

final class NewChatUITests: PiNativeUITestCase {
    func testNewChatWithMockRPCResponds() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        app.launchEnvironment["PI_NATIVE_MOCK_RPC_RESPONSE"] = "smoke test ok"
        app.launchEnvironment["PI_NATIVE_AUTOSUBMIT_AFTER_TYPING"] = "1"
        app.launchArguments.append("--ui-test-autosubmit")
        app.launch()

        clickNewChat(in: app)

        let prompt = app.textFields["newChat.promptEditor"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.click()
        let promptText = "i want to make some edits to the sidebar"
        app.typeText(promptText)

        // Autosubmit fires shortly after typing stops and navigates away from
        // NewChatStartView into the live conversation view, so don't re-query
        // the (now-gone) prompt field afterwards — assert on the transcript
        // instead, which is the real signal that the prompt was sent and
        // answered.
        XCTAssertTrue(app.staticTexts["transcript.userMessage"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["transcript.assistantMessage"].waitForExistence(timeout: 10))
    }


    func testNewChatCanStartWithoutProject() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        app.launchEnvironment["PI_NATIVE_MOCK_RPC_RESPONSE"] = "projectless chat ok"
        app.launchEnvironment["PI_NATIVE_AUTOSUBMIT_AFTER_TYPING"] = "1"
        app.launchArguments.append("--ui-test-autosubmit")
        app.launch()

        clickNewChat(in: app)

        let projectPicker = app.buttons["newChat.projectPicker"]
        XCTAssertTrue(projectPicker.waitForExistence(timeout: 5))
        projectPicker.click()

        let prompt = app.textFields["newChat.promptEditor"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.click()
        app.typeText("start without a project")

        let userMessage = app.staticTexts["transcript.userMessage"]
        XCTAssertTrue(userMessage.waitForExistence(timeout: 10))
        XCTAssertTrue((userMessage.value as? String)?.contains("start without a project") == true)

        let assistantMessage = app.staticTexts["transcript.assistantMessage"]
        XCTAssertTrue(assistantMessage.waitForExistence(timeout: 10))
        XCTAssertTrue((assistantMessage.value as? String)?.contains("projectless chat ok") == true)

        XCTAssertTrue(app.buttons["chat.promoteProjectLink"].waitForExistence(timeout: 5))
    }
    /// Exercises the real `pi --mode rpc` process end-to-end (no mock
    /// response) against this repo checkout as the project folder, asking a
    /// real question and waiting for a real LLM reply. Requires `pi` on
    /// PATH and configured API credentials; slower and more flaky than the
    /// mock smoke test above by nature of hitting a live model, so keep the
    /// mock test as the fast default and use this one for confidence that
    /// the whole RPC pipeline still works against a real `pi`.
    @MainActor
    func testNewChatWithLiveRPCResponds() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        app.launchEnvironment["PI_NATIVE_AUTOSUBMIT_AFTER_TYPING"] = "1"
        app.launchArguments.append("--ui-test-autosubmit")
        app.launch()

        clickNewChat(in: app)

        let prompt = app.textFields["newChat.promptEditor"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.click()
        app.typeText("i want to make some edits to the sidebar")

        let userMessage = app.staticTexts["transcript.userMessage"]
        XCTAssertTrue(userMessage.waitForExistence(timeout: 10))

        // Real model turnaround (process spawn + tool-call planning + first
        // token) is much slower than the mock's fixed 300ms delay.
        let assistantMessage = app.staticTexts["transcript.assistantMessage"]
        XCTAssertTrue(assistantMessage.waitForExistence(timeout: 60))
        print("=== ASSISTANT REPLY ===")
        print(assistantMessage.value ?? assistantMessage.label)
        print("=== END ASSISTANT REPLY ===")

        // The composer model picker should be populated from pi's real
        // get_state/get_available_models RPC commands by now — not stuck on
        // the disabled "Model" placeholder.
        let modelPicker = app.menuButtons["composer.modelPicker"]
        XCTAssertTrue(modelPicker.waitForExistence(timeout: 10))
        print("=== MODEL PICKER TITLE: \(modelPicker.title) ===")
        XCTAssertFalse(modelPicker.title.isEmpty)
        XCTAssertNotEqual(modelPicker.title, "Model")
    }
}
