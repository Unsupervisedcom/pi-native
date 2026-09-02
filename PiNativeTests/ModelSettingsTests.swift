import XCTest
@testable import PiNative

private actor AsyncTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let currentWaiters = waiters
        waiters.removeAll()
        currentWaiters.forEach { $0.resume() }
    }
}

private actor ModelCatalogLoaderStub {
    private var responses: [[PiModelOption]]
    private(set) var callCount = 0

    init(responses: [[PiModelOption]]) {
        self.responses = responses
    }

    func load() -> [PiModelOption] {
        callCount += 1
        return responses.isEmpty ? [] : responses.removeFirst()
    }
}

@MainActor
final class ModelSettingsTests: XCTestCase {
    nonisolated(unsafe) private var defaultsSuiteName: String!
    nonisolated(unsafe) private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "ModelSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    func testInitialFavoriteSeedingPersistenceAndSavedEmptyMigration() throws {
        let defaultModel = PiModelOption(provider: "openrouter", id: "moonshotai/kimi-k3", name: "Kimi K3")
        let storage = UserDefaultsModelFavoritesStorage(defaults: defaults)
        let seeded = ModelSettingsModel(storage: storage, favoritesKey: "favorites", configuredDefaultModel: defaultModel)

        // 2119: REQ-007.3.2
        XCTAssertEqual(seeded.favorites, [defaultModel])
        XCTAssertNotNil(defaults.data(forKey: "favorites"))

        let userAdded = PiModelOption(provider: "openai", id: "gpt-5.5", name: "GPT-5.5")
        seeded.setFavorite(true, for: userAdded)
        seeded.removeFavorite(defaultModel)
        let reloaded = ModelSettingsModel(storage: storage, favoritesKey: "favorites", configuredDefaultModel: nil)
        // 2119: REQ-007.3.1
        XCTAssertEqual(reloaded.favorites, [userAdded])

