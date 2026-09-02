import XCTest

final class ShellChromeUITests: PiNativeUITestCase {
    func testRightPaneToolbarToggleOnlyAppearsWhenPaneIsOpen() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        app.launch()

        let rightToggle = app.buttons["shell.toggleRightPaneButton"]
        XCTAssertFalse(rightToggle.exists)

        app.typeKey("t", modifierFlags: [.command])

        XCTAssertTrue(app.staticTexts["Browser"].waitForExistence(timeout: 5))
        XCTAssertTrue(rightToggle.waitForExistence(timeout: 5))
        rightToggle.click()
        XCTAssertFalse(rightToggle.waitForExistence(timeout: 1))
    }

    func testSidebarTogglesKeepCenterChatVisible() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_CHAT_TITLE"] = "shell visible chat"
        app.launchEnvironment["PI_NATIVE_MOCK_RPC_RESPONSE"] = "shell layout response"
        app.launch()

        // 2119: REQ-004.1.1
        let centerTitle = app.staticTexts["chat.title"].firstMatch
        let transcriptMessage = app.staticTexts["shell visible chat"].firstMatch
        let centerComposer = app.textViews["composer.textEditor"].firstMatch
        func assertCenterUsable(file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertTrue(centerTitle.waitForExistence(timeout: 5), file: file, line: line)
            XCTAssertEqual(centerTitle.value as? String, "shell visible chat", file: file, line: line)
            XCTAssertTrue(transcriptMessage.waitForExistence(timeout: 5), file: file, line: line)
            XCTAssertTrue(transcriptMessage.isHittable, file: file, line: line)
            XCTAssertTrue(centerComposer.waitForExistence(timeout: 5), file: file, line: line)
            XCTAssertTrue(centerComposer.isHittable, file: file, line: line)
            let centerElements = [centerTitle, transcriptMessage, centerComposer]
            for element in centerElements {
                assertElementFullyInsideWindow(element, in: app, file: file, line: line)
            }
            let visibleShellRegions = [
                app.descendants(matching: .any)["shell.leftPane"].firstMatch,
                app.descendants(matching: .any)["shell.rightPane"].firstMatch
            ].filter { $0.exists && !$0.frame.isEmpty }
            for element in centerElements {
                for region in visibleShellRegions {
                    assertElementDoesNotOverlap(element, region, file: file, line: line)
                }
            }
        }

        assertCenterUsable()

        let hideLeft = app.buttons["Hide Sidebar"]
        XCTAssertTrue(hideLeft.waitForExistence(timeout: 5))
        hideLeft.click()
        assertCenterUsable()

        let showLeft = app.buttons["Show Sidebar"]
        XCTAssertTrue(showLeft.waitForExistence(timeout: 5))
        showLeft.click()
        assertCenterUsable()

        app.typeKey("t", modifierFlags: [.command])
        let rightToggle = app.buttons["shell.toggleRightPaneButton"]
        XCTAssertTrue(rightToggle.waitForExistence(timeout: 5))
        assertCenterUsable()

        rightToggle.click()
        assertCenterUsable()

        centerComposer.click()
        app.typeText("usable after shell toggles")
        XCTAssertTrue((centerComposer.value as? String)?.contains("usable after shell toggles") == true)
        XCTAssertTrue(transcriptMessage.isHittable)
        assertElementFullyInsideWindow(centerComposer, in: app)
    }

    func testBrowserShortcutOpensBrowserPane() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        app.launch()

        app.typeKey("t", modifierFlags: [.command])

        XCTAssertTrue(app.staticTexts["Browser"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Start browsing"].waitForExistence(timeout: 5))
    }

}
