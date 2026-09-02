import Combine
import PostHog
import XCTest
@testable import PiNative

@MainActor
final class AnalyticsTests: XCTestCase {
    // 2119: REQ-010.1.1
    // 2119: REQ-010.2.2
    func testAppLaunchReportsAppOpenedOnlyWhenAnalyticsAreEnabled() {
        let client = RecordingAnalyticsClient()
        let service = makeService(client: client)

        _ = PiNativeApp(analytics: service)
        service.setEnabled(false)
        _ = PiNativeApp(analytics: service)

        XCTAssertEqual(client.events, [RecordedAnalyticsEvent(name: "app_opened", properties: [:])])
    }

    // 2119: REQ-010.4.1
    func testPostHogConfigurationDisablesAutomaticExceptionTracking() {
        let configuration = PostHogAnalyticsClient.configuration(apiKey: "phc_test")

        XCTAssertFalse(configuration.errorTrackingConfig.autoCapture)
    }

    // 2119: REQ-010.1.1
    // 2119: REQ-010.2.2
    func testAppModelReportsChatSettingsAndRightPaneInteractions() {
        let client = RecordingAnalyticsClient()
        let service = makeService(client: client)
        let appModel = AppModel(analytics: service)

        appModel.startNewChat()
        appModel.startNewChat(in: UUID())
        appModel.presentSettings()
        appModel.openRightPane(.browser)
        appModel.selectRightPaneMode(.plugins)
        appModel.selectRightPaneMode(.archivedChats)
        service.setEnabled(false)
        appModel.startNewChat()
        appModel.presentSettings()
        appModel.openRightPane(.review)
        appModel.selectRightPaneMode(.archivedChats)

        XCTAssertEqual(client.events, [
            RecordedAnalyticsEvent(name: "chat_started", properties: [:]),
            RecordedAnalyticsEvent(name: "chat_started", properties: [:]),
            RecordedAnalyticsEvent(name: "settings_opened", properties: [:]),
            RecordedAnalyticsEvent(name: "right_pane_opened", properties: ["pane": "browser"]),
            RecordedAnalyticsEvent(name: "right_pane_opened", properties: ["pane": "plugins"]),
            RecordedAnalyticsEvent(name: "right_pane_opened", properties: ["pane": "archivedChats"])
        ])
    }

    // 2119: REQ-010.3.1
    func testSubmittedPromptWithAttachmentReportsNoAttachmentName() {
        let client = RecordingAnalyticsClient()
        let appModel = AppModel(analytics: makeService(client: client))
        appModel.automaticallyStartsPendingRuntimes = false
        let attachmentName = "super-secret-quarterly-plan.pdf"
        let attachment = ComposerAttachment(kind: .fileReference(FileReferenceAttachment(
            url: URL(fileURLWithPath: "/tmp/\(attachmentName)"),
            displayName: attachmentName,
            fileSize: 42
        )))
        let prompt = PreparedPrompt(message: "see attached", images: [], displayAttachments: [attachment])

        appModel.sendNewChatPrompt(prompt)

        XCTAssertEqual(client.events, [RecordedAnalyticsEvent(name: "prompt_submitted", properties: [:])])
        XCTAssertFalse(client.events.flatMap { [$0.name] + Array($0.properties.values) }.joined().contains(attachmentName))
    }

    // 2119: REQ-010.3.1
    func testSubmittedPromptWithImageAttachmentReportsNoAttachmentContent() {
        let client = RecordingAnalyticsClient()
        let appModel = AppModel(analytics: makeService(client: client))
        appModel.automaticallyStartsPendingRuntimes = false
        let marker = "SECRET_IMAGE_BYTES_MARKER"
        let attachment = ComposerAttachment(kind: .image(ImageAttachment(
            data: Data(marker.utf8),
            mimeType: "image/png",
            displayName: "confidential-diagram.png",
            sourceURL: nil,
            pixelWidth: nil,
            pixelHeight: nil
        )))
        let prompt = PreparedPrompt(message: "see the diagram", images: [], displayAttachments: [attachment])

        appModel.sendNewChatPrompt(prompt)

        XCTAssertEqual(client.events, [RecordedAnalyticsEvent(name: "prompt_submitted", properties: [:])])
        XCTAssertFalse(client.events.flatMap { [$0.name] + Array($0.properties.values) }.joined().contains(marker))
    }

