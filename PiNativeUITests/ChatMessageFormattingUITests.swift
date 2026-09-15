import XCTest

final class ChatMessageFormattingUITests: PiNativeUITestCase {
    // 2119: REQ-014.2.1
    func testConsecutiveActivitySummariesRenderAsSeparatedRows() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeChatFormatting-")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = projectURL.path
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_CHAT_TITLE"] = "chat formatting fixture"
        app.launchEnvironment["PI_NATIVE_TEST_CHAT_FORMATTING_FIXTURE"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_RPC_STALL"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["chat formatting fixture"].firstMatch.waitForExistence(timeout: 10))
        let firstSummary = app.staticTexts["transcript.activitySummary.0"].firstMatch
        let secondSummary = app.staticTexts["transcript.activitySummary.1"].firstMatch
        XCTAssertTrue(firstSummary.waitForExistence(timeout: 5))
        XCTAssertTrue(secondSummary.waitForExistence(timeout: 5))

        XCTAssertGreaterThan(
            secondSummary.frame.minY,
            firstSummary.frame.maxY,
            "Consecutive activity summaries should have visible vertical space between their rows."
        )
    }
}
