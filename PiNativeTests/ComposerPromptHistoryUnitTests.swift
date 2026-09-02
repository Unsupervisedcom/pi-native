import AppKit
import SwiftUI
import XCTest
@testable import PiNative

@MainActor
final class ComposerPromptHistoryUnitTests: XCTestCase {
    private let firstID = UUID()
    private let secondID = UUID()

    // 2119: REQ-009.1.1
    // 2119: REQ-009.1.2
    // 2119: REQ-009.1.3
    // 2119: REQ-009.1.4
    // 2119: REQ-009.1.5
    func testHistoryTraversesNewestToOldestAndBackToEmpty() throws {
        let entries = makeEntries()
        var navigator = ComposerPromptHistoryNavigator()
        var draft = ""
        var attachments: [ComposerAttachment] = []

        XCTAssertTrue(navigator.navigateOlder(in: entries, draft: &draft, attachments: &attachments))
        XCTAssertEqual(draft, "second prompt")
        XCTAssertTrue(navigator.navigateOlder(in: entries, draft: &draft, attachments: &attachments))
        XCTAssertEqual(draft, "first prompt")
        XCTAssertEqual(attachments.map(\.displayName), ["first.txt"])
        XCTAssertTrue(navigator.navigateOlder(in: entries, draft: &draft, attachments: &attachments))
        XCTAssertEqual(draft, "first prompt")
        XCTAssertEqual(attachments.map(\.displayName), ["first.txt"])
        XCTAssertTrue(navigator.isBrowsing)

        XCTAssertTrue(navigator.navigateNewer(in: entries, draft: &draft, attachments: &attachments))
        XCTAssertEqual(draft, "second prompt")
        XCTAssertTrue(navigator.navigateNewer(in: entries, draft: &draft, attachments: &attachments))
        XCTAssertEqual(draft, "")
        XCTAssertTrue(attachments.isEmpty)
        XCTAssertFalse(navigator.isBrowsing)
        XCTAssertFalse(navigator.navigateNewer(in: entries, draft: &draft, attachments: &attachments))
    }

    // 2119: REQ-009.1.6
    // 2119: REQ-009.1.7

    // 2119: REQ-009.1.6
    // 2119: REQ-009.1.7
    func testRecallReturnsExactTextAndOrderedAttachments() throws {
        let attachments = [makeFileAttachment("one.txt"), makeFileAttachment("two.txt")]
        let payload = UserMessagePayload(text: "  exact\tmultiline\r\ntext 👋 世界  \n\n", attachments: attachments)
        let model = PiConversationModel()
        model.items = [.user(id: firstID, payload)]
        var navigator = ComposerPromptHistoryNavigator()
        var draft = ""
        var recalledAttachments: [ComposerAttachment] = []

        XCTAssertTrue(navigator.navigateOlder(
            in: model.promptHistory,
            draft: &draft,
            attachments: &recalledAttachments
        ))

        XCTAssertEqual(draft, payload.text)
        XCTAssertEqual(recalledAttachments, attachments)
    }

    // 2119: REQ-009.2.1

    // 2119: REQ-009.2.1
    func testNonemptyTextOrAttachmentsCannotStartHistoryBrowsing() {
        let entries = makeEntries()
        var textDraftNavigator = ComposerPromptHistoryNavigator()
        var attachmentDraftNavigator = ComposerPromptHistoryNavigator()
        var textDraft = "do not replace"
        var noAttachments: [ComposerAttachment] = []
        var emptyDraft = ""
        var attachmentDraft = [makeFileAttachment("draft.txt")]

        XCTAssertFalse(textDraftNavigator.navigateOlder(in: entries, draft: &textDraft, attachments: &noAttachments))
        XCTAssertEqual(textDraft, "do not replace")
        XCTAssertFalse(attachmentDraftNavigator.navigateOlder(in: entries, draft: &emptyDraft, attachments: &attachmentDraft))
        XCTAssertEqual(attachmentDraft.map(\.displayName), ["draft.txt"])
        XCTAssertFalse(textDraftNavigator.isBrowsing)
        XCTAssertFalse(attachmentDraftNavigator.isBrowsing)
    }

    // 2119: REQ-009.2.2
    // 2119: REQ-009.3.1
    // 2119: REQ-009.3.3

    // 2119: REQ-009.2.2
    // 2119: REQ-009.3.1
    // 2119: REQ-009.3.3
    func testChatChangeEndsBrowsingAndUsesOnlyDestinationChatHistory() throws {
        let firstChat = PiConversationModel()
        firstChat.items = [.user(id: firstID, UserMessagePayload(text: "chat A prompt"))]
        let secondChat = PiConversationModel()
        secondChat.items = [.user(id: secondID, UserMessagePayload(text: "chat B prompt"))]
        secondChat.draft = "chat B draft"
        var navigator = ComposerPromptHistoryNavigator()
        var draft = ""
        var attachments: [ComposerAttachment] = []

        XCTAssertTrue(navigator.navigateOlder(in: firstChat.promptHistory, draft: &draft, attachments: &attachments))
        XCTAssertEqual(draft, "chat A prompt")
        navigator.chatDidChange()
        XCTAssertFalse(navigator.isBrowsing)
        draft = secondChat.draft
        attachments = secondChat.draftAttachments
        XCTAssertEqual(draft, "chat B draft")
        XCTAssertFalse(draft.contains("chat A prompt"))
        draft = ""
        XCTAssertTrue(navigator.navigateOlder(in: secondChat.promptHistory, draft: &draft, attachments: &attachments))
        XCTAssertEqual(draft, "chat B prompt")
        XCTAssertFalse(secondChat.promptHistory.contains { $0.payload.text == "chat A prompt" })
    }