        storage.saveData(try JSONEncoder().encode([PiModelOption]()), forKey: "empty-favorites")
        let migrated = ModelSettingsModel(storage: storage, favoritesKey: "empty-favorites", configuredDefaultModel: defaultModel)
        // 2119: REQ-007.3.2
        XCTAssertEqual(migrated.favorites, [defaultModel])
        let persistedMigration = ModelSettingsModel(storage: storage, favoritesKey: "empty-favorites", configuredDefaultModel: nil)
        XCTAssertEqual(persistedMigration.favorites, [defaultModel])
    }

    func testOnlyFavoriteCannotBeRemoved() {
        let defaultModel = PiModelOption(provider: "openrouter", id: "default", name: "Default")
        let other = PiModelOption(provider: "openai", id: "other", name: "Other")
        let model = ModelSettingsModel(
            storage: UserDefaultsModelFavoritesStorage(defaults: defaults),
            favoritesKey: "favorites",
            configuredDefaultModel: defaultModel
        )

        model.removeFavorite(defaultModel)
        // 2119: REQ-007.3.7
        XCTAssertEqual(model.favorites, [defaultModel])

        model.setFavorite(true, for: other)
        model.removeFavorite(defaultModel)
        XCTAssertEqual(model.favorites, [other])

        model.setFavorite(false, for: other)
        // 2119: REQ-007.3.7
        XCTAssertEqual(model.favorites, [other])
    }

    func testFavoritesPersistThroughDiskBackedStoreRecreation() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeFavoritesPersistence-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("favorites.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let defaultModel = PiModelOption(provider: "openrouter", id: "default", name: "Default")
        let persistedModel = PiModelOption(provider: "openai", id: "persisted", name: "Persisted")
        var model: ModelSettingsModel? = ModelSettingsModel(
            storage: FileModelFavoritesStorage(fileURL: fileURL),
            configuredDefaultModel: defaultModel
        )
        model?.setFavorite(true, for: persistedModel)
        model?.removeFavorite(defaultModel)
        model = nil

        let relaunched = ModelSettingsModel(
            storage: FileModelFavoritesStorage(fileURL: fileURL),
            configuredDefaultModel: defaultModel
        )

        // 2119: REQ-007.3.1
        XCTAssertEqual(relaunched.favorites, [persistedModel])
    }

    func testAppStartupSeedsDefaultAndLoadsCatalogWithoutAnActiveConversation() async {
        setenv("PI_NATIVE_TEST_DEFAULT_PROVIDER", "openrouter", 1)
        setenv("PI_NATIVE_TEST_DEFAULT_MODEL", "startup-model", 1)
        setenv("PI_NATIVE_RESET_PROJECTS", "1", 1)
        defer {
            unsetenv("PI_NATIVE_TEST_DEFAULT_PROVIDER")
            unsetenv("PI_NATIVE_TEST_DEFAULT_MODEL")
            unsetenv("PI_NATIVE_RESET_PROJECTS")
        }
        let catalogModel = PiModelOption(provider: "openrouter", id: "startup-model", name: "Startup Model")
        let appModel = AppModel(
            modelFavoritesStorage: UserDefaultsModelFavoritesStorage(defaults: defaults),
            modelCatalogLoader: { [catalogModel] }
        )

        // 2119: REQ-007.3.3
        XCTAssertFalse(appModel.isSettingsPresented)
        XCTAssertNil(appModel.activeConversationModel)
        XCTAssertEqual(appModel.modelSettings.favorites.map(\.stableID), ["openrouter/startup-model"])

        await appModel.refreshModelCatalog()

        XCTAssertEqual(appModel.modelSettings.catalog, [catalogModel])
        XCTAssertEqual(appModel.modelSettings.availableFavorites, [catalogModel])
    }

    func testLoadedEmptyCatalogCanBeForceRefreshed() async {
        let available = PiModelOption(provider: "openrouter", id: "available", name: "Available")
        let loader = ModelCatalogLoaderStub(responses: [[], [available]])
        let appModel = AppModel(
            modelFavoritesStorage: UserDefaultsModelFavoritesStorage(defaults: defaults),
            modelCatalogLoader: { await loader.load() }
        )

        await appModel.refreshModelCatalog()
        XCTAssertEqual(appModel.modelSettings.catalog, [])
        await appModel.refreshModelCatalog()
        let cachedCallCount = await loader.callCount
        XCTAssertEqual(cachedCallCount, 1)

        await appModel.refreshModelCatalog(force: true)

        let refreshedCallCount = await loader.callCount
        XCTAssertEqual(refreshedCallCount, 2)
        XCTAssertEqual(appModel.modelSettings.catalog, [available])
    }

    func testFavoritesAreUniqueAndUnavailableFavoritesAreTracked() {
        let available = PiModelOption(provider: "openrouter", id: "one", name: "One")
        let stale = PiModelOption(provider: "openrouter", id: "stale", name: "Stale")
        let model = ModelSettingsModel(storage: UserDefaultsModelFavoritesStorage(defaults: defaults), favoritesKey: "favorites", configuredDefaultModel: nil)

        model.setFavorite(true, for: available)
        model.setFavorite(true, for: available)
        model.setFavorite(true, for: stale)
        XCTAssertTrue(model.availableFavorites.isEmpty)
        // 2119: REQ-007.3.4
        XCTAssertEqual(model.favorites.map(\.stableID), ["openrouter/one", "openrouter/stale"])

        model.updateCatalog([available])
        // 2119: REQ-007.3.5
        XCTAssertEqual(model.unavailableFavorites, [stale])
        // 2119: REQ-007.3.6
        XCTAssertEqual(model.availableFavorites, [available])

        model.removeFavorite(stale)
        // 2119: REQ-007.1.4
        XCTAssertEqual(model.favorites, [available])
    }

    func testSearchMatchesProviderIDAndNameAndPreservesFavoriteState() {
        let kimi = PiModelOption(provider: "openrouter", id: "moonshotai/kimi-k3", name: "Kimi K3")
        let gpt = PiModelOption(provider: "openai", id: "gpt-5.5", name: "GPT-5.5")
        let claude = PiModelOption(provider: "anthropic", id: "claude-opus-4-7", name: "Claude Opus")
        let mini = PiModelOption(provider: "openai", id: "gpt-mini", name: "GPT Mini")
        let model = ModelSettingsModel(storage: UserDefaultsModelFavoritesStorage(defaults: defaults), favoritesKey: "favorites", configuredDefaultModel: nil)
        model.updateCatalog([gpt, kimi, claude, mini])
        model.setFavorite(true, for: kimi)
        model.setFavorite(true, for: mini)

        model.searchQuery = "PENROUT"
        // 2119: REQ-007.2.2
        XCTAssertEqual(model.filteredCatalog, [kimi])
        // 2119: REQ-007.2.3
        XCTAssertTrue(model.isFavorite(kimi))

        model.searchQuery = "gpt-5"
        XCTAssertEqual(model.filteredCatalog, [gpt])
        model.searchQuery = "claude op"
        XCTAssertEqual(model.filteredCatalog, [claude])
        model.searchQuery = "CLAUDE OPUS"
        XCTAssertEqual(model.filteredCatalog, [claude])
        model.searchQuery = "not-a-model"
        XCTAssertTrue(model.filteredCatalog.isEmpty)

        model.searchQuery = "gpt"
        XCTAssertEqual(Set(model.filteredCatalog), Set([gpt, mini]))
        // 2119: REQ-007.2.3
        XCTAssertTrue(model.isFavorite(kimi))
        XCTAssertTrue(model.isFavorite(mini))
        XCTAssertFalse(model.isFavorite(gpt))
        XCTAssertFalse(model.isFavorite(claude))
        model.searchQuery = ""
        XCTAssertTrue(model.isFavorite(kimi))
        XCTAssertTrue(model.isFavorite(mini))
        XCTAssertFalse(model.isFavorite(gpt))
        XCTAssertFalse(model.isFavorite(claude))

        model.searchQuery = ""
        // 2119: REQ-007.2.4
        XCTAssertEqual(model.filteredCatalog, model.catalog)
    }

    func testSettingsCanOpenDirectlyToModelsSection() {
        let appModel = AppModel()
        // 2119: REQ-007.1.1
        XCTAssertTrue(SettingsSection.allCases.contains(.models))

        appModel.presentModelSettings()
        // 2119: REQ-007.4.4
        XCTAssertTrue(appModel.isSettingsPresented)
        XCTAssertEqual(appModel.settingsSection, .models)
    }

    func testComposerRejectsSubmissionWithoutASelectedModel() {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "should not send", 1)
        defer { unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE") }
        let settings = ModelSettingsModel(
            storage: UserDefaultsModelFavoritesStorage(defaults: defaults),
            favoritesKey: "favorites",
            configuredDefaultModel: nil
        )
        let conversation = PiConversationModel(modelSettings: settings)
        conversation.draft = "Do not submit without a model"

        conversation.sendDraft()

        // 2119: REQ-007.4.7
        XCTAssertEqual(conversation.draft, "Do not submit without a model")
        XCTAssertTrue(conversation.items.isEmpty)
        XCTAssertFalse(conversation.hasPendingPrompt)
        XCTAssertFalse(conversation.isRunning)

        let availableButUnselected = PiModelOption(provider: "openrouter", id: "available", name: "Available")
        settings.updateCatalog([availableButUnselected])
        conversation.availableModels = [availableButUnselected]
        conversation.currentThinkingLevel = .medium
        conversation.draft = "Do not submit without a selected model from a loaded catalog"
        conversation.sendDraft()
        // 2119: REQ-007.4.7
        XCTAssertEqual(conversation.draft, "Do not submit without a selected model from a loaded catalog")
        XCTAssertTrue(conversation.items.isEmpty)
        XCTAssertFalse(conversation.hasPendingPrompt)
        XCTAssertFalse(conversation.isRunning)

        let selected = PiModelOption(provider: "openrouter", id: "selected", name: "Selected")
        conversation.currentModel = selected
        conversation.currentThinkingLevel = .medium
        conversation.sendDraft()
        XCTAssertTrue(conversation.draft.isEmpty)
        XCTAssertEqual(conversation.items.count, 1)
        XCTAssertTrue(conversation.isRunning)
    }

    func testConversationWaitsForHydratedCatalogBeforeSelectingConfiguredModel() {
        let configured = PiModelOption(provider: "openrouter", id: "configured", name: "configured")
        let hydrated = PiModelOption(provider: "openrouter", id: "configured", name: "Configured")
        let settings = ModelSettingsModel(
            storage: UserDefaultsModelFavoritesStorage(defaults: defaults),
            favoritesKey: "favorites",
            configuredDefaultModel: configured
        )

        let waitingConversation = PiConversationModel(modelSettings: settings)

        XCTAssertNil(waitingConversation.currentModel)
        XCTAssertNil(waitingConversation.currentThinkingLevel)
        XCTAssertFalse(waitingConversation.isProcessStarted)

        settings.updateCatalog([hydrated])
        let hydratedConversation = PiConversationModel(modelSettings: settings)

        XCTAssertEqual(hydratedConversation.currentModel, hydrated)
        XCTAssertNil(hydratedConversation.currentThinkingLevel)
        XCTAssertFalse(hydratedConversation.isProcessStarted)
    }

    func testConversationDoesNotProvisionallySelectAnUnavailableFavorite() {
        let stale = PiModelOption(provider: "openrouter", id: "stale", name: "Stale")
        let available = PiModelOption(provider: "openrouter", id: "available", name: "Available")
        let settings = ModelSettingsModel(
            storage: UserDefaultsModelFavoritesStorage(defaults: defaults),
            favoritesKey: "favorites",
            configuredDefaultModel: nil
        )
        settings.setFavorite(true, for: stale)
        settings.updateCatalog([available])

        let conversation = PiConversationModel(modelSettings: settings)

        // 2119: REQ-007.3.6
        XCTAssertNil(conversation.currentModel)
        // 2119: REQ-007.4.7
        conversation.draft = "Do not send with an unavailable favorite"
        conversation.sendDraft()
        XCTAssertEqual(conversation.draft, "Do not send with an unavailable favorite")
        XCTAssertTrue(conversation.items.isEmpty)
    }

    func testComposerFavoriteFilteringAndPerConversationSelectionIsolation() {
        let favorite = PiModelOption(provider: "openrouter", id: "favorite", name: "Favorite")
        let other = PiModelOption(provider: "openrouter", id: "other", name: "Other")
        let modelSettings = ModelSettingsModel(storage: UserDefaultsModelFavoritesStorage(defaults: defaults), favoritesKey: "favorites", configuredDefaultModel: nil)
        modelSettings.updateCatalog([favorite, other])
        modelSettings.setFavorite(true, for: favorite)

        // 2119: REQ-007.4.1
        XCTAssertEqual(modelSettings.availableFavorites, [favorite])
        // 2119: REQ-007.4.2
        XCTAssertFalse(modelSettings.availableFavorites.contains(other))

        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "ok", 1)
        defer { unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE") }
        let first = PiConversationModel(modelSettings: modelSettings)
        let second = PiConversationModel(modelSettings: modelSettings)
        let third = PiConversationModel(modelSettings: modelSettings)
        first.currentModel = other
        second.currentModel = other
        third.currentModel = other
        second.currentThinkingLevel = .low
        third.currentThinkingLevel = .medium

        first.selectModel(favorite)
        // 2119: REQ-007.4.5
        XCTAssertEqual(first.currentModel, favorite)
        // 2119: REQ-007.4.6
        XCTAssertEqual(second.currentModel, other)
        XCTAssertEqual(third.currentModel, other)

        first.selectThinkingLevel(.high)
        // 2119: REQ-007.5.3
        XCTAssertEqual(first.currentThinkingLevel, .high)
        // 2119: REQ-007.5.4
        XCTAssertEqual(second.currentThinkingLevel, .low)
        XCTAssertEqual(third.currentThinkingLevel, .medium)
    }

    func testEffortSelectionUpdatesTheActiveAppConversation() throws {
        setenv("PI_NATIVE_RESET_PROJECTS", "1", 1)
        setenv("PI_NATIVE_TEST_PROJECT_PATH", FileManager.default.temporaryDirectory.path, 1)
        setenv("PI_NATIVE_TEST_SEEDED_CHAT_TITLE", "Active effort chat", 1)
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "ok", 1)
        defer {
            unsetenv("PI_NATIVE_RESET_PROJECTS")
            unsetenv("PI_NATIVE_TEST_PROJECT_PATH")
            unsetenv("PI_NATIVE_TEST_SEEDED_CHAT_TITLE")
            unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
        }

        let appModel = AppModel(modelFavoritesStorage: UserDefaultsModelFavoritesStorage(defaults: defaults))
        let activeConversation = try XCTUnwrap(appModel.activeConversationModel)
        activeConversation.currentThinkingLevel = .low
        activeConversation.selectThinkingLevel(.high)

        // 2119: REQ-007.5.3
        XCTAssertTrue(appModel.activeConversationModel === activeConversation)
        XCTAssertEqual(appModel.activeConversationModel?.currentThinkingLevel, .high)
    }

    func testProvisionalCatalogIsHydratedWithPiDisplayNames() async {
        let previouslyNamed = PiModelOption(provider: "openrouter", id: "moonshotai/kimi-k3", name: "Old Catalog Name")
        let provisional = PiModelOption(provider: "openrouter", id: "moonshotai/kimi-k3", name: "moonshotai/kimi-k3")
        let catalogNamed = PiModelOption(provider: "openrouter", id: "moonshotai/kimi-k3", name: "Kimi K3")
        let model = ModelSettingsModel(storage: UserDefaultsModelFavoritesStorage(defaults: defaults), favoritesKey: "favorites", configuredDefaultModel: previouslyNamed)

        await model.refreshProvisionalCatalog { [provisional] }
        XCTAssertTrue(model.catalogIsProvisional)
        await model.refreshCatalogIfNeeded { [catalogNamed] }

        // 2119: REQ-007.4.1
        XCTAssertFalse(model.catalogIsProvisional)
        XCTAssertEqual(model.availableFavorites.first?.name, "Kimi K3")
    }

    func testRealCatalogRefreshUpgradesAnInflightProvisionalCatalog() async {
        let model = ModelSettingsModel(storage: UserDefaultsModelFavoritesStorage(defaults: defaults), favoritesKey: "favorites", configuredDefaultModel: nil)
        let provisional = PiModelOption(provider: "openrouter", id: "same", name: "same")
        let hydrated = PiModelOption(provider: "openrouter", id: "same", name: "Hydrated Name")
        let provisionalStarted = expectation(description: "provisional catalog started")
        let gate = AsyncTestGate()

        let provisionalTask = Task {
            await model.refreshProvisionalCatalog {
                provisionalStarted.fulfill()
                await gate.wait()
                return [provisional]
            }
        }
        await fulfillment(of: [provisionalStarted], timeout: 2)
        let hydratedTask = Task {
            await model.refreshCatalogIfNeeded { [hydrated] }
        }
        await gate.open()
        await provisionalTask.value
        await hydratedTask.value

        XCTAssertFalse(model.catalogIsProvisional)
        XCTAssertEqual(model.catalog, [hydrated])
    }

    func testCatalogLoaderDrivesLoadingLoadedEmptyAndFailureStates() async {
        let model = ModelSettingsModel(storage: UserDefaultsModelFavoritesStorage(defaults: defaults), favoritesKey: "favorites", configuredDefaultModel: nil)
        let available = PiModelOption(provider: "openrouter", id: "loaded", name: "Loaded Model")

        let loaderStarted = expectation(description: "catalog loader started")
        let gate = AsyncTestGate()
        let loadingTask = Task {
            await model.refreshCatalog {
                loaderStarted.fulfill()
                await gate.wait()
                return [available]
            }
        }
        await fulfillment(of: [loaderStarted], timeout: 2)
        // 2119: REQ-007.1.6
        XCTAssertEqual(model.catalogState, .loading)
        await gate.open()
        await loadingTask.value

        XCTAssertEqual(model.catalog, [available])

        await model.refreshCatalog { [] }
        XCTAssertEqual(model.catalogState, .loaded)
        XCTAssertTrue(model.catalog.isEmpty)

        struct TestFailure: Error {}
        await model.refreshCatalog { throw TestFailure() }
        // 2119: REQ-007.1.8
        if case .failed = model.catalogState {} else { XCTFail("Expected catalog failure state") }
    }

    func testCatalogAndEffortStateRules() {
        let model = ModelSettingsModel(storage: UserDefaultsModelFavoritesStorage(defaults: defaults), favoritesKey: "favorites", configuredDefaultModel: nil)
        // 2119: REQ-007.1.8
        model.failCatalog("catalog unavailable")
        XCTAssertEqual(model.catalogState, .failed("catalog unavailable"))

        model.updateCatalog([])
        XCTAssertEqual(model.catalogState, .loaded)
        XCTAssertTrue(model.catalog.isEmpty)

        let conversation = PiConversationModel(modelSettings: model)
        XCTAssertTrue(conversation.availableThinkingLevels.isEmpty)
    }
}
