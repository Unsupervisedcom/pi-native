import XCTest
@testable import PiNative

@MainActor
final class StopButtonTests: XCTestCase {
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