    // 2119: REQ-009.2.4
    // 2119: REQ-009.2.8

    // 2119: REQ-009.2.4
    // 2119: REQ-009.2.8
    func testUserEditEndsBrowsingWithoutMutatingTranscriptSource() throws {
        let originalAttachment = makeFileAttachment("original.txt")
        let original = UserMessagePayload(text: "original prompt", attachments: [originalAttachment])
        let model = PiConversationModel()
        model.items = [.user(id: firstID, original)]
        let entries = model.promptHistory
        var navigator = ComposerPromptHistoryNavigator()
        var draft = ""
        var attachments: [ComposerAttachment] = []
        XCTAssertTrue(navigator.navigateOlder(in: entries, draft: &draft, attachments: &attachments))

        // Caret or selection movement does not call the text-change path.
        XCTAssertTrue(navigator.isBrowsing)
        draft = "edited prompt"
        navigator.userDidEdit()

        XCTAssertFalse(navigator.isBrowsing)
        guard case .user(_, let transcriptPayload) = model.items[0] else {
            return XCTFail("Expected transcript user message")
        }
        XCTAssertEqual(transcriptPayload.text, "original prompt")
        XCTAssertEqual(transcriptPayload.attachments, [originalAttachment])
        XCTAssertFalse(navigator.navigateOlder(in: entries, draft: &draft, attachments: &attachments))

        draft = ""
        attachments = []
        XCTAssertTrue(navigator.navigateOlder(in: entries, draft: &draft, attachments: &attachments))
        attachments.removeAll()
        navigator.userDidEdit()
        XCTAssertFalse(navigator.isBrowsing)
        guard case .user(_, let attachmentEditSource) = model.items[0] else {
            return XCTFail("Expected transcript user message")
        }
        XCTAssertEqual(attachmentEditSource.attachments, [originalAttachment])

        draft = ""
        attachments = []
        XCTAssertTrue(navigator.navigateOlder(in: entries, draft: &draft, attachments: &attachments))
        attachments.append(makeImageAttachment("added.png"))
        navigator.userDidEdit()
        XCTAssertFalse(navigator.isBrowsing)
        guard case .user(_, let attachmentAdditionSource) = model.items[0] else {
            return XCTFail("Expected transcript user message")
        }
        XCTAssertEqual(attachmentAdditionSource.attachments, [originalAttachment])
    }

    // 2119: REQ-009.2.7

    // 2119: REQ-009.2.7
    func testEmptyChatHistoryLeavesNavigatorInactive() {
        let model = PiConversationModel()
        var navigator = ComposerPromptHistoryNavigator()
        var draft = ""
        var attachments: [ComposerAttachment] = []

        XCTAssertFalse(navigator.navigateOlder(in: model.promptHistory, draft: &draft, attachments: &attachments))
        XCTAssertEqual(draft, "")
        XCTAssertTrue(attachments.isEmpty)
        XCTAssertFalse(navigator.isBrowsing)
    }

    // 2119: REQ-009.2.5
    // 2119: REQ-009.2.6

    // 2119: REQ-009.2.5
    // 2119: REQ-009.2.6
    func testSubmittingRecalledPromptAppendsNewTurnWithoutChangingOriginal() throws {
        let model = PiConversationModel()
        let originalID = UUID()
        let originalAttachment = makeFileAttachment("original.txt")
        let originalPayload = UserMessagePayload(text: "recalled prompt", attachments: [originalAttachment])
        model.items = [.user(id: originalID, originalPayload)]
        model.currentModel = PiModelOption(provider: "test", id: "selected", name: "Selected")
        model.currentThinkingLevel = .medium
        var navigator = ComposerPromptHistoryNavigator()
        XCTAssertTrue(navigator.navigateOlder(
            in: model.promptHistory,
            draft: &model.draft,
            attachments: &model.draftAttachments
        ))

        model.sendDraft()

        let userTurns = model.items.compactMap { item -> (UUID, UserMessagePayload)? in
            guard case .user(let id, let payload) = item else { return nil }
            return (id, payload)
        }
        XCTAssertEqual(userTurns.count, 2)
        XCTAssertNotEqual(userTurns[0].0, userTurns[1].0)
        XCTAssertEqual(userTurns[1].1.text, originalPayload.text)
        XCTAssertEqual(userTurns[1].1.attachments, originalPayload.attachments)
        XCTAssertEqual(model.items.first, Optional(.user(id: originalID, originalPayload)))
    }

