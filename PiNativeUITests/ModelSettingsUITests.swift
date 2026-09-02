import XCTest

final class ModelSettingsUITests: PiNativeUITestCase {
    func testModelsSettingsSearchAndFavoriteControls() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        app.launchEnvironment["PI_NATIVE_TEST_MODEL_FAVORITES_FILE"] = NSTemporaryDirectory() + "model-favorites-settings-\(UUID().uuidString).json"
        app.launchEnvironment["PI_NATIVE_TEST_DEFAULT_PROVIDER"] = "openrouter"
        app.launchEnvironment["PI_NATIVE_TEST_DEFAULT_MODEL"] = "alpha"
        app.launchEnvironment["PI_NATIVE_TEST_MODEL_CATALOG"] = #"[{"provider":"openrouter","id":"alpha","name":"Alpha Model"},{"provider":"openai","id":"alpha","name":"Direct Alpha Model"},{"provider":"openai","id":"beta","name":"Beta Model"}]"#
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("YES")
        app.launch()

        app.buttons["sidebar.settingsButton"].click()
        app.buttons["Models"].firstMatch.click()

        // 2119: REQ-007.1.1
        XCTAssertTrue(app.staticTexts["Models"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Alpha Model"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Direct Alpha Model"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Beta Model"].waitForExistence(timeout: 5))
        let favoriteHeader = app.staticTexts["settings.models.favoritesSection"]
        let availableModelsHeader = app.staticTexts["settings.models.availableModelsSection"]
        // 2119: REQ-007.1.9
        XCTAssertTrue(favoriteHeader.waitForExistence(timeout: 5))
        XCTAssertTrue(availableModelsHeader.waitForExistence(timeout: 5))
        let favoriteRow = app.descendants(matching: .any)["settings.models.row.openrouter/alpha"]
        let directAlphaRow = app.descendants(matching: .any)["settings.models.row.openai/alpha"]
        XCTAssertTrue(favoriteRow.waitForExistence(timeout: 5))
        XCTAssertTrue(directAlphaRow.waitForExistence(timeout: 5))
        // 2119: REQ-007.1.9
        XCTAssertLessThan(favoriteHeader.frame.maxY, favoriteRow.frame.minY)
        XCTAssertLessThan(favoriteRow.frame.maxY, availableModelsHeader.frame.minY)
        XCTAssertLessThan(availableModelsHeader.frame.maxY, directAlphaRow.frame.minY)
        // 2119: REQ-007.1.10
        XCTAssertLessThan(favoriteHeader.frame.maxY, favoriteRow.frame.minY)
        XCTAssertLessThan(favoriteRow.frame.maxY, availableModelsHeader.frame.minY)
        XCTAssertLessThan(favoriteHeader.frame.maxY, directAlphaRow.frame.minY)
        XCTAssertLessThan(availableModelsHeader.frame.maxY, directAlphaRow.frame.minY)
        // 2119: REQ-007.1.11
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "settings.models.row.openrouter/alpha").count, 1)
        // 2119: REQ-007.1.3
        let alphaButton = app.buttons["settings.models.favorite.openrouter/alpha"]
        let directAlphaButton = app.buttons["settings.models.favorite.openai/alpha"]
        let betaButton = app.buttons["settings.models.favorite.openai/beta"]
        XCTAssertTrue(alphaButton.waitForExistence(timeout: 5))
        XCTAssertTrue(directAlphaButton.waitForExistence(timeout: 5))
        XCTAssertTrue(betaButton.waitForExistence(timeout: 5))
        assertElementFullyInsideWindow(alphaButton, in: app)
        assertElementFullyInsideWindow(directAlphaButton, in: app)
        assertElementFullyInsideWindow(betaButton, in: app)
        XCTAssertTrue(directAlphaButton.isHittable)
        XCTAssertTrue(betaButton.isHittable)
        // 2119: REQ-007.1.5
        XCTAssertEqual(alphaButton.label, "Alpha Model is the only favorite")
        XCTAssertTrue(app.buttons["Add Direct Alpha Model to favorites"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add Beta Model to favorites"].waitForExistence(timeout: 5))
        // 2119: REQ-007.3.7
        XCTAssertFalse(alphaButton.isEnabled)

        betaButton.click()
        let betaRow = app.descendants(matching: .any)["settings.models.row.openai/beta"]
        XCTAssertTrue(betaRow.waitForExistence(timeout: 5))
        // 2119: REQ-007.1.9
        XCTAssertLessThan(favoriteHeader.frame.maxY, favoriteRow.frame.minY)
        XCTAssertLessThan(betaRow.frame.maxY, availableModelsHeader.frame.minY)
        XCTAssertLessThan(availableModelsHeader.frame.maxY, directAlphaRow.frame.minY)
        // 2119: REQ-007.1.10
        XCTAssertLessThan(favoriteRow.frame.maxY, availableModelsHeader.frame.minY)
        XCTAssertLessThan(betaRow.frame.maxY, availableModelsHeader.frame.minY)
        XCTAssertLessThan(favoriteHeader.frame.maxY, directAlphaRow.frame.minY)
        XCTAssertLessThan(availableModelsHeader.frame.maxY, directAlphaRow.frame.minY)
        XCTAssertTrue(alphaButton.isEnabled)
        XCTAssertEqual(alphaButton.label, "Remove Alpha Model from favorites")
        // 2119: REQ-007.1.11
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "settings.models.row.openrouter/alpha").count, 1)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "settings.models.row.openai/beta").count, 1)
        // 2119: REQ-007.1.4
        app.buttons["settings.models.favorite.openrouter/alpha"].click()

        // 2119: REQ-007.2.1
        let search = app.textFields["settings.models.searchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("alpha")
        let alphaFavoriteButton = app.buttons["settings.models.favorite.openrouter/alpha"]
        let directAlphaFavoriteButton = app.buttons["settings.models.favorite.openai/alpha"]
        XCTAssertTrue(alphaFavoriteButton.waitForExistence(timeout: 5))
        XCTAssertTrue(directAlphaFavoriteButton.waitForExistence(timeout: 5))
        // 2119: REQ-007.2.1
        XCTAssertFalse(app.descendants(matching: .any)["settings.models.row.openai/beta"].exists)
        // 2119: REQ-007.2.3
        XCTAssertEqual(alphaFavoriteButton.label, "Add Alpha Model to favorites")
        XCTAssertEqual(directAlphaFavoriteButton.label, "Add Direct Alpha Model to favorites")
        app.buttons["Clear model search"].click()
        search.click()
        search.typeText("beta")
        XCTAssertTrue(app.staticTexts["Beta Model"].waitForExistence(timeout: 5))
        // 2119: REQ-007.2.1
        XCTAssertFalse(app.descendants(matching: .any)["settings.models.row.openrouter/alpha"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["settings.models.row.openai/alpha"].exists)
        XCTAssertFalse(app.staticTexts["Alpha Model"].exists)
        // 2119: REQ-007.2.3
        let filteredBetaButton = app.buttons["settings.models.favorite.openai/beta"]
        XCTAssertEqual(filteredBetaButton.label, "Beta Model is the only favorite")
        XCTAssertFalse(filteredBetaButton.isEnabled)
    }

    func testUnavailableFavoriteIsVisibleInModelsSettings() throws {
        let favoritesFile = NSTemporaryDirectory() + "model-favorites-unavailable-\(UUID().uuidString).json"
        try #"[{"provider":"openrouter","id":"stale","name":"Stale Model"}]"#.write(toFile: favoritesFile, atomically: true, encoding: .utf8)

        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        app.launchEnvironment["PI_NATIVE_TEST_MODEL_FAVORITES_FILE"] = favoritesFile
        app.launchEnvironment["PI_NATIVE_TEST_MODEL_CATALOG"] = "[]"
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("YES")
        app.launch()

        app.buttons["sidebar.settingsButton"].click()
        app.buttons["Models"].firstMatch.click()
        // 2119: REQ-007.3.5
        XCTAssertTrue(app.staticTexts["settings.models.favoritesSection"].waitForExistence(timeout: 5))
        let staleFavoriteRow = app.descendants(matching: .any)["settings.models.unavailable.openrouter/stale"]
        XCTAssertTrue(staleFavoriteRow.waitForExistence(timeout: 5))
        let staleFavoriteName = app.staticTexts["Stale Model"]
        let unavailableIndicator = app.staticTexts["Unavailable"]
        XCTAssertTrue(staleFavoriteName.waitForExistence(timeout: 5))
        XCTAssertTrue(unavailableIndicator.waitForExistence(timeout: 5))
        XCTAssertTrue(staleFavoriteRow.frame.contains(staleFavoriteName.frame))
        XCTAssertTrue(staleFavoriteRow.frame.contains(unavailableIndicator.frame))
        let soleUnavailableFavorite = app.buttons["Stale Model is the only favorite"]
        // 2119: REQ-007.3.7
        XCTAssertTrue(soleUnavailableFavorite.waitForExistence(timeout: 5))
        XCTAssertFalse(soleUnavailableFavorite.isEnabled)
        XCTAssertTrue(app.staticTexts["No models available"].waitForExistence(timeout: 5))
    }

    func testModelsSettingsCatalogStatesAreVisible() throws {
        let fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeLoadingCatalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        let script = fixtureDirectory.appendingPathComponent("slow-pi-catalog.sh")
        try """
        #!/bin/sh
        sleep 4
        printf 'provider model context max-out thinking images\\n'
        printf 'openrouter alpha 128K 16K yes no\\n'
        """.write(to: script, atomically: true, encoding: .utf8)

        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        app.launchEnvironment["PI_NATIVE_TEST_MODEL_FAVORITES_FILE"] = fixtureDirectory.appendingPathComponent("favorites.json").path
        app.launchEnvironment["PI_NATIVE_TEST_PI_EXECUTABLE"] = "/bin/sh"
        app.launchEnvironment["PI_NATIVE_TEST_PI_ARGUMENTS"] = String(
            decoding: try JSONEncoder().encode([script.path]),
            as: UTF8.self
        )
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("YES")
        app.launch()
        app.buttons["sidebar.settingsButton"].click()
        app.buttons["Models"].firstMatch.click()
        // 2119: REQ-007.1.6
        XCTAssertTrue(app.staticTexts["Loading models…"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["alpha"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Loading models…"].exists)
    }

    func testModelsSettingsShowsEmptyAndErrorFromPiCatalogProcess() throws {
        let outcomes: [(name: String, body: String, expectedText: String, favoritesJSON: String)] = [
            ("empty", """
            while IFS= read -r line; do
              request_id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
              command=$(printf '%s' "$line" | sed -E 's/.*"type":"([^"]+)".*/\\1/')
              data="}"
              case "$command" in
                get_available_models) data=',"data":{"models":[]}}' ;;
              esac
              printf '{"id":%s,"type":"response","command":"%s","success":true%s\\n' "$request_id" "$command" "$data"
            done
            """, "No models available", "[]"),
            ("empty-with-favorite", """
            while IFS= read -r line; do
              request_id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
              command=$(printf '%s' "$line" | sed -E 's/.*"type":"([^"]+)".*/\\1/')
              data="}"
              case "$command" in
                get_available_models) data=',"data":{"models":[]}}' ;;
              esac
              printf '{"id":%s,"type":"response","command":"%s","success":true%s\\n' "$request_id" "$command" "$data"
            done
            """, "No models available", #"[{"provider":"openrouter","id":"stale","name":"Stale Model"}]"#),
            ("error", "echo 'simulated Pi catalog failure' >&2; exit 42", "Could not load models", "[]")
        ]

        for outcome in outcomes {
            let fixtureDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PiNativeCatalogState-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
            let script = fixtureDirectory.appendingPathComponent("pi-catalog.sh")
            try "#!/bin/sh\n\(outcome.body)\n".write(to: script, atomically: true, encoding: .utf8)

            let app = XCUIApplication()
            app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
            app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .path
            let favoritesFile = fixtureDirectory.appendingPathComponent("favorites.json")
            try outcome.favoritesJSON.write(to: favoritesFile, atomically: true, encoding: .utf8)
            app.launchEnvironment["PI_NATIVE_TEST_MODEL_FAVORITES_FILE"] = favoritesFile.path
            app.launchEnvironment["PI_NATIVE_TEST_PI_EXECUTABLE"] = "/bin/sh"
            app.launchEnvironment["PI_NATIVE_TEST_PI_ARGUMENTS"] = String(
                decoding: try JSONEncoder().encode([script.path]),
                as: UTF8.self
            )
            app.launchArguments.append("-ApplePersistenceIgnoreState")
            app.launchArguments.append("YES")
            app.launch()
            app.buttons["sidebar.settingsButton"].click()
            app.buttons["Models"].firstMatch.click()
            if outcome.name.hasPrefix("empty") {
                // 2119: REQ-007.1.7
                XCTAssertTrue(app.staticTexts[outcome.expectedText].waitForExistence(timeout: 8))
                XCTAssertEqual(
                    app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "settings.models.row.")).count,
                    0
                )
                if outcome.name == "empty-with-favorite" {
                    XCTAssertTrue(app.staticTexts["settings.models.favoritesSection"].waitForExistence(timeout: 3))
                    XCTAssertTrue(app.staticTexts["Stale Model"].waitForExistence(timeout: 3))
                }
            } else {
                // 2119: REQ-007.1.8
                XCTAssertTrue(app.staticTexts[outcome.expectedText].waitForExistence(timeout: 8))
                XCTAssertTrue(app.staticTexts["simulated Pi catalog failure"].waitForExistence(timeout: 3))
            }
            app.terminate()
        }
    }

    func testComposerRejectsReturnAndSendWithoutASelectedModel() throws {
        let fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeComposerNoModel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }
        try "[]".write(to: fixtureDirectory.appendingPathComponent("favorites.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: fixtureDirectory.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)

        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_CHAT_TITLE"] = "No model chat"
        app.launchEnvironment["PI_NATIVE_TEST_MODEL_FAVORITES_FILE"] = fixtureDirectory.appendingPathComponent("favorites.json").path
        app.launchEnvironment["PI_NATIVE_TEST_MODEL_CATALOG"] = "[]"
        app.launchEnvironment["PI_CODING_AGENT_DIR"] = fixtureDirectory.path
        app.launchEnvironment["PI_NATIVE_TEST_PI_EXECUTABLE"] = "/tmp/pinative-missing-no-model-pi"
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("YES")
        app.launch()

        let composer = app.textViews["composer.textEditor"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        let modelPicker = app.buttons["composer.modelPicker"]
        XCTAssertTrue(modelPicker.waitForExistence(timeout: 5))
        XCTAssertEqual(modelPicker.value as? String, "Unavailable")
        // 2119: REQ-007.4.7
        modelPicker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertFalse(app.popovers.firstMatch.waitForExistence(timeout: 0.5))
        let effortPicker = app.buttons["composer.effortPicker"]
        XCTAssertTrue(effortPicker.waitForExistence(timeout: 5))
        XCTAssertEqual(effortPicker.value as? String, "Unavailable")
        // 2119: REQ-007.4.7
        effortPicker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertFalse(app.popovers.firstMatch.waitForExistence(timeout: 0.5))
        let initialMessageCount = app.staticTexts.matching(identifier: "transcript.userMessage").count
        composer.click()
        app.typeText("This must wait for a model")
        let send = app.buttons["Send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        // 2119: REQ-007.4.7
        XCTAssertFalse(send.isEnabled)
        send.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(app.staticTexts.matching(identifier: "transcript.userMessage").count, initialMessageCount)

        composer.click()
        composer.typeKey(.return, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)
        // 2119: REQ-007.4.7
        XCTAssertEqual(app.staticTexts.matching(identifier: "transcript.userMessage").count, initialMessageCount)
    }

    func testComposerLoadsFavoriteCatalogBeforeConversationRPCStarts() throws {
        let fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeComposerCatalogStartup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let script = fixtureDirectory.appendingPathComponent("pi-catalog.sh")
        try """
        #!/bin/sh
        printf 'provider model context max-out thinking images\\n'
        printf 'openrouter alpha 128K 16K yes no\\n'
        """.write(to: script, atomically: true, encoding: .utf8)
        let favoritesFile = fixtureDirectory.appendingPathComponent("favorites.json")
        try #"[{"provider":"openrouter","id":"alpha","name":"Alpha Model"}]"#
            .write(to: favoritesFile, atomically: true, encoding: .utf8)

        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_CHAT_TITLE"] = "Catalog startup chat"
        app.launchEnvironment["PI_NATIVE_TEST_MODEL_FAVORITES_FILE"] = favoritesFile.path
        app.launchEnvironment["PI_NATIVE_TEST_PI_EXECUTABLE"] = "/bin/sh"
        app.launchEnvironment["PI_NATIVE_TEST_PI_ARGUMENTS"] = String(
            decoding: try JSONEncoder().encode([script.path]),
            as: UTF8.self
        )
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("YES")
        app.launch()

        let modelPicker = app.buttons["composer.modelPicker"]
        XCTAssertTrue(modelPicker.waitForExistence(timeout: 5))
        modelPicker.click()

        // 2119: REQ-007.4.1
        XCTAssertTrue(app.buttons["composer.modelFavorite.openrouter/alpha"].waitForExistence(timeout: 8))
    }

    func testComposerModelFavoritesAndSeparateEffortPicker() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        app.launchEnvironment["PI_NATIVE_MOCK_RPC_RESPONSE"] = "model picker ok"
        app.launchEnvironment["PI_NATIVE_TEST_THINKING_LEVELS"] = "low,high"
        let favoritesFile = NSTemporaryDirectory() + "model-favorites-composer-\(UUID().uuidString).json"
        try #"[{"provider":"openrouter","id":"alpha","name":"Alpha Model"},{"provider":"openrouter","id":"gamma","name":"Gamma Model"},{"provider":"openrouter","id":"stale","name":"Stale Model"}]"#.write(toFile: favoritesFile, atomically: true, encoding: .utf8)
        app.launchEnvironment["PI_NATIVE_TEST_MODEL_FAVORITES_FILE"] = favoritesFile
        app.launchEnvironment["PI_NATIVE_TEST_MODEL_CATALOG"] = #"[{"provider":"openrouter","id":"alpha","name":"Alpha Model"},{"provider":"openrouter","id":"gamma","name":"Gamma Model"},{"provider":"openai","id":"beta","name":"Beta Model"}]"#
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_CHAT_TITLE"] = "Model controls chat"
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("YES")
        app.launch()

        let modelPicker = app.buttons["composer.modelPicker"]
        let effortPicker = app.buttons["composer.effortPicker"]
        // 2119: REQ-007.5.1
        XCTAssertTrue(modelPicker.waitForExistence(timeout: 5))
        XCTAssertTrue(effortPicker.waitForExistence(timeout: 5))

        modelPicker.click()
        // 2119: REQ-007.4.1
        XCTAssertTrue(app.buttons["composer.modelFavorite.openrouter/alpha"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["composer.modelFavorite.openrouter/gamma"].waitForExistence(timeout: 5))
        // 2119: REQ-007.4.2
        XCTAssertFalse(app.buttons["composer.modelFavorite.openai/beta"].exists)
        XCTAssertFalse(app.buttons["composer.modelFavorite.mock/mock"].exists)
        // 2119: REQ-007.5.1
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "composer.effort.")).firstMatch.exists)
        let visibleFavoriteOptions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "composer.modelFavorite."))
        // 2119: REQ-007.4.2
        XCTAssertEqual(visibleFavoriteOptions.count, 2)
        // 2119: REQ-007.3.6
        // 2119: REQ-007.4.1
        XCTAssertFalse(app.buttons["composer.modelFavorite.openrouter/stale"].exists)
        // 2119: REQ-007.4.3
        let modelPopover = app.popovers.firstMatch
        let selectFavorites = modelPopover.buttons["composer.selectFavorites"]
        XCTAssertTrue(selectFavorites.waitForExistence(timeout: 5))
        let favoriteRows = [
            modelPopover.buttons["composer.modelFavorite.openrouter/alpha"],
            modelPopover.buttons["composer.modelFavorite.openrouter/gamma"]
        ]
        // 2119: REQ-007.4.3
        XCTAssertEqual(selectFavorites.label, "Select Favorites…")
        XCTAssertTrue(favoriteRows.allSatisfy { $0.exists })
        XCTAssertLessThan(favoriteRows.map { $0.frame.maxY }.max() ?? .infinity, selectFavorites.frame.minY)
        // 2119: REQ-007.4.4
        selectFavorites.click()
        XCTAssertTrue(app.textFields["settings.models.searchField"].waitForExistence(timeout: 5))
        app.buttons["Close Settings"].click()

        modelPicker.click()
        app.buttons["composer.modelFavorite.openrouter/alpha"].click()
        // 2119: REQ-007.4.5
        XCTAssertEqual(app.buttons["composer.modelPicker"].value as? String, "Alpha Model")

        let composer = app.textViews["composer.textEditor"]
        composer.click()
        app.typeText("load effort levels")
        app.buttons["Send"].click()
        XCTAssertTrue(app.staticTexts["transcript.assistantMessage"].waitForExistence(timeout: 10))

        effortPicker.click()
        // 2119: REQ-007.5.1
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "composer.modelFavorite.")).firstMatch.exists)
        XCTAssertFalse(app.buttons["composer.selectFavorites"].exists)
        XCTAssertTrue(app.buttons["composer.effort.low"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["composer.effort.high"].waitForExistence(timeout: 5))
        let effortOptions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "composer.effort."))
        XCTAssertEqual(effortOptions.count, 2)
        XCTAssertFalse(app.buttons["composer.effort.medium"].exists)
        XCTAssertFalse(app.buttons["composer.effort.max"].exists)
        app.buttons["composer.effort.high"].click()
        // 2119: REQ-007.5.3
        XCTAssertTrue(app.buttons["composer.effortPicker"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["composer.effortPicker"].value as? String, "High")
    }

    func testModelAndEffortSelectionsBeforeRPCStartupAreAppliedToPi() throws {
        let fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeModelSelectionRPC-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        let commandLog = fixtureDirectory.appendingPathComponent("commands.log")
        let effortStateFile = fixtureDirectory.appendingPathComponent("effort-state.txt")
        let script = fixtureDirectory.appendingPathComponent("fake-pi-rpc.sh")
        try """
        #!/bin/sh
        model_id="initial"
        effort="low"
        while IFS= read -r line; do
          command=$(printf '%s' "$line" | sed -E 's/.*"type":"([^"]+)".*/\\1/')
          request_id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          printf '%s\\n' "$command" >> "$PI_NATIVE_TEST_RPC_COMMAND_LOG"
          data="}"
          case "$command" in
            switch_session|new_session)
              data=',"data":{"cancelled":false}}'
              ;;
            get_messages)
              data=',"data":{"messages":[]}}'
              ;;
            get_state)
              model_name="Initial Model"
              [ "$model_id" = "alpha" ] && model_name="Alpha Model"
              data=',"data":{"model":{"provider":"openrouter","id":"'"$model_id"'","name":"'"$model_name"'"},"thinkingLevel":"'"$effort"'","sessionFile":"/tmp/pinative-ui-newest-visible.jsonl"}}'
              ;;
            get_available_models)
              data=',"data":{"models":[{"provider":"openrouter","id":"alpha","name":"Alpha Model"}]}}'
              ;;
            get_available_thinking_levels)
              data=',"data":{"levels":["low","high"]}}'
              ;;
            set_model)
              model_id="alpha"
              data=',"data":{"provider":"openrouter","id":"alpha","name":"Alpha Model"}}'
              ;;
            set_thinking_level)
              effort="high"
              printf '%s' "$effort" > "$PI_NATIVE_TEST_RPC_EFFORT_STATE_FILE"
              ;;
          esac
          printf '{"id":%s,"type":"response","command":"%s","success":true%s\\n' "$request_id" "$command" "$data"
        done
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let favoritesFile = fixtureDirectory.appendingPathComponent("favorites.json")
        try #"[{"provider":"openrouter","id":"alpha","name":"Alpha Model"}]"#.write(to: favoritesFile, atomically: true, encoding: .utf8)
        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_CHAT_TITLE"] = "Queued selection chat"
        app.launchEnvironment["PI_NATIVE_TEST_MODEL_FAVORITES_FILE"] = favoritesFile.path
        app.launchEnvironment["PI_NATIVE_TEST_MODEL_CATALOG"] = #"[{"provider":"openrouter","id":"alpha","name":"Alpha Model"}]"#
        app.launchEnvironment["PI_NATIVE_TEST_THINKING_LEVELS"] = "low,high"
        app.launchEnvironment["PI_NATIVE_TEST_PI_EXECUTABLE"] = "/bin/sh"
        app.launchEnvironment["PI_NATIVE_TEST_PI_ARGUMENTS"] = String(
            decoding: try JSONEncoder().encode([script.path]),
            as: UTF8.self
        )
        app.launchEnvironment["PI_NATIVE_TEST_RPC_COMMAND_LOG"] = commandLog.path
        app.launchEnvironment["PI_NATIVE_TEST_RPC_EFFORT_STATE_FILE"] = effortStateFile.path
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("YES")
        app.launch()

        app.buttons["composer.modelPicker"].click()
        let alphaFavorite = app.buttons["composer.modelFavorite.openrouter/alpha"]
        alphaFavorite.click()
        XCTAssertTrue(alphaFavorite.waitForNonExistence(timeout: 5))
        app.buttons["composer.effortPicker"].click()
        XCTAssertTrue(app.buttons["composer.effort.low"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["composer.effort.high"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "composer.effort.")).count,
            2
        )
        app.buttons["composer.effort.high"].click()

        let commandsApplied = expectation(
            for: NSPredicate { _, _ in
                guard let commands = try? String(contentsOf: commandLog, encoding: .utf8) else { return false }
                return commands.contains("set_model") && commands.contains("set_thinking_level")
            },
            evaluatedWith: nil
        )
        wait(for: [commandsApplied], timeout: 10)
        // 2119: REQ-007.4.5
        XCTAssertEqual(app.buttons["composer.modelPicker"].value as? String, "Alpha Model")
        // 2119: REQ-007.5.3
        XCTAssertEqual(app.buttons["composer.effortPicker"].value as? String, "High")
        XCTAssertEqual(try String(contentsOf: effortStateFile, encoding: .utf8), "high")
    }

    func testEffortPickerShowsUnavailableStateWhenPiReportsNoLevels() throws {
        let fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeNoEffortLevels-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        let script = fixtureDirectory.appendingPathComponent("fake-pi-rpc.sh")
        let commandLog = fixtureDirectory.appendingPathComponent("commands.log")
        try """
        #!/bin/sh
        levels='missing'
        effort='low'
        conversation='default'
        session_file='/tmp/pinative-ui-newest-visible.jsonl'
        while IFS= read -r line; do
          command=$(printf '%s' "$line" | sed -E 's/.*"type":"([^"]+)".*/\\1/')
          printf '%s\\n' "$command" >> "$PI_NATIVE_TEST_RPC_COMMAND_LOG"
          request_id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          data="}"
          case "$command" in
            switch_session)
              session_file=$(printf '%s' "$line" | sed -E 's/.*"sessionPath":"([^"]+)".*/\\1/')
              case "$line" in
                *pinative-ui-older-visible*) levels='missing'; conversation='unavailable' ;;
                *pinative-ui-pinned*) levels='["minimal","xhigh"]'; conversation='pinned' ;;
                *) levels='["medium"]'; conversation='default' ;;
              esac
              data=',"data":{"cancelled":false}}'
              ;;
            new_session) data=',"data":{"cancelled":false}}' ;;
            get_messages) data=',"data":{"messages":[{"role":"user","content":"Fixture transcript"}]}}' ;;
            get_state) data=',"data":{"model":{"provider":"openrouter","id":"alpha","name":"Alpha Model"},"thinkingLevel":"'"$effort"'","sessionFile":"'"$session_file"'"}}' ;;
            get_available_models) data=',"data":{"models":[{"provider":"openrouter","id":"alpha","name":"Alpha Model"}]}}' ;;
            get_available_thinking_levels)
              if [ "$levels" = "missing" ]; then
                data=',"data":{}}'
              else
                data=',"data":{"levels":'"$levels"'}}'
              fi
              ;;
            set_thinking_level)
              effort=$(printf '%s' "$line" | sed -E 's/.*"level":"([^"]+)".*/\\1/')
              printf 'set_thinking_level:%s:%s\\n' "$conversation" "$effort" >> "$PI_NATIVE_TEST_RPC_COMMAND_LOG"
              ;;
          esac
          printf '{"id":%s,"type":"response","command":"%s","success":true%s\\n' "$request_id" "$command" "$data"
        done
        """.write(to: script, atomically: true, encoding: .utf8)
        let favoritesFile = fixtureDirectory.appendingPathComponent("favorites.json")
        try #"[{"provider":"openrouter","id":"alpha","name":"Alpha Model"}]"#.write(
            to: favoritesFile,
            atomically: true,
            encoding: .utf8
        )

        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_PROJECT_PATH"] = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_CHAT_TITLE"] = "Levels chat"
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_OLDER_CHAT_TITLE"] = "No effort levels chat"
        app.launchEnvironment["PI_NATIVE_TEST_SEEDED_PINNED_CHAT_TITLE"] = "Alternate levels chat"
        app.launchEnvironment["PI_NATIVE_TEST_MODEL_FAVORITES_FILE"] = favoritesFile.path
        app.launchEnvironment["PI_NATIVE_TEST_MODEL_CATALOG"] = #"[{"provider":"openrouter","id":"alpha","name":"Alpha Model"}]"#
        app.launchEnvironment["PI_NATIVE_TEST_THINKING_LEVELS"] = "low"
        app.launchEnvironment["PI_NATIVE_TEST_PI_EXECUTABLE"] = "/bin/sh"
        app.launchEnvironment["PI_NATIVE_TEST_PI_ARGUMENTS"] = String(
            decoding: try JSONEncoder().encode([script.path]),
            as: UTF8.self
        )
        app.launchEnvironment["PI_NATIVE_TEST_RPC_COMMAND_LOG"] = commandLog.path
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("YES")
        app.launch()

        app.buttons["No effort levels chat"].firstMatch.click()
        app.buttons["composer.modelPicker"].click()
        let unavailableChatAlpha = app.buttons["composer.modelFavorite.openrouter/alpha"]
        XCTAssertTrue(unavailableChatAlpha.waitForExistence(timeout: 5))
        unavailableChatAlpha.click()
        XCTAssertTrue(unavailableChatAlpha.waitForNonExistence(timeout: 5))
        let effortPicker = app.buttons["composer.effortPicker"]
        XCTAssertTrue(effortPicker.waitForExistence(timeout: 5))
        let levelsRequested = expectation(
            for: NSPredicate { _, _ in
                guard let commands = try? String(contentsOf: commandLog, encoding: .utf8) else { return false }
                return commands.contains("get_available_thinking_levels")
            },
            evaluatedWith: nil
        )
        wait(for: [levelsRequested], timeout: 8)
        effortPicker.click()
        // 2119: REQ-007.5.5
        XCTAssertTrue(app.staticTexts["Effort unavailable"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])

        app.buttons["Alternate levels chat"].firstMatch.click()
        app.buttons["composer.modelPicker"].click()
        let alternateChatAlpha = app.buttons["composer.modelFavorite.openrouter/alpha"]
        XCTAssertTrue(alternateChatAlpha.waitForExistence(timeout: 5))
        alternateChatAlpha.click()
        XCTAssertTrue(alternateChatAlpha.waitForNonExistence(timeout: 5))
        let alternateLevelsRequested = expectation(
            for: NSPredicate { _, _ in
                guard let commands = try? String(contentsOf: commandLog, encoding: .utf8) else { return false }
                return commands.components(separatedBy: "get_available_thinking_levels").count - 1 >= 2
            },
            evaluatedWith: nil
        )
        wait(for: [alternateLevelsRequested], timeout: 8)
        app.buttons["composer.effortPicker"].click()
        // 2119: REQ-007.5.2
        XCTAssertTrue(app.buttons["composer.effort.minimal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["composer.effort.xhigh"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "composer.effort.")).count,
            2
        )
        XCTAssertFalse(app.buttons["composer.effort.low"].exists)
        XCTAssertFalse(app.buttons["composer.effort.medium"].exists)
        XCTAssertFalse(app.buttons["composer.effort.high"].exists)
        XCTAssertFalse(app.buttons["composer.effort.max"].exists)
        // 2119: REQ-007.5.5
        XCTAssertFalse(app.staticTexts["Effort unavailable"].exists)
        app.buttons["composer.effort.xhigh"].click()
        let alternateEffortPicker = app.buttons["composer.effortPicker"]
        XCTAssertTrue(alternateEffortPicker.waitForExistence(timeout: 5))
        // 2119: REQ-007.5.3
        XCTAssertEqual(alternateEffortPicker.value as? String, "Extra Hard")
        let pinnedConversationMutated = expectation(
            for: NSPredicate { _, _ in
                guard let commands = try? String(contentsOf: commandLog, encoding: .utf8) else { return false }
                return commands.contains("set_thinking_level:pinned:xhigh")
            },
            evaluatedWith: nil
        )
        wait(for: [pinnedConversationMutated], timeout: 8)
        let mutationLog = try String(contentsOf: commandLog, encoding: .utf8)
        // 2119: REQ-007.5.3
        XCTAssertFalse(mutationLog.contains("set_thinking_level:unavailable:"))

        app.buttons["No effort levels chat"].firstMatch.click()
        app.buttons["composer.effortPicker"].click()
        // 2119: REQ-007.5.5
        XCTAssertTrue(app.staticTexts["Effort unavailable"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "composer.effort.")).count,
            0
        )
    }

    @MainActor
    func testModelsSettingsLoadsRealPiCatalogWithoutAConversation() throws {
        let captureFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("real-pi-catalog-\(UUID().uuidString).json")
        let app = XCUIApplication()
        app.launchEnvironment["PI_NATIVE_RESET_PROJECTS"] = "1"
        app.launchEnvironment["PI_NATIVE_TEST_MODEL_FAVORITES_FILE"] = NSTemporaryDirectory() + "model-favorites-real-catalog-\(UUID().uuidString).json"
        app.launchEnvironment["PI_NATIVE_TEST_MODEL_CATALOG_CAPTURE_FILE"] = captureFile.path
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("YES")
        app.launch()

        app.buttons["sidebar.settingsButton"].click()
        app.buttons["Models"].firstMatch.click()

        let nonemptySummary = app.staticTexts.matching(
            NSPredicate(format: "value MATCHES %@ OR label MATCHES %@", #"[1-9][0-9]* available"#, #"[1-9][0-9]* available"#)
        ).firstMatch
        // 2119: REQ-007.1.2
        XCTAssertTrue(nonemptySummary.waitForExistence(timeout: 30))
        struct CapturedModel: Decodable {
            let provider: String
            let id: String
            let name: String
        }
        let capturedModels = try JSONDecoder().decode([CapturedModel].self, from: try Data(contentsOf: captureFile))
        XCTAssertFalse(capturedModels.isEmpty)
        XCTAssertTrue(app.staticTexts["\(capturedModels.count) available"].waitForExistence(timeout: 5))
        let search = app.textFields["settings.models.searchField"]
        for capturedModel in capturedModels {
            let provider = capturedModel.provider
            let modelID = capturedModel.id
            search.click()
            search.typeKey("a", modifierFlags: .command)
            search.typeText(modelID)
            XCTAssertTrue(app.descendants(matching: .any)["settings.models.row.\(provider)/\(modelID)"].waitForExistence(timeout: 10))
        }
        XCTAssertFalse(app.staticTexts["Could not load models"].exists)
    }

}
