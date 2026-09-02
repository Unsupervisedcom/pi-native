import XCTest
@testable import PiNative

@MainActor
final class ChatReadinessTests: XCTestCase {
    // 2119: REQ-005.2.1
    func testEffortSelectorInteractivityPolicyIgnoresSessionLoadingUntilCatastrophicFailure() {
        XCTAssertTrue(ChatComposerInteractivity.modelAndEffortControlsEnabled(isCatastrophicRPCFailure: false, isLoadingSession: false))
        XCTAssertTrue(ChatComposerInteractivity.modelAndEffortControlsEnabled(isCatastrophicRPCFailure: false, isLoadingSession: true))
        XCTAssertFalse(ChatComposerInteractivity.modelAndEffortControlsEnabled(isCatastrophicRPCFailure: true, isLoadingSession: false))
        XCTAssertFalse(ChatComposerInteractivity.modelAndEffortControlsEnabled(isCatastrophicRPCFailure: true, isLoadingSession: true))
    }

    func testTransientExtensionChromeUpdatesDoNotPolluteTranscript() {
        let model = PiConversationModel()

        for index in 0..<3 {
            for method in ["setStatus", "setTitle"] {
                let eventJSON = """
                {
                  "type": "extension_ui_request",
                  "id": "chrome-\(method)-\(index)",
                  "method": "\(method)",
                  "title": "Transient title \(index)",
                  "message": "Transient status \(index)"
                }
                """.data(using: .utf8)!
                let event = try! JSONDecoder().decode(RPCEnvelope.self, from: eventJSON)
                model.handleEventForTesting(event)
            }
        }

        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNil(model.rpcStatusMessage)
    }

    func testCachedSetTitleFallbackNoticesAreRemovedWithoutDroppingOtherNotices() {
        let model = PiConversationModel()
        model.configureSession(
            workingDirectory: nil,
            sessionPath: "cached-session",
            cachedItems: [
                .notice("Pi requested unsupported UI interaction: setTitle."),
                .notice("Keep this useful notice.")
            ]
        )

        XCTAssertEqual(model.items.count, 1)
        guard case .notice(_, let text) = model.items[0] else {
            return XCTFail("Expected the unrelated notice to remain")
        }
        XCTAssertEqual(text, "Keep this useful notice.")
    }

    func testEveryExtensionUIPromptMethodBeforeSessionReadySurfacesStatus() {
        let agentStartData = #"{"type":"agent_start"}"#.data(using: .utf8)!
        let agentStart = try! JSONDecoder().decode(RPCEnvelope.self, from: agentStartData)

        for method in ["confirm", "select", "input", "editor"] {
            let loadingModel = PiConversationModel()
            loadingModel.isLoadingSession = true
            let readyModel = PiConversationModel()
            readyModel.configureSession(workingDirectory: nil, sessionPath: nil)
            XCTAssertTrue(loadingModel.isLoadingSession)
            XCTAssertFalse(readyModel.isLoadingSession)

            loadingModel.handleEventForTesting(agentStart)
            readyModel.handleEventForTesting(agentStart)
            XCTAssertFalse(loadingModel.isRunning, "The loading fixture must reject ordinary turn events before readiness")
            XCTAssertTrue(readyModel.isRunning, "The ready control must accept ordinary turn events")

            let eventJSON = """
            {
              "type": "extension_ui_request",
              "id": "prompt-\(method)",
              "method": "\(method)",
              "title": "pi config out of sync",
              "message": "Resolve the \(method) request"
            }
            """.data(using: .utf8)!
            let event = try! JSONDecoder().decode(RPCEnvelope.self, from: eventJSON)

            // 2119: REQ-005.2.2
            loadingModel.handleEventForTesting(event)
            readyModel.handleEventForTesting(event)

            for model in [loadingModel, readyModel] {
                XCTAssertTrue(model.rpcStatusMessage?.contains("pi config out of sync") == true, "Missing status for \(method)")
                XCTAssertTrue(model.items.contains { item in
                    if case .notice(_, let text) = item {
                        return text.contains("pi config out of sync") && text.contains("Resolve the \(method) request")
                    }
                    return false
                }, "Missing transcript feedback for \(method)")
            }
        }
    }

