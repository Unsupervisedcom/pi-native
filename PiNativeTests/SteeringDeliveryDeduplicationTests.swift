import XCTest
@testable import PiNative

@MainActor
final class SteeringDeliveryDeduplicationTests: XCTestCase {
    func testMatchingSteeringDeliveryInOneChatCannotMutateAnotherChat() throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "later response", 1)
        defer { unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE") }
        let first = readyModel()
        let second = readyModel()
        first.handleEventForTesting(try envelope(["type": .string("agent_start")]))
        second.handleEventForTesting(try envelope(["type": .string("agent_start")]))
        first.draft = "identical steering text"
        second.draft = "identical steering text"
        first.sendDraft()
        second.sendDraft()
        let secondItemsBeforeDelivery = second.items

        // 2119: REQ-003.7.21
        first.handleEventForTesting(try userDelivery("identical steering text"))

        XCTAssertTrue(first.pendingSteering.isEmpty)
        XCTAssertEqual(second.pendingSteering.map(\.prepared.summaryText), ["identical steering text"])
        XCTAssertEqual(second.items, secondItemsBeforeDelivery)
    }

    func testLateAcknowledgementsCannotCreateAnyDuplicateSubmissionOrDelivery() async throws {
        let model = PiConversationModel()
        model.mockResponseOverrideForTesting = "bootstrap"
        model.currentModel = PiModelOption(provider: "test", id: "selected", name: "Selected")
        model.currentThinkingLevel = .medium
        model.start(workingDirectory: nil, sessionPath: nil)
        model.mockResponseOverrideForTesting = nil
        model.handleEventForTesting(try envelope(["type": .string("agent_start")]))
        var submissions: [String] = []
        model.onSteeringRPCForTesting = { _ in submissions.append("steer") }
        model.onPromptRPCForTesting = { _ in submissions.append("prompt") }
        model.draft = "ack race without duplicates"
        model.sendDraft()
        model.mockResponseOverrideForTesting = "replacement response"

        // 2119: REQ-003.7.19
        model.stopActiveTurn()
        model.handleEventForTesting(try userDelivery("server-expanded late acknowledgement before replay"))
        try await Task.sleep(nanoseconds: 60_000_000)
        model.handleEventForTesting(try userDelivery("different server-expanded late acknowledgement after replay"))

        XCTAssertEqual(submissions, ["prompt"])
        XCTAssertEqual(model.items.filter { item in
            if case .user = item { return true }
            return false
        }.count, 1)
        XCTAssertTrue(model.pendingSteering.isEmpty)
    }

    func testAcceptedSteeringReplayStartsOnlyAfterStopCompletes() async throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "later response", 1)
        defer { unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE") }
        let model = PiConversationModel()
        model.currentModel = PiModelOption(provider: "test", id: "selected", name: "Selected")
        model.currentThinkingLevel = .medium
        model.start(workingDirectory: nil, sessionPath: nil)
        model.handleEventForTesting(try envelope(["type": .string("agent_start")]))
        model.draft = "replay after stop"
        model.sendDraft()
        XCTAssertEqual(model.pendingSteering.count, 1)

        var lifecycle: [String] = []
        model.onStopCompletionForTesting = {
            lifecycle.append("stop-completed")
        }
        model.onPromptRPCForTesting = { _ in
            lifecycle.append("replay-submitted")
        }

        // 2119: REQ-003.7.16
        model.stopActiveTurn()
        try await Task.sleep(nanoseconds: 60_000_000)

        XCTAssertEqual(lifecycle, ["stop-completed", "replay-submitted"])
        XCTAssertTrue(model.items.contains { item in
            if case .user(_, let payload) = item {
                return payload.text == "replay after stop"
            }
            return false
        })
    }

    func testRepeatedDeliveryEventCreatesOneHistoryEntryForOneAcceptedSteeringMessage() throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "later response", 1)
        defer { unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE") }
        let model = PiConversationModel()
        model.currentModel = PiModelOption(provider: "test", id: "selected", name: "Selected")
        model.currentThinkingLevel = .medium
        model.start(workingDirectory: nil, sessionPath: nil)
        model.handleEventForTesting(try envelope(["type": .string("agent_start")]))
        model.draft = "deliver exactly once"
        model.sendDraft()
        XCTAssertEqual(model.pendingSteering.count, 1)

        let delivery = try envelope([
            "type": .string("message_start"),
            "message": .object([
                "role": .string("user"),
                "content": .array([.object([
                    "type": .string("text"),
                    "text": .string("deliver exactly once")
                ])])
            ])
        ])

        // 2119: REQ-003.7.11
        model.handleEventForTesting(delivery)
        model.handleEventForTesting(delivery)

        let deliveredCount = model.items.filter { item in
            if case .user(_, let payload) = item {
                return payload.text == "deliver exactly once"
            }
            return false
        }.count
        XCTAssertEqual(deliveredCount, 1)
        XCTAssertTrue(model.pendingSteering.isEmpty)
    }

    private func envelope(_ raw: [String: JSONValue]) throws -> RPCEnvelope {
        let data = try JSONEncoder().encode(JSONValue.object(raw))
        return try JSONDecoder().decode(RPCEnvelope.self, from: data)
    }

    private func readyModel() -> PiConversationModel {
        let model = PiConversationModel()
        model.currentModel = PiModelOption(provider: "test", id: "selected", name: "Selected")
        model.currentThinkingLevel = .medium
        model.start(workingDirectory: nil, sessionPath: nil)
        return model
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
}
