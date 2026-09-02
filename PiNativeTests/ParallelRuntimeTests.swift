import Combine
import Darwin
import XCTest
@testable import PiNative

@MainActor
final class ParallelRuntimeTests: XCTestCase {
    func testPendingSteeringRemainsWithChatAcrossNavigation() throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "later response", 1)
        defer { unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE") }
        let appModel = testAppModel()
        let projectID = appModel.projects[0].id
        let first = appModel.projects[0].sessions[0]
        let second = appModel.projects[0].sessions[1]
        appModel.select(sessionID: first.id, in: projectID)
        let firstModel = try XCTUnwrap(appModel.activeConversationModel)
        firstModel.currentModel = PiModelOption(provider: "test", id: "selected", name: "Selected")
        firstModel.currentThinkingLevel = .medium
        firstModel.start(workingDirectory: nil, sessionPath: nil)
        firstModel.handleEventForTesting(try Self.event(type: "agent_start"))
        firstModel.draft = "stay with first chat"
        firstModel.sendDraft()
        firstModel.draft = "stay second"
        firstModel.sendDraft()
        firstModel.draft = "stay third"
        firstModel.sendDraft()

        appModel.select(sessionID: second.id, in: projectID)
        firstModel.handleEventForTesting(try Self.userMessageStart("stay with first chat"))
        appModel.select(sessionID: first.id, in: projectID)

        // 2119: REQ-003.7.23
        XCTAssertEqual(appModel.activeConversationModel?.pendingSteering.map(\.prepared.summaryText), ["stay second", "stay third"])
    }

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
        firstModel.handleEventForTesting(try Self.event(type: "agent_start"))
        let firstTranscriptBeforeOutput = firstModel.items
        appModel.select(sessionID: second.id, in: projectID)

        // 2119: REQ-003.4.5
        firstModel.handleEventForTesting(try Self.textDelta("output for first only"))

        let updatedFirst = try XCTUnwrap(appModel.projects[0].sessions.first { $0.id == first.id })
        let updatedSecond = try XCTUnwrap(appModel.projects[0].sessions.first { $0.id == second.id })
        XCTAssertEqual(updatedFirst.cachedTranscript.count, firstTranscriptBeforeOutput.count + 1)
        XCTAssertEqual(Array(updatedFirst.cachedTranscript.dropLast()), firstTranscriptBeforeOutput)
        guard case .assistantText(_, let appendedText) = updatedFirst.cachedTranscript.last else {
            return XCTFail("Expected in-flight output to append as the final owning-chat item")
        }
        XCTAssertEqual(appendedText, "output for first only")
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
        XCTAssertTrue(appModel.activeConversationModel === secondModel)
        appModel.activeConversationModel?.stopActiveTurn()
        XCTAssertTrue(appModel.isConversationRunning(sessionID: first.id, projectID: projectID))
        XCTAssertFalse(appModel.isConversationRunning(sessionID: second.id, projectID: projectID))
    }

    func testQuickChatCreationNavigationDraftsAndOutputAreIsolatedFromProjectChats() throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "parallel response", 1)
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE_DELAY_MS", "2500", 1)
        defer {
            unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
            unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE_DELAY_MS")
        }
        let appModel = testAppModel()
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
        // 2119: REQ-003.6.4
        XCTAssertEqual(projectModel.draft, "")
        projectModel.draft = "project-only draft"

        appModel.startNewChat()
        appModel.sendNewChatPrompt(PreparedPrompt(message: "second quick plan", images: [], displayAttachments: []))
        let secondQuickChat = try XCTUnwrap(appModel.standaloneSessions.first { $0.id != quickChat.id })
        let secondQuickModel = try XCTUnwrap(appModel.activeConversationModel)
        // 2119: REQ-003.6.4
        XCTAssertEqual(secondQuickModel.draft, "")
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
        let quickTranscriptBeforeOutput = quickModel.items
        quickModel.handleEventForTesting(try Self.textDelta("quick output only"))
        let updatedQuick = try XCTUnwrap(appModel.standaloneSessions.first { $0.id == quickChat.id })
        let updatedSecondQuick = try XCTUnwrap(appModel.standaloneSessions.first { $0.id == secondQuickChat.id })
        let updatedProject = try XCTUnwrap(appModel.projects[0].sessions.first { $0.id == projectChat.id })
        XCTAssertEqual(updatedQuick.cachedTranscript.count, quickTranscriptBeforeOutput.count + 1)
        XCTAssertEqual(Array(updatedQuick.cachedTranscript.dropLast()), quickTranscriptBeforeOutput)
        guard case .assistantText(_, let appendedText) = updatedQuick.cachedTranscript.last else {
            return XCTFail("Expected Quick Chat output to append as the final transcript item")
        }
        XCTAssertEqual(appendedText, "quick output only")
        XCTAssertFalse(updatedSecondQuick.cachedTranscript.contains { item in
            if case .assistantText(_, let text) = item { return text.contains("quick output only") }
            return false
        })
        XCTAssertFalse(updatedProject.cachedTranscript.contains { item in
            if case .assistantText(_, let text) = item { return text.contains("quick output only") }
            return false
        })
    }

    func testQuickChatRPCOutputPersistsOnlyToQuickChatAfterNavigation() async throws {
        unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
        let fixture = try QuickChatOutputRPCFixture()
        defer { fixture.cleanup() }
        let appModel = testAppModel { modelSettings in
            let model = PiConversationModel(
                piCommand: PiCommand(executable: fixture.executable.path, arguments: []),
                modelSettings: modelSettings
            )
            model.shouldStallRPCOverrideForTesting = false
            return model
        }
        defer { appModel.stopAllRuntimes() }
        let projectID = appModel.projects[0].id
        let projectChat = appModel.projects[0].sessions[0]

        appModel.startNewChat()
        appModel.sendNewChatPrompt(PreparedPrompt(message: "quick RPC output", images: [], displayAttachments: []))
        let quickChat = try XCTUnwrap(appModel.standaloneSessions.first)
        let quickModel = try XCTUnwrap(appModel.activeConversationModel)

        var cancellables: Set<AnyCancellable> = []
        if !quickModel.isRunning {
            let running = expectation(description: "Quick Chat RPC turn starts")
            quickModel.$isRunning
                .filter { $0 }
                .prefix(1)
                .sink { _ in running.fulfill() }
                .store(in: &cancellables)
            await fulfillment(of: [running], timeout: 3)
            guard quickModel.isRunning else { return }
        }

        appModel.select(sessionID: projectChat.id, in: projectID)
        XCTAssertEqual(appModel.selectedSessionID, projectChat.id)
        let outputPersisted = expectation(description: "Quick Chat RPC output is persisted")
        appModel.$standaloneSessions
            .filter { sessions in
                sessions.first(where: { $0.id == quickChat.id })?.cachedTranscript.contains { item in
                    if case .assistantText(_, let text) = item { return text.contains("quick output only") }
                    return false
                } == true
            }
            .prefix(1)
            .sink { _ in outputPersisted.fulfill() }
            .store(in: &cancellables)

        try fixture.releaseOutput()
        await fulfillment(of: [outputPersisted], timeout: 3)

        // 2119: REQ-003.6.6
        let updatedQuick = try XCTUnwrap(appModel.standaloneSessions.first { $0.id == quickChat.id })
        let updatedProject = try XCTUnwrap(appModel.projects[0].sessions.first { $0.id == projectChat.id })
        XCTAssertTrue(updatedQuick.cachedTranscript.contains { item in
            if case .assistantText(_, let text) = item { return text.contains("quick output only") }
            return false
        })
        XCTAssertFalse(updatedProject.cachedTranscript.contains { item in
            if case .assistantText(_, let text) = item { return text.contains("quick output only") }
            return false
        })
        XCTAssertTrue(appModel.activeConversationModel !== quickModel)
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

    private func testAppModel(
        projectCount: Int = 1,
        firstCachedTranscript: [TranscriptItem] = [.user(UserMessagePayload(text: "first seed"))],
        conversationModelFactory: ((ModelSettingsModel) -> PiConversationModel)? = nil
    ) -> AppModel {
        let appModel = AppModel(conversationModelFactory: conversationModelFactory)
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

    private static func userMessageStart(_ text: String) throws -> RPCEnvelope {
        try envelope([
            "type": .string("message_start"),
            "message": .object([
                "role": .string("user"),
                "content": .array([.object(["type": .string("text"), "text": .string(text)])])
            ])
        ])
    }

    private static func envelope(_ raw: [String: JSONValue]) throws -> RPCEnvelope {
        let data = try JSONEncoder().encode(JSONValue.object(raw))
        return try JSONDecoder().decode(RPCEnvelope.self, from: data)
    }
}

private struct QuickChatOutputRPCFixture {
    let directory: URL
    let executable: URL
    let outputGate: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeQuickChatOutput-\(UUID().uuidString)", isDirectory: true)
        executable = directory.appendingPathComponent("fake-pi-rpc.sh")
        outputGate = directory.appendingPathComponent("output-gate")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard mkfifo(outputGate.path, 0o600) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        try Self.script(outputGate: outputGate).write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    func releaseOutput() throws {
        let handle = try FileHandle(forWritingTo: outputGate)
        try handle.write(contentsOf: Data("release\n".utf8))
        try handle.close()
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func script(outputGate: URL) -> String {
        """
        #!/bin/sh
        output_gate='\(outputGate.path)'
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"type":"prompt"'*)
              exec 3<> "$output_gate"
              printf '%s\n' '{"type":"agent_start"}'
              printf '{"id":%s,"type":"response","success":true,"data":{}}\n' "$id"
              IFS= read -r _ <&3
              exec 3>&-
              printf '%s\n' '{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"quick output only"}}'
              ;;
            *'"type":"get_state"'*)
              printf '{"id":%s,"type":"response","success":true,"data":{"model":{"provider":"test","id":"selected","name":"Selected"},"thinkingLevel":"medium"}}\n' "$id"
              ;;
            *'"type":"get_available_models"'*)
              printf '{"id":%s,"type":"response","success":true,"data":{"models":[{"provider":"test","id":"selected","name":"Selected"}]}}\n' "$id"
              ;;
            *'"type":"get_available_thinking_levels"'*)
              printf '{"id":%s,"type":"response","success":true,"data":{"levels":["low","medium","high"]}}\n' "$id"
              ;;
            *)
              printf '{"id":%s,"type":"response","success":true,"data":{}}\n' "$id"
              ;;
          esac
        done
        """
    }
}
