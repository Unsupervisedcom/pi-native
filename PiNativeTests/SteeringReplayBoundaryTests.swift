import XCTest
@testable import PiNative

@MainActor
final class SteeringReplayBoundaryTests: XCTestCase {
    func testStopDoesNotReplayAcceptedSteeringThatWasAlreadyDelivered() async throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "later response", 1)
        defer { unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE") }
        let model = PiConversationModel()
        model.currentModel = PiModelOption(provider: "test", id: "selected", name: "Selected")
        model.currentThinkingLevel = .medium
        model.start(workingDirectory: nil, sessionPath: nil)
        model.handleEventForTesting(try event(type: "agent_start"))
        model.draft = "already delivered steering"
        model.sendDraft()
        XCTAssertEqual(model.pendingSteering.count, 1)
        model.handleEventForTesting(try userDelivery("already delivered steering"))
        XCTAssertTrue(model.pendingSteering.isEmpty)
        var replayedPrompts: [String] = []
        model.onPromptRPCForTesting = { replayedPrompts.append($0) }

        // 2119: REQ-003.7.16
        model.stopActiveTurn()
        try await Task.sleep(nanoseconds: 60_000_000)

        XCTAssertTrue(replayedPrompts.isEmpty)
        XCTAssertEqual(model.items.filter { item in
            if case .user(_, let payload) = item {
                return payload.text == "already delivered steering"
            }
            return false
        }.count, 1)
    }

    func testStoppingPendingPromptWithoutClientDoesNotReportSteeringFailure() async throws {
        setenv("PI_NATIVE_TEST_RPC_STALL", "1", 1)
        defer { unsetenv("PI_NATIVE_TEST_RPC_STALL") }
        let model = PiConversationModel()
        model.currentModel = PiModelOption(provider: "test", id: "selected", name: "Selected")
        model.currentThinkingLevel = .medium
        model.start(workingDirectory: nil, sessionPath: nil)
        model.draft = "pending initial prompt"
        model.sendDraft()
        XCTAssertTrue(model.hasPendingPrompt)
        XCTAssertTrue(model.pendingSteering.isEmpty)
        var stopCompleted = false
        model.onStopCompletionForTesting = { stopCompleted = true }

        model.stopActiveTurn()
        try await waitForSteeringCondition { stopCompleted }

        XCTAssertFalse(model.items.contains { item in
            guard case .notice(_, let text) = item else { return false }
            return text.contains("resume steering")
        })
    }

    func testRealProcessReplayIsRunningBeforePromptSubmission() async throws {
        unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
        let fixture = try ReplayRPCFixture()
        defer { fixture.cleanup() }
        let model = fixture.makeModel()
        model.start(workingDirectory: fixture.directory.path, sessionPath: nil)
        model.draft = "original real-process turn"
        model.sendDraft()
        try await waitForSteeringCondition { model.isRunning }

        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "accept steering synchronously", 1)
        model.draft = "replay through real process"
        model.sendDraft()
        unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
        XCTAssertEqual(model.pendingSteering.first?.state, .accepted)

        var wasRunningWhenReplaySubmitted: Bool?
        model.onPromptRPCForTesting = { _ in
            wasRunningWhenReplaySubmitted = model.isRunning
        }

        // 2119: REQ-003.7.16
        model.stopActiveTurn()
        try await waitForSteeringCondition { wasRunningWhenReplaySubmitted != nil }

        XCTAssertEqual(wasRunningWhenReplaySubmitted, true)
    }

    func testReplacementProcessSpawnFailureMakesReplayingSteeringRetryable() async throws {
        unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
        let fixture = try ReplayRPCFixture()
        defer { fixture.cleanup() }
        let model = fixture.makeModel()
        model.start(workingDirectory: fixture.directory.path, sessionPath: nil)
        model.draft = "original real-process turn"
        model.sendDraft()
        try await waitForSteeringCondition { model.isRunning }

        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "accept steering synchronously", 1)
        model.draft = "retain after spawn failure"
        model.sendDraft()
        unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
        XCTAssertEqual(model.pendingSteering.first?.state, .accepted)
        try FileManager.default.removeItem(at: fixture.executable)

        // 2119: REQ-003.7.22
        model.stopActiveTurn()
        try await waitForSteeringCondition {
            model.pendingSteering.first?.state == .failed && model.isCatastrophicRPCFailure
        }

        XCTAssertEqual(model.pendingSteering.map(\.prepared.summaryText), ["retain after spawn failure"])
        XCTAssertTrue(model.sessionLoadNotice?.contains("Failed to start pi") == true)
    }

    func testReplacementSessionFailureMakesReplayingSteeringRetryable() async throws {
        unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
        let fixture = try ReplayRPCFixture()
        defer { fixture.cleanup() }
        let model = fixture.makeModel()
        model.start(workingDirectory: fixture.directory.path, sessionPath: nil)
        model.draft = "original real-process turn"
        model.sendDraft()
        try await waitForSteeringCondition { model.isRunning }

        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "accept steering synchronously", 1)
        model.draft = "retain after restart failure"
        model.sendDraft()
        unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
        XCTAssertEqual(model.pendingSteering.first?.state, .accepted)
        try Data().write(to: fixture.failReplacementMarker)

        // 2119: REQ-003.7.22
        model.stopActiveTurn()
        try await waitForSteeringCondition {
            model.pendingSteering.first?.state == .failed && model.isCatastrophicRPCFailure
        }

        XCTAssertEqual(model.pendingSteering.map(\.prepared.summaryText), ["retain after restart failure"])
        XCTAssertTrue(model.sessionLoadNotice?.contains("Failed to load session") == true)
    }

    private func event(type: String) throws -> RPCEnvelope {
        try envelope(["type": .string(type)])
    }

    private func userDelivery(_ text: String) throws -> RPCEnvelope {
        try envelope([
            "type": .string("message_start"),
            "message": .object([
                "role": .string("user"),
                "content": .array([.object(["type": .string("text"), "text": .string(text)])])
            ])
        ])
    }

    private func envelope(_ raw: [String: JSONValue]) throws -> RPCEnvelope {
        let data = try JSONEncoder().encode(JSONValue.object(raw))
        return try JSONDecoder().decode(RPCEnvelope.self, from: data)
    }
}

