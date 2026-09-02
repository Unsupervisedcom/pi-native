import XCTest
@testable import PiNative

@MainActor
final class ParallelRuntimeTests: XCTestCase {
    func testRunningChatDoesNotBlockSelectingAnotherChatOrNewChatSurface() throws {
        let appModel = testAppModel()
        let first = appModel.projects[0].sessions[0]
        let second = appModel.projects[0].sessions[1]

        appModel.select(sessionID: first.id, in: appModel.projects[0].id)
        let firstModel = try XCTUnwrap(appModel.activeConversationModel)
        firstModel.handleEventForTesting(try Self.event(type: "agent_start"))
        XCTAssertTrue(firstModel.isRunning)

        // 2119: REQ-003.4.1
        appModel.select(sessionID: second.id, in: appModel.projects[0].id)
        XCTAssertEqual(appModel.selectedSessionID, second.id)
        XCTAssertTrue(appModel.isConversationRunning(sessionID: first.id, projectID: appModel.projects[0].id))

        // 2119: REQ-003.4.8
        appModel.startNewChat()
        XCTAssertNil(appModel.selectedSessionID)
        XCTAssertTrue(appModel.isConversationRunning(sessionID: first.id, projectID: appModel.projects[0].id))
        appModel.sendNewChatPrompt(PreparedPrompt(message: "new chat while first runs", images: [], displayAttachments: []))
        let createdQuickChat = try XCTUnwrap(appModel.standaloneSessions.first)
        XCTAssertEqual(appModel.selectedProjectID, nil)
        XCTAssertEqual(appModel.selectedSessionID, createdQuickChat.id)
        XCTAssertTrue(appModel.isConversationRunning(sessionID: first.id, projectID: appModel.projects[0].id))
    }

    func testRuntimeCallbacksRouteOutputToOwningChatAfterSelectionChanges() throws {
        let appModel = testAppModel()
        let projectID = appModel.projects[0].id
        let first = appModel.projects[0].sessions[0]
        let second = appModel.projects[0].sessions[1]

        appModel.select(sessionID: first.id, in: projectID)
        let firstModel = try XCTUnwrap(appModel.activeConversationModel)
        appModel.select(sessionID: second.id, in: projectID)

        // 2119: REQ-003.4.5
        firstModel.handleEventForTesting(try Self.textDelta("output for first only"))

        let updatedFirst = try XCTUnwrap(appModel.projects[0].sessions.first { $0.id == first.id })
        let updatedSecond = try XCTUnwrap(appModel.projects[0].sessions.first { $0.id == second.id })
        XCTAssertTrue(updatedFirst.cachedTranscript.contains { item in
            if case .assistantText(_, let text) = item { return text.contains("output for first only") }
            return false
        })
        XCTAssertFalse(updatedSecond.cachedTranscript.contains { item in
            if case .assistantText(_, let text) = item { return text.contains("output for first only") }
            return false
        })
    }

    func testExistingSessionWithoutCachedTranscriptStartsHydrationOnSelection() throws {
        let appModel = testAppModel(firstCachedTranscript: [])
        let first = appModel.projects[0].sessions[0]

        appModel.select(sessionID: first.id, in: appModel.projects[0].id)
        let model = try XCTUnwrap(appModel.activeConversationModel)

        XCTAssertTrue(model.isLoadingSession || model.isProcessStarted)
    }