    // 2119: REQ-009.2.5
    // 2119: REQ-009.2.6

    // 2119: REQ-009.1.1
    // 2119: REQ-009.1.2
    // 2119: REQ-009.1.3
    // 2119: REQ-009.1.4
    // 2119: REQ-009.1.5
    // 2119: REQ-009.2.1
    func testAppKitArrowEventsDriveHistoryAndRespectNonemptyComposer() throws {
        let entries = makeEntries()
        var navigator = ComposerPromptHistoryNavigator()
        var draft = ""
        var attachments: [ComposerAttachment] = []
        let textView = PasteInterceptingTextView()
        textView.onHistoryOlder = {
            navigator.navigateOlder(in: entries, draft: &draft, attachments: &attachments)
        }
        textView.onHistoryNewer = {
            navigator.navigateNewer(in: entries, draft: &draft, attachments: &attachments)
        }

        textView.keyDown(with: try keyEvent(keyCode: 126, characters: "\u{F700}"))
        XCTAssertEqual(draft, "second prompt")
        textView.keyDown(with: try keyEvent(keyCode: 126, characters: "\u{F700}"))
        XCTAssertEqual(draft, "first prompt")
        XCTAssertEqual(attachments.map(\.displayName), ["first.txt"])
        textView.keyDown(with: try keyEvent(keyCode: 126, characters: "\u{F700}"))
        XCTAssertEqual(draft, "first prompt")
        XCTAssertEqual(attachments.map(\.displayName), ["first.txt"])
        textView.keyDown(with: try keyEvent(keyCode: 125, characters: "\u{F701}"))
        XCTAssertEqual(draft, "second prompt")
        textView.keyDown(with: try keyEvent(keyCode: 125, characters: "\u{F701}"))
        XCTAssertEqual(draft, "")

        draft = "keep this draft"
        textView.string = draft
        textView.keyDown(with: try keyEvent(keyCode: 126, characters: "\u{F700}"))
        XCTAssertEqual(draft, "keep this draft")
        XCTAssertFalse(navigator.isBrowsing)
    }

    // 2119: REQ-009.2.4
    // 2119: REQ-009.2.8

    // 2119: REQ-009.2.4
    // 2119: REQ-009.2.8
    func testSelectionMovementKeepsBrowsingButActualTextEditEndsIt() throws {
        let entries = makeEntries()
        var navigator = ComposerPromptHistoryNavigator()
        var draft = ""
        var attachments: [ComposerAttachment] = []
        XCTAssertTrue(navigator.navigateOlder(in: entries, draft: &draft, attachments: &attachments))

        var boundText = draft
        let coordinator = PasteAwareTextView.Coordinator(text: Binding(
            get: { boundText },
            set: { boundText = $0 }
        ))
        coordinator.onUserEdit = { navigator.userDidEdit() }
        let textView = PasteInterceptingTextView()
        textView.string = draft
        textView.delegate = coordinator
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        XCTAssertTrue(navigator.isBrowsing)
        textView.setSelectedRange(NSRange(location: 0, length: 2))
        XCTAssertTrue(navigator.isBrowsing)

        textView.string = "user edit"
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(boundText, "user edit")
        XCTAssertFalse(navigator.isBrowsing)
    }

    // 2119: REQ-009.1.1
    // 2119: REQ-009.1.2
    // 2119: REQ-009.1.3
    // 2119: REQ-009.1.4
    // 2119: REQ-009.1.5
    // 2119: REQ-009.1.6
    // 2119: REQ-009.1.7
    // 2119: REQ-009.2.1
    // 2119: REQ-009.2.2
    // 2119: REQ-009.2.4
    // 2119: REQ-009.2.7
    // 2119: REQ-009.2.8
    // 2119: REQ-009.3.1
    // 2119: REQ-009.3.2
    // 2119: REQ-009.3.3

    private func makeEntries() -> [ComposerPromptHistoryEntry] {
        let model = PiConversationModel()
        model.items = [
            .user(id: firstID, UserMessagePayload(
                text: "first prompt",
                attachments: [makeFileAttachment("first.txt")]
            )),
            .assistantText(text: "assistant response excluded from prompt history"),
            .user(id: secondID, UserMessagePayload(text: "second prompt"))
        ]
        return model.promptHistory
    }

    private func makeFileAttachment(_ name: String) -> ComposerAttachment {
        ComposerAttachment(kind: .fileReference(FileReferenceAttachment(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            displayName: name,
            fileSize: nil
        )))
    }

    private func makeImageAttachment(_ name: String) -> ComposerAttachment {
        ComposerAttachment(kind: .image(ImageAttachment(
            data: Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02]),
            mimeType: "image/png",
            displayName: name,
            sourceURL: nil,
            pixelWidth: 7,
            pixelHeight: 11
        )))
    }

    private func keyEvent(keyCode: UInt16, characters: String) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