private struct ReplayRPCFixture {
    let directory: URL
    let executable: URL
    let launchCountFile: URL
    let failReplacementMarker: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiNativeSteeringReplay-\(UUID().uuidString)", isDirectory: true)
        executable = directory.appendingPathComponent("fake-pi-rpc.sh")
        launchCountFile = directory.appendingPathComponent("launch-count.txt")
        failReplacementMarker = directory.appendingPathComponent("fail-replacements")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.script(launchCountFile: launchCountFile, failReplacementMarker: failReplacementMarker)
            .write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    @MainActor
    func makeModel() -> PiConversationModel {
        let model = PiConversationModel(piCommand: PiCommand(executable: executable.path, arguments: []))
        model.currentModel = PiModelOption(provider: "test", id: "selected", name: "Selected")
        model.currentThinkingLevel = .medium
        return model
    }

    func cleanup() {
        unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
        try? FileManager.default.removeItem(at: directory)
    }

    private static func script(launchCountFile: URL, failReplacementMarker: URL) -> String {
        """
        #!/bin/sh
        count_file='\(launchCountFile.path)'
        fail_marker='\(failReplacementMarker.path)'
        launch_count=0
        [ -f "$count_file" ] && launch_count=$(cat "$count_file")
        launch_count=$((launch_count + 1))
        printf '%s' "$launch_count" > "$count_file"
        if [ "$launch_count" -gt 1 ] && [ -f "$fail_marker" ]; then
          rm -f "$0"
          exit 17
        fi
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"type":"prompt"'*)
              printf '%s\n' '{"type":"agent_start"}'
              printf '{"id":%s,"type":"response","success":true,"data":{}}\n' "$id"
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

@MainActor
private func waitForSteeringCondition(
    timeout: TimeInterval = 3,
    condition: @escaping @MainActor () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail("Timed out waiting for steering condition")
}