    func testProjectSelectionPendingPromptAndCompletionStateAreIndependent() throws {
        let appModel = testAppModel(projectCount: 2)
        appModel.automaticallyStartsPendingRuntimes = false
        let firstProjectID = appModel.projects[0].id
        let secondProjectID = appModel.projects[1].id
        let first = appModel.projects[0].sessions[0]
        let second = appModel.projects[0].sessions[1]
        let otherProjectChat = appModel.projects[1].sessions[0]

        appModel.select(sessionID: first.id, in: firstProjectID)
        let firstModel = try XCTUnwrap(appModel.activeConversationModel)
        firstModel.handleEventForTesting(try Self.event(type: "agent_start"))

        // 2119: REQ-003.4.2
        appModel.select(projectID: secondProjectID)
        XCTAssertEqual(appModel.selectedProjectID, secondProjectID)
        XCTAssertEqual(appModel.selectedSessionID, otherProjectChat.id)

        XCTAssertTrue(appModel.isConversationRunning(sessionID: first.id, projectID: firstProjectID))

        firstModel.handleEventForTesting(try Self.event(type: "agent_end"))
        XCTAssertTrue(appModel.isConversationRunning(sessionID: first.id, projectID: firstProjectID))
        firstModel.handleEventForTesting(try Self.event(type: "agent_settled"))
        XCTAssertFalse(appModel.isConversationRunning(sessionID: first.id, projectID: firstProjectID))

        appModel.select(sessionID: first.id, in: firstProjectID)
        let pendingModel = try XCTUnwrap(appModel.activeConversationModel)
        pendingModel.configureSession(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            sessionPath: first.filePath,
            initialPrompt: PreparedPrompt(message: "queued prompt", images: [], displayAttachments: []),
            cachedItems: [],
            planningMode: false
        )
        XCTAssertTrue(appModel.isConversationWorking(sessionID: first.id, projectID: firstProjectID))

        // 2119: REQ-003.4.7
        appModel.select(sessionID: second.id, in: firstProjectID)
        XCTAssertEqual(appModel.selectedProjectID, firstProjectID)
        XCTAssertEqual(appModel.selectedSessionID, second.id)
        XCTAssertTrue(appModel.isConversationWorking(sessionID: first.id, projectID: firstProjectID))

        let pendingStartup = Session(
            name: "pending startup peer",
            status: .idle,
            filePath: "/tmp/parallel-runtime-pending-startup.jsonl",
            pendingInitialPrompt: PreparedPrompt(message: "startup prompt", images: [], displayAttachments: []),
            cachedTranscript: []
        )
        appModel.projects[0].sessions.append(pendingStartup)
        appModel.select(sessionID: pendingStartup.id, in: firstProjectID)
        XCTAssertTrue(appModel.isConversationWorking(sessionID: pendingStartup.id, projectID: firstProjectID))
        XCTAssertFalse(try XCTUnwrap(appModel.runtime(for: ConversationKey(projectID: firstProjectID, sessionID: pendingStartup.id))).isProcessStarted)

        // 2119: REQ-003.4.7
        appModel.select(sessionID: second.id, in: firstProjectID)
        XCTAssertEqual(appModel.selectedProjectID, firstProjectID)
        XCTAssertEqual(appModel.selectedSessionID, second.id)
        XCTAssertTrue(appModel.isConversationWorking(sessionID: pendingStartup.id, projectID: firstProjectID))
    }

    func testTwoChatsCanRunIndependentlyAndStopOnlySelectedChat() throws {
        let appModel = testAppModel()
        let projectID = appModel.projects[0].id
        let first = appModel.projects[0].sessions[0]
        let second = appModel.projects[0].sessions[1]

        appModel.select(sessionID: first.id, in: projectID)
        let firstModel = try XCTUnwrap(appModel.activeConversationModel)
        firstModel.handleEventForTesting(try Self.event(type: "agent_start"))

        appModel.select(sessionID: second.id, in: projectID)
        let secondModel = try XCTUnwrap(appModel.activeConversationModel)
        secondModel.handleEventForTesting(try Self.event(type: "agent_start"))

        XCTAssertTrue(appModel.isConversationRunning(sessionID: first.id, projectID: projectID))
        XCTAssertTrue(appModel.isConversationRunning(sessionID: second.id, projectID: projectID))

        // 2119: REQ-003.5.4
        secondModel.stopActiveTurn()
        XCTAssertTrue(appModel.isConversationRunning(sessionID: first.id, projectID: projectID))
        XCTAssertFalse(appModel.isConversationRunning(sessionID: second.id, projectID: projectID))
    }

