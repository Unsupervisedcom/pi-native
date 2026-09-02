import XCTest
@testable import PiNative

@MainActor
final class StopButtonTests: XCTestCase {
    func testActiveTurnSubmissionCreatesPendingSteeringInsteadOfUserHistory() throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "later response", 1)
        defer { unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE") }
        let model = steeringReadyModel()
        model.handleEventForTesting(try Self.event(type: "agent_start"))
        model.draft = "  MiXeD  spacing\nnext café 👩🏽‍💻  "

        // 2119: REQ-003.7.1
        // 2119: REQ-003.7.2
        // 2119: REQ-003.7.3
        // 2119: REQ-003.7.5
        model.sendDraft()

        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.pendingSteering.map(\.prepared.summaryText), ["MiXeD  spacing\nnext café 👩🏽‍💻"])
        XCTAssertEqual(model.pendingSteering.first?.state, .accepted)
        XCTAssertFalse(model.items.contains { item in
            if case .user(_, let payload) = item { return payload.text == "MiXeD  spacing\nnext café 👩🏽‍💻" }
            return false
        })
    }

    func testAttachmentOnlySteeringPreservesDisplayMetadataAndRPCPayload() throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "later response", 1)
        defer { unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE") }
        let model = steeringReadyModel()
        model.handleEventForTesting(try Self.event(type: "agent_start"))
        let image = ComposerAttachment(kind: .image(ImageAttachment(
            data: Data([1, 2, 3]), mimeType: "image/png", displayName: "direction.png",
            sourceURL: nil, pixelWidth: 1, pixelHeight: 1
        )))
        model.addDraftAttachments([image])

        // 2119: REQ-003.7.6
        // 2119: REQ-003.7.7
        model.sendDraft()

        let pending = try XCTUnwrap(model.pendingSteering.first)
        XCTAssertEqual(pending.prepared.displayAttachments, [image])
        XCTAssertEqual(
            pending.prepared.displayAttachments,
            UserMessagePayload(text: pending.prepared.summaryText, attachments: [image]).attachments
        )
        XCTAssertEqual(pending.prepared.images.first?.data, Data([1, 2, 3]).base64EncodedString())
        XCTAssertTrue(model.draftAttachments.isEmpty)

        let fields = PiRPCClient.steerFields(message: pending.prepared.message, images: pending.prepared.images)
        XCTAssertEqual(fields["message"]?.stringValue, pending.prepared.message)
        XCTAssertEqual(fields["images"]?.arrayValue?.count, 1)
    }

    func testEmptyActiveTurnSubmissionDoesNotCreateSteering() throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "later response", 1)
        defer { unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE") }
        let model = steeringReadyModel()
        model.handleEventForTesting(try Self.event(type: "agent_start"))
        model.sendDraft()
        XCTAssertTrue(model.pendingSteering.isEmpty)
        model.draft = "  \n"

        // 2119: REQ-003.7.8
        model.sendDraft()

        XCTAssertTrue(model.pendingSteering.isEmpty)
    }

    func testAcceptedSteeringAppearsInConversationHistoryInUserOrder() throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "later response", 1)
        defer { unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE") }
        let model = steeringReadyModel()
        model.handleEventForTesting(try Self.event(type: "agent_start"))
        model.draft = "first distinct direction"
        model.sendDraft()
        model.draft = "second distinct direction"
        model.sendDraft()

        // 2119: REQ-003.7.9
        model.handleEventForTesting(try Self.userMessageStart("second server acknowledgement arrives first"))
        model.handleEventForTesting(try Self.userMessageStart("first server acknowledgement arrives second"))

        let deliveredUserMessages = model.items.compactMap { item -> String? in
            guard case .user(_, let payload) = item else { return nil }
            return payload.text
        }
        XCTAssertEqual(deliveredUserMessages, ["first distinct direction", "second distinct direction"])
    }

    func testPiUserEventPromotesOldestSteeringExactlyOnce() throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "later response", 1)
        defer { unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE") }
        let model = steeringReadyModel()
        let otherModel = steeringReadyModel()
        model.handleEventForTesting(try Self.event(type: "agent_start"))
        model.draft = "first duplicate"
        model.sendDraft()
        model.draft = "first duplicate"
        model.sendDraft()

        let delivery = try Self.userMessageStart("expanded server-side text")
        // 2119: REQ-003.7.10
        // 2119: REQ-003.7.11
        model.handleEventForTesting(delivery)

        XCTAssertEqual(model.pendingSteering.count, 1)
        XCTAssertEqual(model.pendingSteering.first?.prepared.summaryText, "first duplicate")
        XCTAssertEqual(model.items.filter { item in
            if case .user(_, let payload) = item { return payload.text == "first duplicate" }
            return false
        }.count, 1)

        model.handleEventForTesting(try Self.event(type: "message_end"))
        model.handleEventForTesting(delivery)
        model.handleEventForTesting(try Self.event(type: "message_end"))
        XCTAssertTrue(model.pendingSteering.isEmpty)
        XCTAssertEqual(model.items.filter { if case .user = $0 { return true }; return false }.count, 2)
        XCTAssertEqual(model.items.filter { item in
            if case .user(_, let payload) = item { return payload.text == "first duplicate" }
            return false
        }.count, 2)
        XCTAssertFalse(otherModel.items.contains { if case .user = $0 { return true }; return false })
    }

    func testOriginalPromptUserEventCannotPrematurelyDeliverQueuedSteering() throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "later response", 1)
        defer { unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE") }
        let model = steeringReadyModel()
        model.draft = "original prompt"
        model.sendDraft()
        model.draft = "steer after original"
        model.sendDraft()

        // The original prompt's user event may arrive after steering was
        // accepted; it is not the steering-delivery boundary.
        // 2119: REQ-003.7.10
        // 2119: REQ-003.7.11
        model.handleEventForTesting(try Self.userMessageStart("original prompt"))
        XCTAssertEqual(model.pendingSteering.map(\.prepared.summaryText), ["steer after original"])
        XCTAssertEqual(model.items.filter { item in
            if case .user(_, let payload) = item { return payload.text == "steer after original" }
            return false
        }.count, 0)

        model.handleEventForTesting(try Self.userMessageStart("steer after original"))
        XCTAssertTrue(model.pendingSteering.isEmpty)
        XCTAssertEqual(model.items.filter { item in
            if case .user(_, let payload) = item { return payload.text == "steer after original" }
            return false
        }.count, 1)
    }

    func testRejectedSteeringRestoresOriginalContentWithoutOverwritingNewDraft() async throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "bootstrap", 1)
        let model = steeringReadyModel()
        let otherModel = steeringReadyModel()
        otherModel.draft = "other chat draft"
        unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
        model.handleEventForTesting(try Self.event(type: "agent_start"))
        model.draft = "rejected direction"
        model.sendDraft()
        model.draft = "newer draft"

        // 2119: REQ-003.7.12
        // 2119: REQ-003.7.14
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertTrue(model.pendingSteering.isEmpty)
        XCTAssertEqual(model.draft, "rejected direction\n\nnewer draft")
        XCTAssertEqual(otherModel.draft, "other chat draft")
    }

    func testRejectedSteeringRestoresAttachments() async throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "bootstrap", 1)
        let model = steeringReadyModel()
        let otherModel = steeringReadyModel()
        let otherAttachment = ComposerAttachment(kind: .fileReference(FileReferenceAttachment(
            url: URL(fileURLWithPath: "/tmp/other.txt"), displayName: "other.txt", fileSize: 12
        )))
        otherModel.addDraftAttachments([otherAttachment])
        unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
        model.handleEventForTesting(try Self.event(type: "agent_start"))
        let file = ComposerAttachment(kind: .fileReference(FileReferenceAttachment(
            url: URL(fileURLWithPath: "/tmp/rejected.txt"),
            displayName: "rejected.txt",
            fileSize: nil
        )))
        let secondFile = ComposerAttachment(kind: .fileReference(FileReferenceAttachment(
            url: URL(fileURLWithPath: "/tmp/rejected-two.txt"),
            displayName: "rejected-two.txt",
            fileSize: 42
        )))
        model.addDraftAttachments([file, secondFile])
        model.sendDraft()

        // 2119: REQ-003.7.13
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertTrue(model.pendingSteering.isEmpty)
        XCTAssertEqual(model.draftAttachments, [file, secondFile])
        XCTAssertEqual(otherModel.draftAttachments, [otherAttachment])
    }

    func testStopReplaysFirstSteeringAndRetainsRemainingOrder() async throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "old stopped response", 1)
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE_DELAY_MS", "200", 1)
        defer {
            unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
            unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE_DELAY_MS")
        }
        let model = steeringReadyModel()
        model.draft = "active request"
        model.sendDraft()
        XCTAssertTrue(model.isRunning)
        model.draft = "first after stop"
        model.sendDraft()
        model.draft = "second after stop"
        model.sendDraft()
        var replayOrder: [String] = []
        var abortCount = 0
        model.onPromptRPCForTesting = { replayOrder.append("prompt:\($0)") }
        model.onSteeringRPCForTesting = { replayOrder.append("steer:\($0)") }
        model.onAbortRPCForTesting = { abortCount += 1 }
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "replacement response", 1)

        // 2119: REQ-003.7.15
        // 2119: REQ-003.7.16
        // 2119: REQ-003.7.17
        model.stopActiveTurn()
        XCTAssertFalse(model.isRunning)
        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(abortCount, 1)
        XCTAssertEqual(replayOrder, ["prompt:first after stop", "steer:second after stop"])
        XCTAssertTrue(model.items.contains { item in
            if case .user(_, let payload) = item { return payload.text == "first after stop" }
            return false
        })
        XCTAssertEqual(model.pendingSteering.map(\.prepared.summaryText), ["second after stop"])
        try await Task.sleep(nanoseconds: 220_000_000)
        XCTAssertFalse(model.items.contains { item in
            if case .assistantText(_, let text) = item { return text.contains("old stopped response") }
            return false
        })
    }

    func testStopKeepsUnacknowledgedSteeringUntilExactlyOnceReplayDisposition() async throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "bootstrap", 1)
        defer { unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE") }
        let model = steeringReadyModel()
        unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
        model.handleEventForTesting(try Self.event(type: "agent_start"))
        model.draft = "acknowledgement race"
        model.sendDraft()
        var replayedPrompts: [String] = []
        model.onPromptRPCForTesting = { replayedPrompts.append($0) }
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "replacement response", 1)

        // 2119: REQ-003.7.18
        // 2119: REQ-003.7.19
        model.stopActiveTurn()
        model.handleEventForTesting(try Self.userMessageStart("late old-process delivery"))

        XCTAssertEqual(model.pendingSteering.map(\.prepared.summaryText), ["acknowledgement race"])
        XCTAssertFalse(model.items.contains { item in
            if case .user(_, let payload) = item { return payload.text.contains("acknowledgement race") }
            return false
        })

        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertTrue(model.pendingSteering.isEmpty)
        XCTAssertEqual(replayedPrompts, ["acknowledgement race"])
        XCTAssertEqual(model.items.filter { item in
            if case .user(_, let payload) = item { return payload.text == "acknowledgement race" }
            return false
        }.count, 1)

        model.handleEventForTesting(try Self.userMessageStart("late acceptance after replay"))
        XCTAssertEqual(replayedPrompts, ["acknowledgement race"])
        XCTAssertEqual(model.items.filter { item in
            if case .user(_, let payload) = item { return payload.text == "acknowledgement race" }
            return false
        }.count, 1)
    }

    func testSteeringQueuesRemainIsolatedPerConversation() throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "later response", 1)
        defer { unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE") }
        let first = steeringReadyModel()
        let second = steeringReadyModel()
        first.handleEventForTesting(try Self.event(type: "agent_start"))
        second.handleEventForTesting(try Self.event(type: "agent_start"))
        first.draft = "only first"
        let firstItemsBefore = first.items
        let secondItemsBefore = second.items

        // 2119: REQ-003.7.20
        // 2119: REQ-003.7.21
        first.sendDraft()

        XCTAssertEqual(first.pendingSteering.map(\.prepared.summaryText), ["only first"])
        XCTAssertTrue(second.pendingSteering.isEmpty)
        second.handleEventForTesting(try Self.userMessageStart("unrelated"))
        XCTAssertEqual(first.pendingSteering.map(\.prepared.summaryText), ["only first"])
        XCTAssertEqual(first.items, firstItemsBefore)
        XCTAssertEqual(second.items, secondItemsBefore)
    }

    func testFailedSteeringEntryRemainsCompleteAndRetryable() async throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "bootstrap", 1)
        let model = steeringReadyModel()
        unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
        model.handleEventForTesting(try Self.event(type: "agent_start"))
        model.draft = "retain me"
        let attachment = ComposerAttachment(kind: .fileReference(FileReferenceAttachment(
            url: URL(fileURLWithPath: "/tmp/retain-me.txt"), displayName: "retain-me.txt", fileSize: 99
        )))
        model.addDraftAttachments([attachment])
        model.sendDraft()
        model.stopActiveTurn()

        // 2119: REQ-003.7.22
        try await Task.sleep(nanoseconds: 40_000_000)
        let retained = try XCTUnwrap(model.pendingSteering.first)
        XCTAssertEqual(retained.state, .failed)
        XCTAssertEqual(retained.prepared.summaryText, "retain me")
        XCTAssertEqual(retained.composerText, "retain me")
        XCTAssertEqual(retained.composerAttachments, [attachment])
        XCTAssertEqual(retained.prepared.displayAttachments, [attachment])

        model.retrySteering(retained.id)
        try await Task.sleep(nanoseconds: 20_000_000)
        let retainedAfterRetry = try XCTUnwrap(model.pendingSteering.first)
        XCTAssertEqual(retainedAfterRetry.id, retained.id)
        XCTAssertEqual(retainedAfterRetry.state, .failed)
        XCTAssertEqual(retainedAfterRetry.composerAttachments, [attachment])
    }

    func testSendingWhileSessionLoadsShowsUserMessageImmediately() throws {
        let model = PiConversationModel()
        model.currentModel = PiModelOption(provider: "test", id: "selected", name: "Selected")
        model.currentThinkingLevel = .medium
        model.draft = "hello while loading"

        model.sendDraft()

        XCTAssertEqual(model.draft, "")
        XCTAssertTrue(model.items.contains { item in
            if case .user(_, let payload) = item {
                return payload.text == "hello while loading"
            }
            return false
        })
        XCTAssertFalse(model.isRunning)
    }

    func testLoadingSessionSuppressesPreHydrationTurnOutput() throws {
        let model = PiConversationModel()
        model.isLoadingSession = true

        let startupDelta = try RPCEnvelope.testEnvelope([
            "type": .string("message_update"),
            "assistantMessageEvent": .object([
                "type": .string("text_delta"),
                "delta": .string("startup debug output that should not flash")
            ])
        ])

        model.handleEventForTesting(startupDelta)

        XCTAssertTrue(model.items.isEmpty)
        XCTAssertFalse(model.isRunning)
    }

    func testPostLoadTurnOutputStillRenders() throws {
        let model = PiConversationModel()
        model.isLoadingSession = false

        let delta = try RPCEnvelope.testEnvelope([
            "type": .string("message_update"),
            "assistantMessageEvent": .object([
                "type": .string("text_delta"),
                "delta": .string("visible response")
            ])
        ])

        model.handleEventForTesting(delta)

        XCTAssertTrue(model.items.contains { item in
            if case .assistantText(_, "visible response") = item { return true }
            return false
        })
    }

    func testStoppedTurnOutputCannotAppendAfterLaterPromptStarts() async throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "old stopped turn output", 1)
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE_DELAY_MS", "120", 1)
        defer {
            unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
            unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE_DELAY_MS")
        }
        let model = PiConversationModel()
        model.start(workingDirectory: nil, sessionPath: nil)
        model.draft = "first prompt to stop"
        model.sendDraft()
        XCTAssertTrue(model.isRunning)
        model.stopActiveTurn()
        XCTAssertFalse(model.isRunning)

        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "new prompt output", 1)
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE_DELAY_MS", "20", 1)
        model.draft = "new prompt after stop"
        model.sendDraft()

        // 2119: REQ-003.5.2
        try await Task.sleep(nanoseconds: 220_000_000)

        XCTAssertFalse(model.items.contains { item in
            if case .assistantText(_, let text) = item { return text.contains("old stopped turn output") }
            return false
        })
        XCTAssertTrue(model.items.contains { item in
            if case .assistantText(_, let text) = item { return text.contains("new prompt output") }
            return false
        })
        XCTAssertFalse(model.isRunning)
    }

    func testStopImmediatelyLeavesRunningStateAndSuppressesLateTurnOutput() async throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "later prompt response", 1)
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE_DELAY_MS", "1", 1)
        defer {
            unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
            unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE_DELAY_MS")
        }
        let model = PiConversationModel()
        model.currentModel = PiModelOption(provider: "test", id: "selected", name: "Selected")
        model.currentThinkingLevel = .medium
        model.start(workingDirectory: nil, sessionPath: nil)
        model.items.append(.assistantText(text: "existing assistant text"))
        model.isRunning = true

        let stopStartedAt = Date()
        model.stopActiveTurn()

        XCTAssertFalse(model.isRunning)
        XCTAssertLessThan(Date().timeIntervalSince(stopStartedAt), 1.0)
        XCTAssertTrue(model.items.contains { item in
            if case .notice(_, "Stopped.") = item { return true }
            return false
        })

        let lateDelta = try RPCEnvelope.testEnvelope([
            "type": .string("message_update"),
            "assistantMessageEvent": .object([
                "type": .string("text_delta"),
                "delta": .string("late output that should be ignored")
            ])
        ])
        let lateToolStart = try RPCEnvelope.testEnvelope([
            "type": .string("tool_execution_start"),
            "toolCallId": .string("late-tool"),
            "toolName": .string("shell"),
            "args": .object(["command": .string("echo should-not-append")])
        ])
        // 2119: REQ-003.5.2
        model.handleEventForTesting(lateDelta)
        model.handleEventForTesting(lateToolStart)

        XCTAssertFalse(model.items.contains { item in
            if case .assistantText(_, let text) = item {
                return text.contains("late output") || text.contains("existing assistant textlate")
            }
            if case .activity(let group) = item {
                return group.tools.contains { $0.callID == "late-tool" || $0.args.contains("should-not-append") }
            }
            return false
        })
        XCTAssertFalse(model.isRunning)
    }

    // 2119: REQ-003.5.2
    func testRealRPCProcessLateOutputIsSuppressedAfterStop() async throws {
        unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeStopRPC-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let script = sandbox.appendingPathComponent("fake-pi-rpc.sh")
        try """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"type":"prompt"'*)
              printf '%s\\n' '{"type":"agent_start"}'
              printf '{"id":%s,"type":"response","success":true,"data":{}}\\n' "$id"
              (
                sleep 0.20
                printf '%s\\n' '{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"late output from real rpc process"}}'
              ) &
              ;;
            *'"type":"abort"'*)
              sleep 0.45
              printf '{"id":%s,"type":"response","success":true,"data":{}}\\n' "$id"
              ;;
            *)
              printf '{"id":%s,"type":"response","success":true,"data":{}}\\n' "$id"
              ;;
          esac
        done
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let model = PiConversationModel(piCommand: PiCommand(executable: script.path, arguments: []))
        model.currentModel = PiModelOption(provider: "test", id: "selected", name: "Selected")
        model.currentThinkingLevel = .medium
        model.start(workingDirectory: sandbox.path, sessionPath: nil)

        model.draft = "start a turn through the real rpc process"
        model.sendDraft()
        try await waitUntil(timeout: 1) { model.isRunning }
        model.stopActiveTurn()

        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertFalse(model.items.contains { item in
            if case .assistantText(_, let text) = item {
                return text.contains("late output from real rpc process")
            }
            return false
        })
        XCTAssertFalse(model.isRunning)
    }

    private func steeringReadyModel() -> PiConversationModel {
        let model = PiConversationModel()
        model.currentModel = PiModelOption(provider: "test", id: "selected", name: "Selected")
        model.currentThinkingLevel = .medium
        model.start(workingDirectory: nil, sessionPath: nil)
        return model
    }

    private static func event(type: String) throws -> RPCEnvelope {
        try RPCEnvelope.testEnvelope(["type": .string(type)])
    }

    private static func userMessageStart(_ text: String) throws -> RPCEnvelope {
        try RPCEnvelope.testEnvelope([
            "type": .string("message_start"),
            "message": .object([
                "role": .string("user"),
                "content": .array([.object(["type": .string("text"), "text": .string(text)])])
            ])
        ])
    }
    // 2119: REQ-003.5.2
    func testRealRPCProcessLateStoppedOutputIsSuppressedAfterLaterTurnStarts() async throws {
        unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeStopThenRestartRPC-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let promptCountFile = sandbox.appendingPathComponent("prompt-count.txt")
        let commandLogFile = sandbox.appendingPathComponent("commands.log")
        let script = sandbox.appendingPathComponent("fake-pi-rpc.sh")
        try """
        #!/bin/sh
        count_file="$PI_NATIVE_TEST_PROMPT_COUNT_FILE"
        log_file="$PI_NATIVE_TEST_COMMAND_LOG_FILE"
        while IFS= read -r line; do
          printf '%s\n' "$line" >> "$log_file"
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"type":"prompt"'*)
              count=0
              [ -f "$count_file" ] && count=$(cat "$count_file")
              count=$((count + 1))
              printf '%s' "$count" > "$count_file"
              printf '%s\\n' '{"type":"agent_start"}'
              printf '{"id":%s,"type":"response","success":true,"data":{}}\\n' "$id"
              if [ "$count" -eq 1 ]; then
                (
                  sleep 0.35
                  printf '%s\\n' '{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"stale first-turn output after second start"}}'
                ) &
              else
                printf '%s\\n' '{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"fresh second-turn output"}}'
                printf '%s\\n' '{"type":"agent_end"}'
              fi
              ;;
            *'"type":"abort"'*)
              printf '{"id":%s,"type":"response","success":true,"data":{}}\\n' "$id"
              ;;
            *'"type":"get_state"'*)
              printf '{"id":%s,"type":"response","success":true,"data":{"model":{"provider":"test","id":"selected","name":"Selected"},"thinkingLevel":"medium"}}\\n' "$id"
              ;;
            *'"type":"get_available_models"'*)
              printf '{"id":%s,"type":"response","success":true,"data":{"models":[{"provider":"test","id":"selected","name":"Selected"}]}}\\n' "$id"
              ;;
            *'"type":"get_available_thinking_levels"'*)
              printf '{"id":%s,"type":"response","success":true,"data":{"levels":["low","medium","high"]}}\\n' "$id"
              ;;
            *)
              printf '{"id":%s,"type":"response","success":true,"data":{}}\\n' "$id"
              ;;
          esac
        done
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        setenv("PI_NATIVE_TEST_PROMPT_COUNT_FILE", promptCountFile.path, 1)
        setenv("PI_NATIVE_TEST_COMMAND_LOG_FILE", commandLogFile.path, 1)
        defer {
            unsetenv("PI_NATIVE_TEST_PROMPT_COUNT_FILE")
            unsetenv("PI_NATIVE_TEST_COMMAND_LOG_FILE")
        }

        let model = PiConversationModel(piCommand: PiCommand(executable: script.path, arguments: []))
        model.currentModel = PiModelOption(provider: "test", id: "selected", name: "Selected")
        model.currentThinkingLevel = .medium
        model.start(workingDirectory: sandbox.path, sessionPath: nil)

        model.draft = "first prompt"
        model.sendDraft()
        try await waitUntil(timeout: 1) {
            (try? String(contentsOf: promptCountFile, encoding: .utf8)) == "1"
        }
        XCTAssertTrue(model.isRunning)
        model.stopActiveTurn()

        model.draft = "second prompt"
        model.sendDraft()
        try await waitUntil(timeout: 3) {
            (try? String(contentsOf: promptCountFile, encoding: .utf8)) == "2"
        }
        try await waitUntil(timeout: 3) {
            model.items.contains { item in
                if case .assistantText(_, let text) = item {
                    return text.contains("fresh second-turn output")
                }
                return false
            }
        }

        let commandLog = (try? String(contentsOf: commandLogFile, encoding: .utf8)) ?? "<missing command log>"
        let transcript = String(describing: model.items)
        XCTAssertTrue(commandLog.contains("\"message\":\"second prompt\""), commandLog)
        XCTAssertTrue(transcript.contains("fresh second-turn output"), "Commands:\n\(commandLog)\nTranscript:\n\(transcript)")

        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertFalse(model.items.contains { item in
            if case .assistantText(_, let text) = item {
                return text.contains("stale first-turn output after second start")
            }
            return false
        })
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

private extension RPCEnvelope {
    static func testEnvelope(_ raw: [String: JSONValue]) throws -> RPCEnvelope {
        let data = try JSONEncoder().encode(JSONValue.object(raw))
        return try JSONDecoder().decode(RPCEnvelope.self, from: data)
    }
}
