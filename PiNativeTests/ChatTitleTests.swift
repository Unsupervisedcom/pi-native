import Darwin
import XCTest
@testable import PiNative

@MainActor
final class ChatTitleFormattingTests: XCTestCase {
    // 2119: REQ-008.1.1
    // 2119: REQ-008.2.1
    func testFallbackIsDeterministicSingleLineAndSidebarSized() {
        let message = "Can you please investigate robots\nwith a deliberately long description that exceeds the sidebar title width by a wide margin"
        let first = ChatTitleFormatting.fallback(from: message)
        let second = ChatTitleFormatting.fallback(from: message)

        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
        XCTAssertFalse(first.contains("\n"))
        XCTAssertLessThanOrEqual(first.count, 48)
    }

    // 2119: REQ-008.2.1
    func testSemanticTitleIsSingleLineAndSidebarSized() throws {
        let output = "Robotics Learning Guide With A Deliberately Excessive Sidebar Title That Must Be Truncated\nIgnore this second line"
        let title = try XCTUnwrap(ChatTitleFormatting.semanticTitle(from: output, firstUserPrompt: "Learn robotics"))

        XCTAssertFalse(title.contains("\n"))
        XCTAssertLessThanOrEqual(title.count, 48)
        XCTAssertNotEqual(title, output)
    }

    // 2119: REQ-008.2.5
    func testSemanticTitleRejectsNormalizedVerbatimPrompt() {
        XCTAssertNil(ChatTitleFormatting.semanticTitle(
            from: "I am interested in learning about robots",
            firstUserPrompt: "I am interested in learning about robots"
        ))
        XCTAssertNil(ChatTitleFormatting.semanticTitle(
            from: "  I   AM interested in learning about robots  ",
            firstUserPrompt: "I am interested in learning about robots"
        ))
        XCTAssertNil(ChatTitleFormatting.semanticTitle(
            from: "I am interested in learning about robots\n",
            firstUserPrompt: "  i am interested in learning about robots  "
        ))
        XCTAssertEqual(ChatTitleFormatting.semanticTitle(
            from: "Robotics Learning Guide",
            firstUserPrompt: "I am interested in learning about robots"
        ), "Robotics Learning Guide")
    }
}

@MainActor
final class ChatTitleLifecycleTests: XCTestCase {
    private var projectSessionDefaultsKeys: Set<String> = []

    override func setUp() async throws {
        clearSessionDefaults()
    }

    override func tearDown() async throws {
        clearSessionDefaults()
    }

    // 2119: REQ-008.1.1
    func testAcceptedLongMultilinePromptUsesFormattedFallbackInChatLifecycle() {
        let generator = RecordingTitleGenerator(output: "Unused")
        let prompt = "Can you please investigate robotics\nwith a deliberately long request that exceeds the sidebar title limit"
        let (appModel, _, _) = makeNewChat(generator: generator, prompt: prompt)
        let displayedTitle = appModel.standaloneSessions[0].name

        XCTAssertEqual(displayedTitle, ChatTitleFormatting.fallback(from: prompt))
        XCTAssertNotEqual(displayedTitle, prompt)
        XCTAssertFalse(displayedTitle.isEmpty)
        XCTAssertFalse(displayedTitle.contains("\n"))
        XCTAssertLessThanOrEqual(displayedTitle.count, 48)
    }

    // 2119: REQ-008.1.1
    // 2119: REQ-008.1.2
    // 2119: REQ-008.1.3
    // 2119: REQ-008.1.4
    // 2119: REQ-008.2.1
    // 2119: REQ-008.2.4
    func testNewChatTitlesOnceFromCompletedFirstExchangeAndPersists() async throws {
        let generator = RecordingTitleGenerator(output: "Robotics Learning Guide")
        let prompt = "I am interested in learning about robots"
        let (appModel, sessionID, model) = makeNewChat(generator: generator, prompt: prompt)
        model.items = [
            .user(UserMessagePayload(text: prompt)),
            .assistantText(text: "Robotics combines mechanics"),
            .assistantText(text: "with programming and feedback systems.")
        ]

        XCTAssertEqual(appModel.standaloneSessions[0].name, "I am interested in learning about robots")
        let countBeforeSettlement = await generator.currentCallCount()
        XCTAssertEqual(countBeforeSettlement, 0)

        model.handleEventForTesting(try Self.event(type: "agent_end"))
        let countAfterAgentEnd = await generator.currentCallCount()
        XCTAssertEqual(countAfterAgentEnd, 0)
        XCTAssertEqual(appModel.standaloneSessions[0].name, "I am interested in learning about robots")

        model.handleEventForTesting(try Self.event(type: "agent_settled"))
        try await waitUntil { appModel.standaloneSessions[0].name == "Robotics Learning Guide" }
        let recordedSnapshot = await generator.firstSnapshot()
        let snapshot = try XCTUnwrap(recordedSnapshot)
        XCTAssertEqual(snapshot.userPrompt, prompt)
        XCTAssertEqual(snapshot.assistantText, "Robotics combines mechanics\n\nwith programming and feedback systems.")
        let countAfterSettlement = await generator.currentCallCount()
        XCTAssertEqual(countAfterSettlement, 1)

        model.items.append(.user(UserMessagePayload(text: "Now discuss films")))
        model.items.append(.assistantText(text: "Film response."))
        model.handleEventForTesting(try Self.event(type: "agent_settled"))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appModel.standaloneSessions[0].name, "Robotics Learning Guide")
        let countAfterSecondTurn = await generator.currentCallCount()
        XCTAssertEqual(countAfterSecondTurn, 1)