    func testQuickChatCreationNavigationDraftsAndOutputAreIsolatedFromProjectChats() throws {
        let appModel = testAppModel()
        appModel.automaticallyStartsPendingRuntimes = false
        let projectID = appModel.projects[0].id
        let projectChat = appModel.projects[0].sessions[0]

        appModel.startNewChat()
        appModel.sendNewChatPrompt(PreparedPrompt(message: "quick plan", images: [], displayAttachments: []))
        let quickChat = try XCTUnwrap(appModel.standaloneSessions.first)

        XCTAssertEqual(appModel.selectedProjectID, nil)
        XCTAssertEqual(appModel.selectedSessionID, quickChat.id)
        XCTAssertEqual(appModel.standaloneSessions.count, 1)

        let quickModel = try XCTUnwrap(appModel.activeConversationModel)
        quickModel.draft = "quick-only draft"

        appModel.select(sessionID: projectChat.id, in: projectID)
        let projectModel = try XCTUnwrap(appModel.activeConversationModel)
        projectModel.draft = "project-only draft"

        appModel.startNewChat()
        appModel.sendNewChatPrompt(PreparedPrompt(message: "second quick plan", images: [], displayAttachments: []))
        let secondQuickChat = try XCTUnwrap(appModel.standaloneSessions.first { $0.id != quickChat.id })
        let secondQuickModel = try XCTUnwrap(appModel.activeConversationModel)
        secondQuickModel.draft = "second-quick-only draft"

        appModel.select(sessionID: quickChat.id, in: nil)
        XCTAssertEqual(appModel.selectedProjectID, nil)
        XCTAssertEqual(appModel.selectedSessionID, quickChat.id)

        // 2119: REQ-003.6.4
        XCTAssertEqual(try XCTUnwrap(appModel.activeConversationModel).draft, "quick-only draft")
        appModel.select(sessionID: projectChat.id, in: projectID)
        XCTAssertEqual(try XCTUnwrap(appModel.activeConversationModel).draft, "project-only draft")
        appModel.select(sessionID: secondQuickChat.id, in: nil)
        XCTAssertEqual(try XCTUnwrap(appModel.activeConversationModel).draft, "second-quick-only draft")
        XCTAssertNotEqual(try XCTUnwrap(appModel.activeConversationModel).draft, "quick-only draft")

        appModel.select(sessionID: quickChat.id, in: nil)
        quickModel.handleEventForTesting(try Self.event(type: "agent_start"))

        // 2119: REQ-003.6.5
        appModel.select(sessionID: projectChat.id, in: projectID)
        XCTAssertEqual(appModel.selectedSessionID, projectChat.id)
        let selectedProjectModel = try XCTUnwrap(appModel.activeConversationModel)
        XCTAssertTrue(selectedProjectModel === projectModel)
        XCTAssertFalse(selectedProjectModel === quickModel)
        selectedProjectModel.currentModel = PiModelOption(provider: "test", id: "selected", name: "Selected")
        selectedProjectModel.currentThinkingLevel = .medium
        selectedProjectModel.draft = "project work while quick runs"
        selectedProjectModel.sendDraft()
        XCTAssertTrue(selectedProjectModel.hasPendingPrompt || selectedProjectModel.isRunning || selectedProjectModel.isLoadingSession)
        XCTAssertTrue(selectedProjectModel.items.contains { item in
            if case .user(_, let payload) = item { return payload.text.contains("project work while quick runs") }
            return false
        })
        XCTAssertTrue(appModel.isConversationRunning(sessionID: quickChat.id, projectID: nil))

        // 2119: REQ-003.6.6
        quickModel.handleEventForTesting(try Self.textDelta("quick output only"))
        let updatedQuick = try XCTUnwrap(appModel.standaloneSessions.first { $0.id == quickChat.id })
        let updatedSecondQuick = try XCTUnwrap(appModel.standaloneSessions.first { $0.id == secondQuickChat.id })
        let updatedProject = try XCTUnwrap(appModel.projects[0].sessions.first { $0.id == projectChat.id })
        XCTAssertTrue(updatedQuick.cachedTranscript.contains { item in
            if case .assistantText(_, let text) = item { return text.contains("quick output only") }
            return false
        })
        XCTAssertFalse(updatedSecondQuick.cachedTranscript.contains { item in
            if case .assistantText(_, let text) = item { return text.contains("quick output only") }
            return false
        })
        XCTAssertFalse(updatedProject.cachedTranscript.contains { item in
            if case .assistantText(_, let text) = item { return text.contains("quick output only") }
            return false
        })
    }

    func testPromotingQuickChatArchivesSourceAndCleansRuntime() throws {
        let appModel = testAppModel()
        let source = Session(
            name: "planning quick chat",
            status: .idle,
            cachedTranscript: [.user(UserMessagePayload(text: "plan something"))]
        )
        appModel.standaloneSessions = [source]
        appModel.select(sessionID: source.id, in: nil)
        let sourceKey = ConversationKey(projectID: nil, sessionID: source.id)
        XCTAssertNotNil(appModel.runtime(for: sourceKey))

        appModel.presentPromoteToProject(session: source)
        _ = appModel.completePromotion(projectPath: FileManager.default.temporaryDirectory.appendingPathComponent("promoted-\(UUID().uuidString)").path)
        XCTAssertNil(appModel.runtime(for: sourceKey))
        XCTAssertTrue(try XCTUnwrap(appModel.standaloneSessions.first { $0.id == source.id }).isArchived)
        XCTAssertNotNil(appModel.selectedProjectID)
        XCTAssertNotNil(appModel.selectedSessionID)
    }