    // 2119: REQ-010.1.1
    // 2119: REQ-010.3.1
    func testSubmittedPromptReportsNoPromptContent() {
        let analytics = RecordingAnalyticsClient()
        let appModel = AppModel(analytics: analytics)
        appModel.automaticallyStartsPendingRuntimes = false
        let prompt = PreparedPrompt(message: "a private prompt", images: [], displayAttachments: [])

        appModel.sendNewChatPrompt(prompt)

        let disabledClient = RecordingAnalyticsClient()
        let disabledService = makeService(client: disabledClient)
        disabledService.setEnabled(false)
        let disabledAppModel = AppModel(analytics: disabledService)
        disabledAppModel.automaticallyStartsPendingRuntimes = false
        disabledAppModel.sendNewChatPrompt(prompt)

        XCTAssertEqual(analytics.events, [RecordedAnalyticsEvent(name: "prompt_submitted", properties: [:])])
        XCTAssertTrue(disabledClient.events.isEmpty)
    }

    // 2119: REQ-010.1.1
    func testExistingChatPromptReportsSubmissionThroughInstalledRuntimeCallback() throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "mock response", 1)
        defer { unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE") }

        let client = RecordingAnalyticsClient()
        let appModel = AppModel(analytics: makeService(client: client))
        appModel.automaticallyStartsPendingRuntimes = false
        let session = Session(name: "Existing chat", status: .idle)
        appModel.standaloneSessions = [session]
        appModel.select(sessionID: session.id, in: nil)
        let model = try XCTUnwrap(appModel.activeConversationModel)
        model.currentModel = PiModelOption(provider: "test", id: "selected", name: "Selected")
        model.currentThinkingLevel = .medium
        model.draft = "ordinary chat prompt"

        model.sendDraft()
        appModel.stopAllRuntimes()

        XCTAssertEqual(client.events, [RecordedAnalyticsEvent(name: "prompt_submitted", properties: [:])])
    }

    // 2119: REQ-010.2.1
    // 2119: REQ-010.2.2
    func testSettingsAnalyticsPreferenceStopsReportingAndPersistsBothStates() {
        let suiteName = "PiNativeTests.AnalyticsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = RecordingAnalyticsClient()
        let service = AnalyticsService(apiKey: "phc_test", defaults: defaults, client: client)
        let appModel = AppModel(analytics: service)

        appModel.presentSettings()
        appModel.analyticsEnabled = false
        service.track(.settingsOpened)
        let disabledRelaunch = AnalyticsService(apiKey: "phc_test", defaults: defaults, client: RecordingAnalyticsClient())
        appModel.analyticsEnabled = true
        service.track(.settingsOpened)
        let enabledRelaunch = AnalyticsService(apiKey: "phc_test", defaults: defaults, client: RecordingAnalyticsClient())

        XCTAssertTrue(appModel.isSettingsPresented)
        XCTAssertFalse(disabledRelaunch.isEnabled)
        XCTAssertTrue(enabledRelaunch.isEnabled)
        XCTAssertEqual(client.events, [
            RecordedAnalyticsEvent(name: "settings_opened", properties: [:]),
            RecordedAnalyticsEvent(name: "settings_opened", properties: [:])
        ])
        XCTAssertEqual(client.enabledStates.suffix(2), [false, true])
    }

    // 2119: REQ-010.1.1
    // 2119: REQ-010.3.1
    func testDiagnosticEventsUseOnlyFixedAllowlistedProperties() {
        let loadFailure = PiLoadFailure(stage: .sessionLoad, error: PiRPCClient.ClientError.processExited)
        let handledFailure = HandledPiOperationFailure(area: .promptSubmission, error: PiRPCClient.ClientError.processExited)
        let events: [AnalyticsEvent] = [
            .appOpened,
            .chatStarted,
            .promptSubmitted,
            .settingsOpened,
            .rightPaneOpened(.review),
            .piLoadFailed(loadFailure, isProjectChat: true),
            .handledException(handledFailure)
        ]

        XCTAssertEqual(events.map(\.properties), [
            [:], [:], [:], [:],
            ["pane": "review"],
            ["stage": "session_load", "failure_kind": "process_lifecycle", "is_project_chat": "true"],
            ["area": "prompt_submission", "failure_kind": "unknown"]
        ])
        XCTAssertEqual(events.map(\.name), ["app_opened", "chat_started", "prompt_submitted", "settings_opened", "right_pane_opened", "pi_load_failed", "handled_exception"])
    }

    // 2119: REQ-010.1.1
    // 2119: REQ-010.3.1
    func testFailureKindClassifiersUseTheirRespectiveFixedTaxonomies() {
        XCTAssertEqual(PiLoadFailure(stage: .processStart, error: NSError(domain: "test", code: 1)).failureKind, .launchFailed)
        XCTAssertEqual(PiLoadFailure(stage: .sessionLoad, error: PiRPCClient.ClientError.requestTimedOut(1)).failureKind, .requestTimedOut)
        XCTAssertEqual(PiLoadFailure(stage: .sessionLoad, error: PiRPCClient.ClientError.invalidResponse("private response")).failureKind, .invalidResponse)
        XCTAssertEqual(PiLoadFailure(stage: .sessionLoad, error: PiRPCClient.ClientError.writeFailed).failureKind, .writeFailed)
        XCTAssertEqual(PiLoadFailure(stage: .sessionLoad, error: PiRPCClient.ClientError.requestCancelled(1)).failureKind, .unknown)

        XCTAssertEqual(HandledPiOperationFailure(area: .modelSelection, error: PiRPCClient.ClientError.requestTimedOut(1)).failureKind, .requestTimedOut)
        XCTAssertEqual(HandledPiOperationFailure(area: .effortSelection, error: PiRPCClient.ClientError.invalidResponse("private response")).failureKind, .invalidResponse)
        XCTAssertEqual(HandledPiOperationFailure(area: .extensionUIResponse, error: PiRPCClient.ClientError.writeFailed).failureKind, .writeFailed)
        let processExitFailure = HandledPiOperationFailure(area: .promptSubmission, error: PiRPCClient.ClientError.processExited)
        let launchFailure = HandledPiOperationFailure(area: .promptSubmission, error: NSError(domain: "private", code: 1))
        XCTAssertEqual(processExitFailure.failureKind, .unknown)
        XCTAssertEqual(launchFailure.failureKind, .unknown)
        XCTAssertNotEqual(processExitFailure.failureKind, .processLifecycle)
        XCTAssertNotEqual(launchFailure.failureKind, .launchFailed)
        XCTAssertEqual(PiOperationArea.allCases.map(\.rawValue), ["model_selection", "effort_selection", "prompt_submission", "extension_ui_response"])
        XCTAssertEqual(AnalyticsFailureKind.allCases.map(\.rawValue), ["process_lifecycle", "request_timed_out", "invalid_response", "write_failed", "launch_failed", "unknown"])
    }

    // 2119: REQ-010.3.1
    func testDiagnosticEventsRejectSensitiveRawErrorText() {
        let forbidden = "private prompt /tmp/workspace attachment.png session-123 project-456 provider-model account@example.com"
        let events: [AnalyticsEvent] = [
            .piLoadFailed(PiLoadFailure(stage: .sessionLoad, error: PiRPCClient.ClientError.invalidResponse(forbidden)), isProjectChat: false),
            .handledException(HandledPiOperationFailure(area: .promptSubmission, error: NSError(domain: forbidden, code: 1)))
        ]

        XCTAssertEqual(events.map(\.properties), [
            ["stage": "session_load", "failure_kind": "invalid_response", "is_project_chat": "false"],
            ["area": "prompt_submission", "failure_kind": "unknown"]
        ])
        XCTAssertFalse(events.flatMap(\.properties.values).joined().contains(forbidden))
    }

    // 2119: REQ-010.5.1
    func testMissingOrInvalidProjectKeyDisablesAnalyticsWithoutPreventingAppActions() {
        for key in [nil, "not-a-project-key"] as [String?] {
            let client = RecordingAnalyticsClient()
            let service = AnalyticsService(apiKey: key, client: client)
            let appModel = AppModel(analytics: service)

            appModel.startNewChat()
            appModel.openRightPane(.browser)
            service.track(.appOpened)

            XCTAssertTrue(client.events.isEmpty)
            XCTAssertEqual(appModel.rightPaneMode, .browser)
        }

        let configuredClient = RecordingAnalyticsClient()
        let configuredService = makeService(client: configuredClient)
        configuredService.track(.appOpened)
        XCTAssertEqual(configuredClient.events, [RecordedAnalyticsEvent(name: "app_opened", properties: [:])])
    }

    // 2119: REQ-010.1.1
    // 2119: REQ-010.2.2
    func testAppModelDerivesProjectBackedLoadFailureFromTheRuntimeKey() throws {
        let root = try temporaryDirectory(named: "PiNativeAnalyticsProjectFlag")
        defer { try? FileManager.default.removeItem(at: root) }
        let projectSession = Session(name: "project chat", status: .idle)
        let standaloneSession = Session(name: "standalone chat", status: .idle)
        let project = Project(name: "Analytics", path: root.path, sessions: [projectSession], diffStats: nil)
        let analytics = RecordingAnalyticsClient()
        let service = makeService(client: analytics)
        let appModel = AppModel(analytics: service)
        appModel.automaticallyStartsPendingRuntimes = false
        appModel.projects = [project]
        appModel.standaloneSessions = [standaloneSession]

        appModel.select(sessionID: projectSession.id, in: project.id)
        let projectModel = try XCTUnwrap(appModel.activeConversationModel)
        appModel.select(sessionID: standaloneSession.id, in: nil)
        let standaloneModel = try XCTUnwrap(appModel.activeConversationModel)
        projectModel.onPiLoadFailed?(PiLoadFailure(stage: .sessionLoad, error: PiRPCClient.ClientError.processExited))
        standaloneModel.onPiLoadFailed?(PiLoadFailure(stage: .sessionLoad, error: PiRPCClient.ClientError.processExited))
        projectModel.onHandledPiOperationFailure?(HandledPiOperationFailure(area: .promptSubmission, error: PiRPCClient.ClientError.processExited))
        service.setEnabled(false)
        projectModel.onPiLoadFailed?(PiLoadFailure(stage: .sessionLoad, error: PiRPCClient.ClientError.processExited))
        projectModel.onHandledPiOperationFailure?(HandledPiOperationFailure(area: .promptSubmission, error: PiRPCClient.ClientError.processExited))

        XCTAssertEqual(analytics.events, [
            RecordedAnalyticsEvent(name: "pi_load_failed", properties: ["stage": "session_load", "failure_kind": "process_lifecycle", "is_project_chat": "true"]),
            RecordedAnalyticsEvent(name: "pi_load_failed", properties: ["stage": "session_load", "failure_kind": "process_lifecycle", "is_project_chat": "false"]),
            RecordedAnalyticsEvent(name: "handled_exception", properties: ["area": "prompt_submission", "failure_kind": "unknown"])
        ])
    }

    // 2119: REQ-010.1.1
    // 2119: REQ-010.1.2
    func testTerminalPiStartFailureReportsExactlyOneSanitizedEvent() async throws {
        let root = try temporaryDirectory(named: "PiNativeAnalyticsStartFailure")
        defer { try? FileManager.default.removeItem(at: root) }
        let analytics = RecordingAnalyticsClient()
        let model = PiConversationModel(piCommand: PiCommand(executable: root.appendingPathComponent("missing-pi").path, arguments: []))
        let reported = expectation(description: "terminal process start failure")
        model.onPiLoadFailed = { failure in
            analytics.track(.piLoadFailed(failure, isProjectChat: false))
            reported.fulfill()
        }
        model.start(workingDirectory: root.path, sessionPath: nil)
        defer { model.stop() }

        await fulfillment(of: [reported], timeout: 3)

        XCTAssertEqual(analytics.events, [
            RecordedAnalyticsEvent(
                name: "pi_load_failed",
                properties: ["stage": "process_start", "failure_kind": "launch_failed", "is_project_chat": "false"]
            )
        ])
    }

    // 2119: REQ-010.1.1
    // 2119: REQ-010.1.2
    func testTerminalPiSessionLoadFailureReportsExactlyOneSanitizedEvent() async throws {
        let root = try temporaryDirectory(named: "PiNativeAnalyticsLoadFailure")
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("fake-pi-rpc.sh")
        try """
        #!/bin/sh
        sleep 0.05
        exit 42
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let analytics = RecordingAnalyticsClient()
        let model = PiConversationModel(piCommand: PiCommand(executable: script.path, arguments: []))
        let reported = expectation(description: "terminal session load failure")
        model.onPiLoadFailed = { failure in
            analytics.track(.piLoadFailed(failure, isProjectChat: true))
            reported.fulfill()
        }
        model.start(workingDirectory: root.path, sessionPath: nil)
        defer { model.stop() }

        await fulfillment(of: [reported], timeout: 3)

        XCTAssertEqual(analytics.events, [
            RecordedAnalyticsEvent(
                name: "pi_load_failed",
                properties: ["stage": "session_load", "failure_kind": "process_lifecycle", "is_project_chat": "true"]
            )
        ])
    }

    // 2119: REQ-010.1.2
    func testRecoveredPiSessionLoadFailureDoesNotReportTerminalFailure() async throws {
        let root = try temporaryDirectory(named: "PiNativeAnalyticsRecoveredLoad")
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("fake-pi-rpc.sh")
        try """
        #!/bin/sh
        attempt="$PWD/.attempt"
        if [ ! -f "$attempt" ]; then
          touch "$attempt"
          sleep 0.05
          exit 42
        fi
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"type":"new_session"'*) printf '{"id":%s,"type":"response","success":true,"data":{}}\\n' "$id" ;;
            *'"type":"get_state"'*) printf '{"id":%s,"type":"response","success":true,"data":{"model":{"provider":"test","id":"selected","name":"Selected"},"thinkingLevel":"medium"}}\\n' "$id" ;;
            *'"type":"get_available_models"'*) printf '{"id":%s,"type":"response","success":true,"data":{"models":[{"provider":"test","id":"selected","name":"Selected"}]}}\\n' "$id" ;;
            *'"type":"get_available_thinking_levels"'*) printf '{"id":%s,"type":"response","success":true,"data":{"levels":["low","medium","high"]}}\\n' "$id" ;;
            *) printf '{"id":%s,"type":"response","success":true,"data":{}}\\n' "$id" ;;
          esac
        done
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let analytics = RecordingAnalyticsClient()
        let model = PiConversationModel(piCommand: PiCommand(executable: script.path, arguments: []))
        let ready = expectation(description: "recovered Pi session ready")
        let readyObserver = model.$currentModel.compactMap { $0 }.first().sink { _ in ready.fulfill() }
        model.onPiLoadFailed = { failure in analytics.track(.piLoadFailed(failure, isProjectChat: false)) }
        model.start(workingDirectory: root.path, sessionPath: nil)
        defer { model.stop() }

        await fulfillment(of: [ready], timeout: 3)
        withExtendedLifetime(readyObserver) {}
        XCTAssertTrue(analytics.events.isEmpty)
    }

    // 2119: REQ-010.1.1
    // 2119: REQ-010.5.1
    func testFailedPromptReportsHandledExceptionOnlyWhenAnalyticsAreConfigured() async throws {
        for (apiKey, expectedEvents) in [
            (Optional("phc_test"), [RecordedAnalyticsEvent(name: "handled_exception", properties: ["area": "prompt_submission", "failure_kind": "unknown"])]),
            (nil, [])
        ] as [(String?, [RecordedAnalyticsEvent])] {
            let root = try temporaryDirectory(named: "PiNativeAnalyticsPromptFailure")
            defer { try? FileManager.default.removeItem(at: root) }
            let script = root.appendingPathComponent("fake-pi-rpc.sh")
            try """
            #!/bin/sh
            while IFS= read -r line; do
              id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
              case "$line" in
                *'"type":"new_session"'*) printf '{"id":%s,"type":"response","success":true,"data":{}}\\n' "$id" ;;
                *'"type":"get_state"'*) printf '{"id":%s,"type":"response","success":true,"data":{"model":{"provider":"test","id":"selected","name":"Selected"},"thinkingLevel":"medium"}}\\n' "$id" ;;
                *'"type":"get_available_models"'*) printf '{"id":%s,"type":"response","success":true,"data":{"models":[{"provider":"test","id":"selected","name":"Selected"}]}}\\n' "$id" ;;
                *'"type":"get_available_thinking_levels"'*) printf '{"id":%s,"type":"response","success":true,"data":{"levels":["low","medium","high"]}}\\n' "$id" ;;
                *'"type":"prompt"'*) exit 42 ;;
                *) printf '{"id":%s,"type":"response","success":true,"data":{}}\\n' "$id" ;;
              esac
            done
            """.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

            let client = RecordingAnalyticsClient()
            let analytics = AnalyticsService(apiKey: apiKey, client: client)
            let model = PiConversationModel(piCommand: PiCommand(executable: script.path, arguments: []))
            let ready = expectation(description: "Pi session ready")
            let readyObserver = model.$currentModel
                .compactMap { $0 }
                .first()
                .sink { _ in ready.fulfill() }
            let reported = expectation(description: "handled prompt failure")
            model.onHandledPiOperationFailure = { failure in
                analytics.track(.handledException(failure))
                reported.fulfill()
            }
            model.start(workingDirectory: root.path, sessionPath: nil)
            await fulfillment(of: [ready], timeout: 3)
            withExtendedLifetime(readyObserver) {}
            model.draft = "private prompt text"
            model.sendDraft()

            await fulfillment(of: [reported], timeout: 3)
            model.stop()

            XCTAssertEqual(client.events, expectedEvents)
        }
    }

    // 2119: REQ-010.1.1
    func testFailedModelAndEffortSelectionsReportTheirSanitizedAreas() async throws {
        for (command, area) in [("set_model", PiOperationArea.modelSelection), ("set_thinking_level", .effortSelection)] {
            let root = try temporaryDirectory(named: "PiNativeAnalyticsSelectionFailure")
            defer { try? FileManager.default.removeItem(at: root) }
            let script = root.appendingPathComponent("fake-pi-rpc.sh")
            try """
            #!/bin/sh
            while IFS= read -r line; do
              id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
              case "$line" in
                *'"type":"new_session"'*) printf '{"id":%s,"type":"response","success":true,"data":{}}\\n' "$id" ;;
                *'"type":"get_state"'*) printf '{"id":%s,"type":"response","success":true,"data":{"model":{"provider":"test","id":"selected","name":"Selected"},"thinkingLevel":"medium"}}\\n' "$id" ;;
                *'"type":"get_available_models"'*) printf '{"id":%s,"type":"response","success":true,"data":{"models":[{"provider":"test","id":"selected","name":"Selected"}]}}\\n' "$id" ;;
                *'"type":"get_available_thinking_levels"'*) printf '{"id":%s,"type":"response","success":true,"data":{"levels":["low","medium","high"]}}\\n' "$id" ;;
                *'"type":"\(command)"'*) exit 42 ;;
                *) printf '{"id":%s,"type":"response","success":true,"data":{}}\\n' "$id" ;;
              esac
            done
            """.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

            let analytics = RecordingAnalyticsClient()
            let model = PiConversationModel(piCommand: PiCommand(executable: script.path, arguments: []))
            let ready = expectation(description: "Pi session ready for \(command)")
            let readyObserver = model.$currentModel.compactMap { $0 }.first().sink { _ in ready.fulfill() }
            let reported = expectation(description: "handled \(command) failure")
            model.onHandledPiOperationFailure = { failure in
                analytics.track(.handledException(failure))
                reported.fulfill()
            }
            model.start(workingDirectory: root.path, sessionPath: nil)
            await fulfillment(of: [ready], timeout: 3)
            withExtendedLifetime(readyObserver) {}
            if command == "set_model" {
                model.selectModel(PiModelOption(provider: "test", id: "other", name: "Other"))
            } else {
                model.selectThinkingLevel(.high)
            }
            defer { model.stop() }

            await fulfillment(of: [reported], timeout: 3)
            XCTAssertEqual(analytics.events, [
                RecordedAnalyticsEvent(name: "handled_exception", properties: ["area": area.rawValue, "failure_kind": "unknown"])
            ])
        }
    }

    // 2119: REQ-010.1.1
    func testUnsupportedExtensionUIPromptReportsHandledExceptionForExtensionArea() async throws {
        let root = try temporaryDirectory(named: "PiNativeAnalyticsExtensionUIFailure")
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("fake-pi-rpc.sh")
        try """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"type":"new_session"'*) printf '{"id":%s,"type":"response","success":true,"data":{}}\\n' "$id" ;;
            *'"type":"get_state"'*) printf '{"id":%s,"type":"response","success":true,"data":{"model":{"provider":"test","id":"selected","name":"Selected"},"thinkingLevel":"medium"}}\\n' "$id" ;;
            *'"type":"get_available_models"'*) printf '{"id":%s,"type":"response","success":true,"data":{"models":[{"provider":"test","id":"selected","name":"Selected"}]}}\\n' "$id" ;;
            *'"type":"get_available_thinking_levels"'*)
              printf '{"id":%s,"type":"response","success":true,"data":{"levels":["low","medium","high"]}}\\n' "$id"
              exit 0
              ;;
            *) printf '{"id":%s,"type":"response","success":true,"data":{}}\\n' "$id" ;;
          esac
        done
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let analytics = RecordingAnalyticsClient()
        let model = PiConversationModel(piCommand: PiCommand(executable: script.path, arguments: []))
        let ready = expectation(description: "Pi session ready")
        let readyObserver = model.$currentModel.compactMap { $0 }.first().sink { _ in ready.fulfill() }
        let reported = expectation(description: "handled extension UI response failure")
        model.onHandledPiOperationFailure = { failure in
            analytics.track(.handledException(failure))
            reported.fulfill()
        }
        model.start(workingDirectory: root.path, sessionPath: nil)
        await fulfillment(of: [ready], timeout: 3)
        withExtendedLifetime(readyObserver) {}

        // Give the fake pi process time to fully exit so the auto-dismissed
        // extension UI response write genuinely fails against a dead process,
        // instead of racing process termination.
        try await Task.sleep(nanoseconds: 300_000_000)
        model.handleEventForTesting(try Self.extensionUIRequestEvent(method: "confirm"))
        defer { model.stop() }

        await fulfillment(of: [reported], timeout: 3)

        XCTAssertEqual(analytics.events, [
            RecordedAnalyticsEvent(name: "handled_exception", properties: ["area": "extension_ui_response", "failure_kind": "unknown"])
        ])
    }

    private static func extensionUIRequestEvent(method: String) throws -> RPCEnvelope {
        let data = try JSONEncoder().encode(JSONValue.object([
            "type": .string("extension_ui_request"),
            "id": .string("test-extension-ui-request"),
            "method": .string(method),
            "title": .string("Confirm")
        ]))
        return try JSONDecoder().decode(RPCEnvelope.self, from: data)
    }

    private func makeService(client: RecordingAnalyticsClient) -> AnalyticsService {
        let suiteName = "PiNativeTests.AnalyticsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AnalyticsService(apiKey: "phc_test", defaults: defaults, client: client)
    }
}

@MainActor
private final class RecordingAnalyticsClient: AnalyticsControlling, AnalyticsClient {
    private(set) var isEnabled = true
    private(set) var events: [RecordedAnalyticsEvent] = []
    private(set) var enabledStates: [Bool] = []

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        enabledStates.append(isEnabled)
    }

    func track(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        capture(name: event.name, properties: event.properties)
    }

    func capture(name: String, properties: [String: String]) {
        events.append(RecordedAnalyticsEvent(name: name, properties: properties))
    }
}

private struct RecordedAnalyticsEvent: Equatable {
    let name: String
    let properties: [String: String]
}

@MainActor
private func temporaryDirectory(named prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