    // 2119: REQ-005.2.1
    func testRealRPCProcessExitMarksDisplayedChatCatastrophicAndDisablesComposerState() async throws {
        let script = try temporaryDirectory(named: "PiNativeRPCExitScript").appendingPathComponent("fake-pi-rpc.sh")
        defer {
            try? FileManager.default.removeItem(at: script.deletingLastPathComponent())
        }
        try """
        #!/bin/sh
        # Accept stdin briefly so PiNative can send the first RPC command, then exit like a crashed RPC process.
        sleep 0.05
        exit 42
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")

        let model = PiConversationModel(piCommand: PiCommand(executable: script.path, arguments: []))
        model.start(
            workingDirectory: script.deletingLastPathComponent().path,
            sessionPath: nil,
            cachedItems: [.user(UserMessagePayload(text: "cached chat remains displayed"))]
        )

        try await waitUntil(timeout: 3) { model.isCatastrophicRPCFailure }

        XCTAssertEqual(model.rpcStatusMessage, "Failed to load session: pi exited.")
        XCTAssertEqual(model.sessionLoadNotice, model.rpcStatusMessage)
        XCTAssertTrue(model.isCatastrophicRPCFailure)
        XCTAssertFalse(model.isRunning)
        XCTAssertFalse(model.items.isEmpty)
    }

    // 2119: REQ-005.2.1
    func testBackgroundRPCProcessExitDoesNotContaminateDisplayedChatComposerState() async throws {
        let root = try temporaryDirectory(named: "PiNativeBackgroundRPCExit")
        let script = root.appendingPathComponent("fake-pi-rpc.sh")
        try """
        #!/bin/sh
        sleep 0.05
        exit 42
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        setenv("PI_NATIVE_RESET_PROJECTS", "1", 1)
        setenv("PI_NATIVE_TEST_PI_EXECUTABLE", script.path, 1)
        unsetenv("PI_NATIVE_TEST_RPC_STALL")
        unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
        defer {
            unsetenv("PI_NATIVE_RESET_PROJECTS")
            unsetenv("PI_NATIVE_TEST_PI_EXECUTABLE")
            try? FileManager.default.removeItem(at: root)
        }

        let displayedSession = Session(
            name: "displayed healthy chat",
            status: .idle,
            cachedTranscript: [.user(UserMessagePayload(text: "displayed transcript"))]
        )
        let backgroundSession = Session(
            name: "background failing chat",
            status: .idle,
            cachedTranscript: [.user(UserMessagePayload(text: "background transcript"))]
        )
        let project = Project(name: "Failure Isolation", path: root.path, sessions: [displayedSession, backgroundSession], diffStats: nil)
        let appModel = AppModel()
        appModel.automaticallyStartsPendingRuntimes = false
        appModel.projects = [project]
        appModel.select(sessionID: backgroundSession.id, in: project.id)
        let backgroundModel = try XCTUnwrap(appModel.activeConversationModel)
        appModel.select(sessionID: displayedSession.id, in: project.id)
        let displayedModel = try XCTUnwrap(appModel.activeConversationModel)
        defer { appModel.stopAllRuntimes() }

        backgroundModel.start(
            workingDirectory: root.path,
            sessionPath: nil,
            cachedItems: backgroundSession.cachedTranscript
        )
        try await waitUntil(timeout: 3) { backgroundModel.isCatastrophicRPCFailure }

        XCTAssertTrue(backgroundModel.isCatastrophicRPCFailure)
        XCTAssertTrue(appModel.activeConversationModel === displayedModel)
        XCTAssertFalse(displayedModel.isCatastrophicRPCFailure)
        XCTAssertNil(displayedModel.sessionLoadNotice)
        XCTAssertTrue(ChatComposerInteractivity.modelAndEffortControlsEnabled(
            isCatastrophicRPCFailure: displayedModel.isCatastrophicRPCFailure,
            isLoadingSession: displayedModel.isLoadingSession
        ))
    }
}

@MainActor
private func waitUntil(timeout: TimeInterval, condition: @escaping @MainActor () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail("Timed out waiting for condition")
}

private func temporaryDirectory(named prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
