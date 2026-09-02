import XCTest
@testable import PiNative

@MainActor
final class ConversationRestorationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "restoration mock", 1)
    }

    override func tearDown() {
        unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE")
        super.tearDown()
    }

    // 2119: REQ-003.1.3
    func testSameSessionLifecycleResyncWithUnavailableCacheKeepsDisplayedTranscript() throws {
        let model = PiConversationModel()
        let cached: [TranscriptItem] = [
            .user(UserMessagePayload(text: "already visible user text")),
            .assistantText(text: "already visible assistant text")
        ]
        let sessionPath = "/tmp/pinative-existing-session.jsonl"

        model.start(workingDirectory: NSTemporaryDirectory(), sessionPath: sessionPath, cachedItems: cached)
        XCTAssertEqual(model.items, cached)

        model.start(workingDirectory: NSTemporaryDirectory(), sessionPath: sessionPath, cachedItems: [])
        model.start(workingDirectory: NSTemporaryDirectory(), sessionPath: sessionPath, cachedItems: [])

        XCTAssertEqual(model.items, cached)

        let updatedCached: [TranscriptItem] = [
            .user(UserMessagePayload(text: "updated first visible user text")),
            .assistantText(text: "updated middle assistant text"),
            .user(UserMessagePayload(text: "updated latest user text"))
        ]
        model.start(workingDirectory: NSTemporaryDirectory(), sessionPath: sessionPath, cachedItems: updatedCached)

        XCTAssertEqual(model.items, updatedCached)
    }
}