    func testArchiveBlocksQueuedPendingPromptAndPreservesRuntime() throws {
        let appModel = testAppModel()
        appModel.automaticallyStartsPendingRuntimes = false
        let projectID = appModel.projects[0].id
        let session = appModel.projects[0].sessions[0]
        let key = ConversationKey(projectID: projectID, sessionID: session.id)

        appModel.select(sessionID: session.id, in: projectID)
        let model = try XCTUnwrap(appModel.runtime(for: key))
        model.configureSession(
            workingDirectory: FileManager.default.temporaryDirectory.path,
            sessionPath: session.filePath,
            initialPrompt: PreparedPrompt(message: "queued prompt", images: [], displayAttachments: []),
            cachedItems: session.cachedTranscript,
            planningMode: false
        )

        appModel.archiveSession(sessionID: session.id, in: projectID)

        XCTAssertNotNil(appModel.runtime(for: key))
        XCTAssertFalse(try XCTUnwrap(appModel.projects[0].sessions.first { $0.id == session.id }).isArchived)
        XCTAssertEqual(appModel.blockedNavigationAlert?.title, "Chat is working")
    }

    func testStopAllRuntimesCleansEveryRuntime() throws {
        let appModel = testAppModel()
        let projectID = appModel.projects[0].id
        let first = appModel.projects[0].sessions[0]
        let second = appModel.projects[0].sessions[1]
        let firstKey = ConversationKey(projectID: projectID, sessionID: first.id)
        let secondKey = ConversationKey(projectID: projectID, sessionID: second.id)

        appModel.select(sessionID: first.id, in: projectID)
        XCTAssertNotNil(appModel.runtime(for: firstKey))
        appModel.select(sessionID: second.id, in: projectID)
        XCTAssertNotNil(appModel.runtime(for: secondKey))

        appModel.stopAllRuntimes()

        XCTAssertNil(appModel.runtime(for: firstKey))
        XCTAssertNil(appModel.runtime(for: secondKey))
        XCTAssertNil(appModel.activeConversationModel)
        XCTAssertFalse(appModel.activeConversationIsRunning)
    }

    private func testAppModel(projectCount: Int = 1, firstCachedTranscript: [TranscriptItem] = [.user(UserMessagePayload(text: "first seed"))]) -> AppModel {
        let appModel = AppModel()
        let first = Session(
            name: "first chat",
            status: .idle,
            filePath: "/tmp/parallel-runtime-first.jsonl",
            cachedTranscript: firstCachedTranscript
        )
        let second = Session(
            name: "second chat",
            status: .idle,
            filePath: "/tmp/parallel-runtime-second.jsonl",
            cachedTranscript: [.user(UserMessagePayload(text: "second seed"))]
        )
        let project = Project(name: "Parallel Runtime Test", path: FileManager.default.temporaryDirectory.path, sessions: [first, second])
        let projects: [Project]
        if projectCount > 1 {
            let other = Session(
                name: "other project chat",
                status: .idle,
                filePath: "/tmp/parallel-runtime-other-project.jsonl",
                cachedTranscript: [.user(UserMessagePayload(text: "other project seed"))]
            )
            projects = [project, Project(name: "Parallel Runtime Other Project", path: FileManager.default.temporaryDirectory.appendingPathComponent("other").path, sessions: [other])]
        } else {
            projects = [project]
        }
        appModel.projects = projects
        appModel.standaloneSessions = []
        appModel.selectedProjectID = project.id
        appModel.selectedSessionID = first.id
        appModel.select(sessionID: first.id, in: project.id)
        return appModel
    }

    private static func event(type: String) throws -> RPCEnvelope {
        try envelope(["type": .string(type)])
    }

    private static func textDelta(_ delta: String) throws -> RPCEnvelope {
        try envelope([
            "type": .string("message_update"),
            "assistantMessageEvent": .object([
                "type": .string("text_delta"),
                "delta": .string(delta)
            ])
        ])
    }

    private static func envelope(_ raw: [String: JSONValue]) throws -> RPCEnvelope {
        let data = try JSONEncoder().encode(JSONValue.object(raw))
        return try JSONDecoder().decode(RPCEnvelope.self, from: data)
    }
}