        let restored = AppModel(chatTitleGenerator: generator)
        restored.automaticallyStartsPendingRuntimes = false
        XCTAssertEqual(restored.standaloneSessions.first { $0.id == sessionID }?.name, "Robotics Learning Guide")
        XCTAssertEqual(restored.standaloneSessions.first { $0.id == sessionID }?.automaticTitleState, .complete)
        restored.select(sessionID: sessionID, in: nil)
        restored.activeConversationModel?.handleEventForTesting(try Self.event(type: "agent_settled"))
        XCTAssertEqual(restored.standaloneSessions.first { $0.id == sessionID }?.name, "Robotics Learning Guide")
        let countAfterRestoredSettlement = await generator.currentCallCount()
        XCTAssertEqual(countAfterRestoredSettlement, 1)
    }

    // 2119: REQ-008.1.1
    func testMinimumAcceptedTextPromptGetsNonemptyFallback() {
        let generator = RecordingTitleGenerator(output: "Unused")
        let (appModel, _, _) = makeNewChat(generator: generator, prompt: "x")

        XCTAssertEqual(appModel.standaloneSessions[0].name, ChatTitleFormatting.fallback(from: "x"))
        XCTAssertFalse(appModel.standaloneSessions[0].name.isEmpty)
        XCTAssertEqual(appModel.standaloneSessions[0].titleSource, .fallback)
    }

    // 2119: REQ-008.1.1
    // 2119: REQ-008.1.2
    func testProjectChatGetsDeterministicFallbackAndOnlyGeneratesAfterSettlement() async throws {
        let generator = RecordingTitleGenerator(output: "Robotics Learning Guide")
        let prompt = "Learn robotics through small practical projects"
        let (projectAppModel, _, projectModel) = makeNewProjectChat(generator: generator, prompt: prompt)
        let (standaloneAppModel, _, _) = makeNewChat(generator: generator, prompt: prompt)
        let projectFallback = projectAppModel.projects[0].sessions[0].name

        XCTAssertEqual(projectFallback, ChatTitleFormatting.fallback(from: prompt))
        XCTAssertFalse(projectFallback.isEmpty)
        XCTAssertEqual(projectFallback, standaloneAppModel.standaloneSessions[0].name)
        XCTAssertEqual(projectAppModel.projects[0].sessions[0].titleSource, .fallback)
        projectModel.items = [
            .user(UserMessagePayload(text: prompt)),
            .assistantText(text: "Complete answer.")
        ]

        projectModel.handleEventForTesting(try Self.event(type: "agent_end"))
        let countBeforeSettlement = await generator.currentCallCount()
        XCTAssertEqual(countBeforeSettlement, 0)
        XCTAssertEqual(projectAppModel.projects[0].sessions[0].name, projectFallback)

        let settled = try Self.event(type: "agent_settled")
        projectModel.handleEventForTesting(settled)
        try await waitUntil { projectAppModel.projects[0].sessions[0].automaticTitleState == .complete }
        projectModel.handleEventForTesting(settled)

        XCTAssertEqual(projectAppModel.projects[0].sessions[0].name, "Robotics Learning Guide")
        let finalCount = await generator.currentCallCount()
        XCTAssertEqual(finalCount, 1)
    }

    // 2119: REQ-008.1.4
    func testExistingPersistedChatIsIneligibleForAutomaticRetitling() async throws {
        let generator = RecordingTitleGenerator(output: "Should Not Appear")
        let appModel = AppModel(chatTitleGenerator: generator)
        appModel.automaticallyStartsPendingRuntimes = false
        let existing = Session(
            name: "Existing chat title",
            status: .idle,
            cachedTranscript: [
                .user(UserMessagePayload(text: "old prompt")),
                .assistantText(text: "old response")
            ]
        )
        appModel.projects = []
        appModel.standaloneSessions = [existing]
        appModel.select(sessionID: existing.id, in: nil)
        let model = try XCTUnwrap(appModel.activeConversationModel)
        XCTAssertEqual(appModel.standaloneSessions[0].automaticTitleState, .ineligible)

        model.handleEventForTesting(try Self.event(type: "agent_settled"))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appModel.standaloneSessions[0].name, "Existing chat title")
        let count = await generator.currentCallCount()
        XCTAssertEqual(count, 0)
    }

    // 2119: REQ-008.1.1
    // 2119: REQ-008.1.2
    // 2119: REQ-008.1.3
    func testGenerationFailureLeavesFallbackUnchangedAndNeverRetries() async throws {
        let generator = RecordingTitleGenerator(error: .expected)
        let (appModel, _, model) = makeNewChat(generator: generator, prompt: "Help me learn robotics")
        model.items = [
            .user(UserMessagePayload(text: "Help me learn robotics")),
            .assistantText(text: "A complete answer.")
        ]
        let fallback = appModel.standaloneSessions[0].name

        model.handleEventForTesting(try Self.event(type: "agent_settled"))
        try await waitUntil { appModel.standaloneSessions[0].automaticTitleState == .complete }

        model.handleEventForTesting(try Self.event(type: "agent_settled"))
        model.items.append(.user(UserMessagePayload(text: "Later topic")))
        model.items.append(.assistantText(text: "Later response."))
        model.handleEventForTesting(try Self.event(type: "agent_settled"))
        let restored = AppModel(chatTitleGenerator: generator)
        restored.automaticallyStartsPendingRuntimes = false
        if let restoredSession = restored.standaloneSessions.first {
            restored.select(sessionID: restoredSession.id, in: nil)
        }

        XCTAssertEqual(restored.standaloneSessions[0].name, fallback)
        XCTAssertEqual(restored.standaloneSessions[0].titleSource, .fallback)
        XCTAssertEqual(appModel.standaloneSessions[0].name, fallback)
        XCTAssertFalse(appModel.standaloneSessions[0].name.isEmpty)
        XCTAssertEqual(appModel.standaloneSessions[0].titleSource, .fallback)
        let count = await generator.currentCallCount()
        XCTAssertEqual(count, 1)
    }

    // 2119: REQ-008.1.3
    // 2119: REQ-008.2.5
    func testInvalidSemanticTitleConsumesAttemptAndKeepsFallback() async throws {
        let generator = RecordingTitleGenerator(output: "  LEARN   ROBOTICS  ")
        let prompt = "Learn robotics"
        let (appModel, _, model) = makeNewChat(generator: generator, prompt: prompt)
        model.items = [
            .user(UserMessagePayload(text: prompt)),
            .assistantText(text: "Complete answer.")
        ]
        let settled = try Self.event(type: "agent_settled")

        model.handleEventForTesting(settled)
        try await waitUntil { appModel.standaloneSessions[0].automaticTitleState == .complete }
        model.handleEventForTesting(settled)

        XCTAssertEqual(appModel.standaloneSessions[0].name, "Learn robotics")
        XCTAssertEqual(appModel.standaloneSessions[0].titleSource, .fallback)
        let count = await generator.currentCallCount()
        XCTAssertEqual(count, 1)
    }

    // 2119: REQ-008.1.3
    func testRapidDuplicateSettlementAndLaterTurnsLaunchOnlyOneLifetimeAttempt() async throws {
        let generator = RecordingTitleGenerator(output: "Robotics Learning Guide")
        let prompt = "Learn robotics"
        let (appModel, _, model) = makeNewChat(generator: generator, prompt: prompt)
        model.items = [
            .user(UserMessagePayload(text: prompt)),
            .assistantText(text: "Complete answer.")
        ]
        let settled = try Self.event(type: "agent_settled")

        model.handleEventForTesting(settled)
        model.handleEventForTesting(settled)
        try await waitUntil { appModel.standaloneSessions[0].automaticTitleState == .complete }

        model.items.append(.user(UserMessagePayload(text: "Now discuss films")))
        model.items.append(.assistantText(text: "Film response."))
        for _ in 0..<5 { model.handleEventForTesting(settled) }

        XCTAssertEqual(appModel.standaloneSessions[0].name, "Robotics Learning Guide")
        let count = await generator.currentCallCount()
        XCTAssertEqual(count, 1)
    }

    // 2119: REQ-008.1.2
    // 2119: REQ-008.1.3
    func testInterruptedPendingAttemptIsConsumedOnRestorationWithoutRerun() async throws {
        let generator = GatedTitleGenerator(output: "Robotics Learning Guide")
        let prompt = "Learn robotics"
        let (firstAppModel, sessionID, firstModel) = makeNewChat(generator: generator, prompt: prompt)
        firstModel.items = [
            .user(UserMessagePayload(text: prompt)),
            .assistantText(text: "Complete answer.")
        ]
        firstModel.handleEventForTesting(try Self.event(type: "agent_settled"))
        await generator.waitUntilStarted()
        guard case .pending = firstAppModel.standaloneSessions[0].automaticTitleState else {
            return XCTFail("Expected persisted pending state while the sole attempt is active")
        }

        let restored = AppModel(chatTitleGenerator: generator)
        restored.automaticallyStartsPendingRuntimes = false
        let restoredSession = try XCTUnwrap(restored.standaloneSessions.first { $0.id == sessionID })
        guard case .pending = restoredSession.automaticTitleState else {
            return XCTFail("Expected interrupted pending state to restore before runtime creation")
        }
        restored.select(sessionID: sessionID, in: nil)
        XCTAssertEqual(restored.standaloneSessions.first { $0.id == sessionID }?.automaticTitleState, .complete)
        XCTAssertEqual(restored.standaloneSessions.first { $0.id == sessionID }?.name, "Learn robotics")
        restored.activeConversationModel?.handleEventForTesting(try Self.event(type: "agent_settled"))
        XCTAssertEqual(restored.standaloneSessions.first { $0.id == sessionID }?.name, "Learn robotics")
        let countAfterRestoration = await generator.currentCallCount()
        XCTAssertEqual(countAfterRestoration, 1)

        await generator.release()
        try await waitUntil { firstAppModel.standaloneSessions[0].automaticTitleState == .complete }
        let finalCount = await generator.currentCallCount()
        XCTAssertEqual(finalCount, 1)
    }

    func testAbandonmentSignalDuringPendingConsumesAttemptAndRejectsLateResult() async throws {
        let generator = GatedTitleGenerator(output: "Late Automatic Title")
        let prompt = "Learn robotics"
        let (appModel, _, model) = makeNewChat(generator: generator, prompt: prompt)
        model.items = [
            .user(UserMessagePayload(text: prompt)),
            .assistantText(text: "Complete answer.")
        ]
        model.handleEventForTesting(try Self.event(type: "agent_settled"))
        await generator.waitUntilStarted()

        model.onAgentRunAbandoned?()
        XCTAssertEqual(appModel.standaloneSessions[0].automaticTitleState, .complete)
        XCTAssertEqual(appModel.standaloneSessions[0].name, "Learn robotics")
        await generator.release()
        model.handleEventForTesting(try Self.event(type: "agent_settled"))

        XCTAssertEqual(appModel.standaloneSessions[0].name, "Learn robotics")
        let count = await generator.currentCallCount()
        XCTAssertEqual(count, 1)
    }

    // 2119: REQ-008.1.2
    func testRuntimeTeardownAndRecreationCannotLaunchAnotherAttempt() async throws {
        let generator = GatedTitleGenerator(output: "Late Automatic Title")
        let prompt = "Learn robotics"
        let (appModel, sessionID, model) = makeNewChat(generator: generator, prompt: prompt)
        model.items = [
            .user(UserMessagePayload(text: prompt)),
            .assistantText(text: "Complete answer.")
        ]
        model.handleEventForTesting(try Self.event(type: "agent_settled"))
        await generator.waitUntilStarted()

        appModel.stopAllRuntimes()
        XCTAssertEqual(appModel.standaloneSessions[0].automaticTitleState, .complete)
        appModel.select(sessionID: sessionID, in: nil)
        appModel.activeConversationModel?.handleEventForTesting(try Self.event(type: "agent_settled"))
        await generator.release()

        XCTAssertEqual(appModel.standaloneSessions[0].name, "Learn robotics")
        let count = await generator.currentCallCount()
        XCTAssertEqual(count, 1)
    }

    // 2119: REQ-008.3.1
    func testGenerationDoesNotMutateVisibleTranscript() async throws {
        let generator = RecordingTitleGenerator(output: "Robotics Learning Guide")
        let (appModel, _, model) = makeNewChat(generator: generator, prompt: "Learn robotics")
        let transcript: [TranscriptItem] = [
            .user(UserMessagePayload(text: "Learn robotics")),
            .assistantText(text: "A complete robotics answer.")
        ]
        model.items = transcript

        model.handleEventForTesting(try Self.event(type: "agent_settled"))
        try await waitUntil { appModel.standaloneSessions[0].titleSource == .generated }

        XCTAssertEqual(model.items, transcript)
        XCTAssertEqual(appModel.standaloneSessions[0].cachedTranscript, transcript)
    }

    // 2119: REQ-008.2.2
    func testRealTitleServiceRequestExcludesLaterExchanges() async throws {
        let fixture = try TitleRPCFixture(mode: "success")
        defer { fixture.cleanup() }
        let prompt = "Learn robotics"
        let (appModel, sessionID, model) = makeNewChat(generator: PiChatTitleService(), prompt: prompt)
        model.items = [
            .user(UserMessagePayload(text: prompt)),
            .assistantText(text: "First response sentinel."),
            .user(UserMessagePayload(text: "Later films sentinel.")),
            .assistantText(text: "Later response sentinel.")
        ]

        model.handleEventForTesting(try Self.event(type: "agent_settled"))
        let foundTitleTask = await appModel.waitForAutomaticTitleAttemptForTesting(sessionID: sessionID)
        XCTAssertTrue(foundTitleTask, "Automatic title generation did not create a task to await")
        XCTAssertEqual(appModel.standaloneSessions[0].automaticTitleState, .complete)
        XCTAssertEqual(appModel.standaloneSessions[0].titleSource, .generated)
        XCTAssertEqual(appModel.standaloneSessions[0].name, "Robotics Learning Guide")

        let arguments = try String(contentsOf: fixture.argumentsFile, encoding: .utf8)
        XCTAssertTrue(arguments.contains(prompt))
        XCTAssertTrue(arguments.contains("First response sentinel."))
        XCTAssertFalse(arguments.contains("Later films sentinel."))
        XCTAssertFalse(arguments.contains("Later response sentinel."))
    }

    // 2119: REQ-008.2.2
    func testTitleGenerationReceivesOnlyFirstExchange() async throws {
        let generator = GatedTitleGenerator(output: "Robotics Learning Guide")
        let prompt = "Learn robotics"
        let (appModel, _, model) = makeNewChat(generator: generator, prompt: prompt)
        model.items = [
            .user(UserMessagePayload(text: prompt)),
            .assistantText(text: "First response."),
            .user(UserMessagePayload(text: "Now discuss films")),
            .assistantText(text: "Later response.")
        ]

        model.handleEventForTesting(try Self.event(type: "agent_settled"))
        await generator.waitUntilStarted()

        let recordedSnapshot = await generator.firstSnapshot()
        await generator.release()
        let snapshot = try XCTUnwrap(recordedSnapshot)
        XCTAssertEqual(snapshot.userPrompt, prompt)
        XCTAssertEqual(snapshot.assistantText, "First response.")
        XCTAssertFalse(snapshot.userPrompt.contains("films"))
        XCTAssertFalse(snapshot.assistantText.contains("Later response"))
        try await waitUntil { appModel.standaloneSessions[0].automaticTitleState == .complete }
    }

    func testNonautomaticTitlePresentBeforeGenerationIsNotOverwritten() async throws {
        let generator = RecordingTitleGenerator(output: "Automatic Robotics Title")
        let (appModel, _, model) = makeNewChat(generator: generator, prompt: "Learn robotics")
        appModel.standaloneSessions[0].name = "Existing Session Name"
        appModel.standaloneSessions[0].titleSource = .authoritative
        model.items = [
            .user(UserMessagePayload(text: "Learn robotics")),
            .assistantText(text: "Complete answer.")
        ]

        model.handleEventForTesting(try Self.event(type: "agent_settled"))
        try await waitUntil { appModel.standaloneSessions[0].automaticTitleState == .complete }

        XCTAssertEqual(appModel.standaloneSessions[0].name, "Existing Session Name")
        XCTAssertEqual(appModel.standaloneSessions[0].titleSource, .authoritative)
    }

    // 2119: REQ-008.2.3
    func testNonemptyAuthoritativeTitleWinsAgainstLateAutomaticResult() async throws {
        let generator = GatedTitleGenerator(output: "Late Automatic Title")
        let (appModel, _, model) = makeNewChat(generator: generator, prompt: "Learn robotics")
        model.items = [
            .user(UserMessagePayload(text: "Learn robotics")),
            .assistantText(text: "Complete answer.")
        ]
        model.handleEventForTesting(try Self.event(type: "agent_settled"))
        await generator.waitUntilStarted()

        appModel.standaloneSessions[0].name = "User Chosen Name"
        appModel.standaloneSessions[0].titleSource = .authoritative
        await generator.release()
        try await waitUntil { appModel.standaloneSessions[0].automaticTitleState == .complete }

        XCTAssertEqual(appModel.standaloneSessions[0].name, "User Chosen Name")
        XCTAssertEqual(appModel.standaloneSessions[0].titleSource, .authoritative)
    }

    // 2119: REQ-008.2.3
    func testRPCSessionNameReplacementWinsAgainstLateAutomaticResult() async throws {
        let fixture = try TitleRPCFixture(mode: "session-name-on-third-state")
        defer { fixture.cleanup() }
        setenv("PI_NATIVE_TEST_PI_EXECUTABLE", fixture.executable.path, 1)
        defer { unsetenv("PI_NATIVE_TEST_PI_EXECUTABLE") }
        let markerURL = fixture.directory.appendingPathComponent("generator-started")
        setenv("PI_NATIVE_TITLE_TEST_GENERATOR_MARKER", markerURL.path, 1)
        defer { unsetenv("PI_NATIVE_TITLE_TEST_GENERATOR_MARKER") }
        let generator = GatedTitleGenerator(output: "Late Automatic Title", startMarkerURL: markerURL)
        let (appModel, _, model) = makeNewChat(generator: generator, prompt: "Learn robotics")
        defer { appModel.stopAllRuntimes() }
        model.startProcessIfNeeded()
        try await waitUntil { !model.isLoadingSession }
        model.items = [
            .user(UserMessagePayload(text: "Learn robotics")),
            .assistantText(text: "Complete answer.")
        ]

        model.handleEventForTesting(try Self.event(type: "agent_settled"))
        await generator.waitUntilStarted()
        await generator.release()
        try await waitUntil { appModel.standaloneSessions[0].automaticTitleState == .complete }

        XCTAssertEqual(appModel.standaloneSessions[0].name, "External Session Name")
        XCTAssertEqual(appModel.standaloneSessions[0].titleSource, .authoritative)
    }

    // 2119: REQ-008.2.3
    func testProjectChatReplacementTitleWinsAgainstLateAutomaticResult() async throws {
        let generator = GatedTitleGenerator(output: "Late Automatic Title")
        let (appModel, sessionID, model) = makeNewProjectChat(generator: generator, prompt: "Learn robotics")
        model.items = [
            .user(UserMessagePayload(text: "Learn robotics")),
            .assistantText(text: "Complete answer.")
        ]
        model.handleEventForTesting(try Self.event(type: "agent_settled"))
        await generator.waitUntilStarted()

        appModel.projects[0].sessions[0].name = "Project Session Name"
        appModel.projects[0].sessions[0].titleSource = .authoritative
        await generator.release()
        try await waitUntil { appModel.projects[0].sessions[0].automaticTitleState == .complete }

        XCTAssertEqual(appModel.projects[0].sessions.first { $0.id == sessionID }?.name, "Project Session Name")
        XCTAssertEqual(appModel.projects[0].sessions.first { $0.id == sessionID }?.titleSource, .authoritative)
    }

    // 2119: REQ-008.2.3
    func testEmptyReplacementMarkerDoesNotBlockAutomaticTitle() async throws {
        let generator = GatedTitleGenerator(output: "Generated Robotics Title")
        let (appModel, _, model) = makeNewChat(generator: generator, prompt: "Learn robotics")
        model.items = [
            .user(UserMessagePayload(text: "Learn robotics")),
            .assistantText(text: "Complete answer.")
        ]
        model.handleEventForTesting(try Self.event(type: "agent_settled"))
        await generator.waitUntilStarted()

        appModel.standaloneSessions[0].name = "  "
        appModel.standaloneSessions[0].titleSource = .authoritative
        await generator.release()
        try await waitUntil { appModel.standaloneSessions[0].name == "Generated Robotics Title" }

        XCTAssertEqual(appModel.standaloneSessions[0].titleSource, .generated)
    }

    // 2119: REQ-008.1.1
    func testPendingGenerationDoesNotBlockComposerOrNavigation() async throws {
        let generator = GatedTitleGenerator(output: "Robotics Learning Guide")
        let (appModel, sessionID, model) = makeNewChat(generator: generator, prompt: "Learn robotics")
        model.items = [
            .user(UserMessagePayload(text: "Learn robotics")),
            .assistantText(text: "Complete answer.")
        ]
        model.handleEventForTesting(try Self.event(type: "agent_settled"))
        await generator.waitUntilStarted()

        XCTAssertEqual(appModel.standaloneSessions[0].name, "Learn robotics")
        XCTAssertEqual(appModel.standaloneSessions[0].titleSource, .fallback)
        XCTAssertFalse(model.isRunning)
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "Second response", 1)
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE_DELAY_MS", "1", 1)
        defer {
            unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
            unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE_DELAY_MS")
        }
        model.currentModel = PiModelOption(provider: "mock", id: "mock", name: "Mock")
        model.currentThinkingLevel = .medium
        let itemCountBeforeComposerSend = model.items.count
        model.draft = "Second prompt while title pending"
        model.sendDraft()
        XCTAssertEqual(model.draft, "")
        XCTAssertGreaterThan(model.items.count, itemCountBeforeComposerSend)
        XCTAssertEqual(appModel.standaloneSessions[0].name, "Learn robotics")
        XCTAssertEqual(appModel.standaloneSessions[0].titleSource, .fallback)

        let other = Session(name: "Other chat", status: .idle)
        appModel.standaloneSessions.append(other)
        appModel.select(sessionID: other.id, in: nil)
        XCTAssertEqual(appModel.selectedSessionID, other.id)
        XCTAssertNotEqual(appModel.selectedSessionID, sessionID)

        await generator.release()
    }

    // 2119: REQ-008.1.2
    func testStoppedFirstRunCannotBeTitledByLaterSettlement() async throws {
        let generator = RecordingTitleGenerator(output: "Should Not Appear")
        let prompt = "Investigate robotics"
        let (appModel, _, model) = makeNewChat(generator: generator, prompt: prompt)
        model.items = [
            .user(UserMessagePayload(text: prompt)),
            .assistantText(text: "Partial response")
        ]
        model.handleEventForTesting(try Self.event(type: "agent_start"))
        model.stopActiveTurn()

        model.items.append(.user(UserMessagePayload(text: "Discuss films instead")))
        model.items.append(.assistantText(text: "Complete film response."))
        model.handleEventForTesting(try Self.event(type: "agent_start"))
        model.handleEventForTesting(try Self.event(type: "agent_settled"))
        await Task.yield()

        XCTAssertEqual(appModel.standaloneSessions[0].name, "Investigate robotics")
        XCTAssertEqual(appModel.standaloneSessions[0].automaticTitleState, .complete)
        let count = await generator.currentCallCount()
        XCTAssertEqual(count, 0)
    }

    private func makeNewChat(generator: any ChatTitleGenerating, prompt: String) -> (AppModel, UUID, PiConversationModel) {
        let appModel = AppModel(chatTitleGenerator: generator)
        appModel.automaticallyStartsPendingRuntimes = false
        appModel.projects = []
        appModel.standaloneSessions = []
        appModel.selectedProjectID = nil
        appModel.selectedSessionID = nil
        appModel.sendNewChatPrompt(PreparedPrompt(message: prompt, images: [], displayAttachments: []))
        let sessionID = appModel.standaloneSessions[0].id
        return (appModel, sessionID, appModel.activeConversationModel!)
    }

    private func makeNewProjectChat(generator: any ChatTitleGenerating, prompt: String) -> (AppModel, UUID, PiConversationModel) {
        let appModel = AppModel(chatTitleGenerator: generator)
        appModel.automaticallyStartsPendingRuntimes = false
        appModel.standaloneSessions = []
        let projectPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeChatTitleTests-\(UUID().uuidString)", isDirectory: true)
            .path
        projectSessionDefaultsKeys.insert("projects.sessions.\(projectPath)")
        let project = Project(name: "Title Test", path: projectPath, sessions: [], diffStats: nil)
        appModel.projects = [project]
        appModel.startNewChat(in: project.id)
        appModel.sendNewChatPrompt(PreparedPrompt(message: prompt, images: [], displayAttachments: []))
        let sessionID = appModel.projects[0].sessions[0].id
        return (appModel, sessionID, appModel.activeConversationModel!)
    }

    private func clearSessionDefaults() {
        for key in projectSessionDefaultsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        projectSessionDefaultsKeys.removeAll()
        UserDefaults.standard.removeObject(forKey: "projects.paths")
        UserDefaults.standard.removeObject(forKey: "projects.selectedPath")
        UserDefaults.standard.removeObject(forKey: "sessions.standalone")
    }

    private static func event(type: String) throws -> RPCEnvelope {
        let data = try JSONEncoder().encode(JSONValue.object(["type": .string(type)]))
        return try JSONDecoder().decode(RPCEnvelope.self, from: data)
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 5_000_000_000,
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let start = ContinuousClock.now
        while !(await condition()) {
            if ContinuousClock.now - start > .nanoseconds(Int64(timeoutNanoseconds)) {
                XCTFail("Timed out waiting for chat title state")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

final class PiRPCEventOrderingTests: XCTestCase {
    func testRapidSubprocessEventsAreDeliveredInWireOrder() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeOrderedRPC-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("ordered-events.py")
        try Self.orderedEventFixture.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let recorder = EventRecorder()
        let client = PiRPCClient(piCommand: PiCommand(executable: executable.path, arguments: []), workingDirectory: directory)
        await client.setOnEvent { event in
            if event.type == "message_update" {
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
            await recorder.append(event.type ?? "")
        }
        try await client.start()
        try await recorder.waitForCount(6)
        await client.stop()

        let recordedTypes = await recorder.recordedTypes()
        XCTAssertEqual(recordedTypes, [
            "agent_start", "message_start", "message_update",
            "message_end", "agent_end", "agent_settled"
        ])
    }

    private static let orderedEventFixture = """
    #!/usr/bin/python3
    import json, sys, time
    events = [
      {"type":"agent_start"},
      {"type":"message_start","message":{"role":"assistant","content":[]}},
      {"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"final text"}},
      {"type":"message_end","message":{"role":"assistant","content":[{"type":"text","text":"final text"}]}},
      {"type":"agent_end","willRetry":False},
      {"type":"agent_settled"}
    ]
    sys.stdout.write("".join(json.dumps(event) + "\\n" for event in events))
    sys.stdout.flush()
    time.sleep(5)
    """
}

final class PiChatTitleServiceTests: XCTestCase {
    // 2119: REQ-008.2.2
    // 2119: REQ-008.3.2
    func testIsolatedTitleRPCUsesNoSessionAndTerminatesAfterSuccess() async throws {
        let fixture = try TitleRPCFixture(mode: "success")
        defer { fixture.cleanup() }
        let service = PiChatTitleService(timeoutNanoseconds: 2_000_000_000)

        let sessionListBeforeTitleGeneration = try String(contentsOf: fixture.sessionListFile, encoding: .utf8)
        let filesBeforeTitleGeneration = try Set(FileManager.default.contentsOfDirectory(atPath: fixture.directory.path))

        let output = try await service.generateTitle(
            for: FirstExchangeSnapshot(userPrompt: "Learn robotics", assistantText: "Complete answer"),
            workingDirectory: fixture.directory.path
        )

        XCTAssertEqual(output, "Robotics Learning Guide")
        let arguments = try String(contentsOf: fixture.argumentsFile, encoding: .utf8)
        for required in ["--mode", "rpc", "--no-session", "--no-tools", "--no-extensions", "--no-skills", "--no-prompt-templates", "--no-context-files"] {
            XCTAssertTrue(arguments.split(separator: "\n").contains(Substring(required)), "Missing \(required)")
        }
        XCTAssertTrue(arguments.contains("Learn robotics"))
        XCTAssertTrue(arguments.contains("Complete answer"))
        XCTAssertFalse(try fixture.isHelperRunning())
        XCTAssertEqual(try String(contentsOf: fixture.sessionListFile, encoding: .utf8), sessionListBeforeTitleGeneration)
        let filesAfterTitleGeneration = try Set(FileManager.default.contentsOfDirectory(atPath: fixture.directory.path))
        XCTAssertEqual(filesAfterTitleGeneration.subtracting(filesBeforeTitleGeneration), ["arguments.txt", "exited.txt", "pid.txt"])
    }

    // 2119: REQ-008.3.2
    func testFailedTitleRPCTerminatesHelper() async throws {
        let fixture = try TitleRPCFixture(mode: "failure")
        defer { fixture.cleanup() }
        let service = PiChatTitleService(timeoutNanoseconds: 2_000_000_000)

        do {
            _ = try await service.generateTitle(
                for: FirstExchangeSnapshot(userPrompt: "Learn robotics", assistantText: "Complete answer"),
                workingDirectory: fixture.directory.path
            )
            XCTFail("Expected failure")
        } catch {
            XCTAssertTrue(error is PiChatTitleService.GenerationError || error is PiRPCClient.ClientError)
        }
        XCTAssertFalse(try fixture.isHelperRunning())
    }

    // 2119: REQ-008.3.2
    func testTimedOutTitleRPCTerminatesHelper() async throws {
        let fixture = try TitleRPCFixture(mode: "timeout")
        defer { fixture.cleanup() }
        let service = PiChatTitleService(timeoutNanoseconds: 100_000_000)

        do {
            _ = try await service.generateTitle(
                for: FirstExchangeSnapshot(userPrompt: "Learn robotics", assistantText: "Complete answer"),
                workingDirectory: fixture.directory.path
            )
            XCTFail("Expected timeout")
        } catch {
            XCTAssertTrue(error is PiChatTitleService.GenerationError)
        }
        XCTAssertFalse(try fixture.isHelperRunning())
    }

}

private enum TestTitleError: Error { case expected }

private actor RecordingTitleGenerator: ChatTitleGenerating {
    private let output: String?
    private let error: TestTitleError?
    private var snapshots: [FirstExchangeSnapshot] = []

    init(output: String) {
        self.output = output
        self.error = nil
    }

    init(error: TestTitleError) {
        self.output = nil
        self.error = error
    }

    func generateTitle(for snapshot: FirstExchangeSnapshot, workingDirectory: String) async throws -> String {
        snapshots.append(snapshot)
        if let error { throw error }
        return output!
    }

    func currentCallCount() -> Int { snapshots.count }
    func firstSnapshot() -> FirstExchangeSnapshot? { snapshots.first }
}

private actor GatedTitleGenerator: ChatTitleGenerating {
    private let output: String
    private let startMarkerURL: URL?
    private var callCount = 0
    private var snapshots: [FirstExchangeSnapshot] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    init(output: String, startMarkerURL: URL? = nil) {
        self.output = output
        self.startMarkerURL = startMarkerURL
    }

    func generateTitle(for snapshot: FirstExchangeSnapshot, workingDirectory: String) async throws -> String {
        callCount += 1
        snapshots.append(snapshot)
        if let startMarkerURL {
            try "started".write(to: startMarkerURL, atomically: true, encoding: .utf8)
        }
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { releaseContinuations.append($0) }
        return output
    }

    func waitUntilStarted() async {
        if callCount > 0 { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func currentCallCount() -> Int { callCount }
    func firstSnapshot() -> FirstExchangeSnapshot? { snapshots.first }

    func release() {
        releaseContinuations.forEach { $0.resume() }
        releaseContinuations.removeAll()
    }
}

private actor EventRecorder {
    private(set) var types: [String] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func append(_ type: String) {
        types.append(type)
        let ready = waiters.filter { types.count >= $0.0 }
        waiters.removeAll { types.count >= $0.0 }
        ready.forEach { $0.1.resume() }
    }

    func waitForCount(_ count: Int) async throws {
        if types.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func recordedTypes() -> [String] { types }
}

private struct TitleRPCFixture {
    let directory: URL
    let executable: URL
    let argumentsFile: URL
    let exitFile: URL
    let pidFile: URL
    let sessionListFile: URL
    static let initialSessionList = "[\"existing-session\"]"

    init(mode: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeTitleRPC-\(UUID().uuidString)", isDirectory: true)
        executable = directory.appendingPathComponent("title-rpc.py")
        argumentsFile = directory.appendingPathComponent("arguments.txt")
        exitFile = directory.appendingPathComponent("exited.txt")
        pidFile = directory.appendingPathComponent("pid.txt")
        sessionListFile = directory.appendingPathComponent("sessions.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.initialSessionList.write(to: sessionListFile, atomically: true, encoding: .utf8)
        try Self.script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        setenv("PI_NATIVE_TEST_TITLE_PI_EXECUTABLE", executable.path, 1)
        setenv("PI_NATIVE_TITLE_TEST_ARGS", argumentsFile.path, 1)
        setenv("PI_NATIVE_TITLE_TEST_EXIT", exitFile.path, 1)
        setenv("PI_NATIVE_TITLE_TEST_PID", pidFile.path, 1)
        setenv("PI_NATIVE_TITLE_TEST_MODE", mode, 1)
    }

    func cleanup() {
        unsetenv("PI_NATIVE_TEST_TITLE_PI_EXECUTABLE")
        unsetenv("PI_NATIVE_TITLE_TEST_ARGS")
        unsetenv("PI_NATIVE_TITLE_TEST_EXIT")
        unsetenv("PI_NATIVE_TITLE_TEST_PID")
        unsetenv("PI_NATIVE_TITLE_TEST_MODE")
        try? FileManager.default.removeItem(at: directory)
    }

    func isHelperRunning() throws -> Bool {
        guard FileManager.default.fileExists(atPath: pidFile.path) else { return false }
        let pidText = try String(contentsOf: pidFile, encoding: .utf8)
        let pid = try XCTUnwrap(Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)))
        return kill(pid, 0) == 0
    }

    func waitUntilHelperStarted() async throws {
        if FileManager.default.fileExists(atPath: pidFile.path) { return }
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        if FileManager.default.fileExists(atPath: pidFile.path) {
            close(descriptor)
            return
        }
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "PiNativeTests.TitleRPCFixture.start")
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: .write,
                queue: queue
            )
            source.setEventHandler {
                guard FileManager.default.fileExists(atPath: pidFile.path) else { return }
                source.cancel()
                continuation.resume()
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
        }
    }

    private static let script = """
    #!/usr/bin/python3
    import json, os, signal, sys
    open(os.environ["PI_NATIVE_TITLE_TEST_PID"], "w").write(str(os.getpid()))
    arguments_path = os.environ["PI_NATIVE_TITLE_TEST_ARGS"]
    open(arguments_path, "w").write("\\n".join(sys.argv[1:]))
    if "--no-session" not in sys.argv[1:]:
      open("sessions.json", "w").write('["existing-session","title-helper-session"]')
    exit_path = os.environ["PI_NATIVE_TITLE_TEST_EXIT"]
    def mark_exit(*_):
      open(exit_path, "w").write("exited")
      sys.exit(0)
    signal.signal(signal.SIGTERM, mark_exit)
    try:
      for line in sys.stdin:
        command = json.loads(line)
        with open(arguments_path, "a") as trace:
          trace.write("\\nCOMMAND:" + command["type"] + ":" + command.get("message", ""))
        response = {"id":command.get("id"),"type":"response","command":command["type"],"success":True}
        if os.environ["PI_NATIVE_TITLE_TEST_MODE"] == "failure" and command["type"] == "prompt":
          response["success"] = False
          response["error"] = "prompt failed"
          sys.stdout.write(json.dumps(response) + "\\n")
          sys.stdout.flush()
          continue
        if command["type"] == "prompt":
          sys.stdout.write(json.dumps(response) + "\\n")
          if os.environ["PI_NATIVE_TITLE_TEST_MODE"] == "success":
            sys.stdout.write(json.dumps({"type":"agent_start"}) + "\\n")
            sys.stdout.write(json.dumps({"type":"agent_settled"}) + "\\n")
          sys.stdout.flush()
        elif command["type"] == "get_state":
          response["data"] = {"sessionFile":"/tmp/title-test-session.jsonl"}
          marker = os.environ.get("PI_NATIVE_TITLE_TEST_GENERATOR_MARKER")
          if os.environ["PI_NATIVE_TITLE_TEST_MODE"] == "session-name-on-third-state" and marker and os.path.exists(marker):
            response["data"]["sessionName"] = "External Session Name"
          sys.stdout.write(json.dumps(response) + "\\n")
          sys.stdout.flush()
        elif command["type"] == "get_last_assistant_text":
          response["data"] = {"text":"Robotics Learning Guide"}
          sys.stdout.write(json.dumps(response) + "\\n")
          sys.stdout.flush()
        else:
          sys.stdout.write(json.dumps(response) + "\\n")
          sys.stdout.flush()
    finally:
      open(exit_path, "w").write("exited")
    """
}
