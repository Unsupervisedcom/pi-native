import AppKit
import SwiftUI
import XCTest
@testable import PiNative

@MainActor
final class ComposerPromptHistoryMountedTests: XCTestCase {
    private let firstID = UUID()
    private let secondID = UUID()

    // 2119: REQ-009.2.5
    // 2119: REQ-009.2.6
    func testMountedConversationComposerRecallsAndSubmitsNewTurn() throws {
        let defaultsName = "ComposerPromptHistoryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let selectedModel = PiModelOption(provider: "test", id: "selected", name: "Selected")
        let settings = ModelSettingsModel(
            storage: UserDefaultsModelFavoritesStorage(defaults: defaults),
            favoritesKey: "favorites",
            configuredDefaultModel: selectedModel
        )
        let conversation = PiConversationModel(modelSettings: settings)
        let originalID = UUID()
        let originalAttachment = makeFileAttachment("mounted-submit.txt")
        let originalPayload = UserMessagePayload(text: "mounted recalled prompt", attachments: [originalAttachment])
        conversation.items = [.user(id: originalID, originalPayload)]
        conversation.currentModel = selectedModel
        conversation.currentThinkingLevel = .medium
        let hostingView = NSHostingView(rootView: PiConversationView(
            model: conversation,
            modelSettings: settings,
            onSelectFavorites: {}
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        let window = testWindow(containing: hostingView)
        defer { tearDown(window: window) }
        hostingView.layoutSubtreeIfNeeded()
        pumpMainRunLoop()
        let textView = try XCTUnwrap(descendant(of: PasteInterceptingTextView.self, in: hostingView))
        XCTAssertTrue(window.makeFirstResponder(textView))

        textView.keyDown(with: try keyEvent(keyCode: 126, characters: "\u{F700}"))
        pumpMainRunLoop()
        XCTAssertEqual(conversation.draft, originalPayload.text)
        XCTAssertEqual(conversation.draftAttachments, originalPayload.attachments)
        textView.keyDown(with: try keyEvent(keyCode: 36, characters: "\r"))

        let userTurns = conversation.items.compactMap { item -> (UUID, UserMessagePayload)? in
            guard case .user(let id, let payload) = item else { return nil }
            return (id, payload)
        }
        XCTAssertEqual(userTurns.count, 2)
        XCTAssertNotEqual(userTurns[0].0, userTurns[1].0)
        XCTAssertEqual(userTurns[1].1, originalPayload)
        XCTAssertEqual(conversation.items.first, Optional(.user(id: originalID, originalPayload)))
    }

    // 2119: REQ-009.2.2
    // 2119: REQ-009.2.5
    // 2119: REQ-009.2.6
    // 2119: REQ-009.2.7
    // 2119: REQ-009.3.1
    // 2119: REQ-009.3.2
    // 2119: REQ-009.3.3

    // 2119: REQ-009.2.2
    // 2119: REQ-009.2.5
    // 2119: REQ-009.2.6
    // 2119: REQ-009.2.7
    // 2119: REQ-009.3.1
    // 2119: REQ-009.3.2
    // 2119: REQ-009.3.3
    func testMountedConversationSwitchUsesFocusedModelHistoryAndComposer() throws {
        let defaultsName = "ComposerPromptHistorySwitchTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let selectedModel = PiModelOption(provider: "test", id: "selected", name: "Selected")
        let settings = ModelSettingsModel(
            storage: UserDefaultsModelFavoritesStorage(defaults: defaults),
            favoritesKey: "favorites",
            configuredDefaultModel: selectedModel
        )
        let chatAAttachment = makeFileAttachment("focused-chat-a.txt")
        let chatA = PiConversationModel(modelSettings: settings)
        chatA.items = [.user(UserMessagePayload(text: "focused chat A prompt", attachments: [chatAAttachment]))]
        let chatBAttachment = makeFileAttachment("focused-chat-b.txt")
        let chatB = PiConversationModel(modelSettings: settings)
        let chatBOriginalID = UUID()
        let chatBOriginalPayload = UserMessagePayload(text: "focused chat B prompt", attachments: [chatBAttachment])
        chatB.items = [
            .user(UserMessagePayload(text: "older focused chat B prompt")),
            .assistantText(text: "chat B assistant response"),
            .notice("chat B notice excluded from prompt history"),
            .activity(ActivityGroup(
                id: UUID(),
                tools: [],
                isRunning: false,
                startedAt: Date(timeIntervalSince1970: 1),
                finishedAt: Date(timeIntervalSince1970: 2)
            )),
            .user(id: chatBOriginalID, chatBOriginalPayload)
        ]
        chatB.currentModel = selectedModel
        chatB.currentThinkingLevel = .medium
        let hostingView = NSHostingView(rootView: PiConversationView(
            model: chatA,
            modelSettings: settings,
            onSelectFavorites: {}
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        let window = testWindow(containing: hostingView)
        defer { tearDown(window: window) }
        hostingView.layoutSubtreeIfNeeded()
        pumpMainRunLoop()
        var textView = try XCTUnwrap(descendant(of: PasteInterceptingTextView.self, in: hostingView))
        XCTAssertTrue(window.makeFirstResponder(textView))
        textView.keyDown(with: try keyEvent(keyCode: 126, characters: "\u{F700}"))
        pumpMainRunLoop()
        XCTAssertEqual(chatA.draft, "focused chat A prompt")
        XCTAssertEqual(chatA.draftAttachments, [chatAAttachment])

        hostingView.rootView = PiConversationView(
            model: chatB,
            modelSettings: settings,
            onSelectFavorites: {}
        )
        hostingView.layoutSubtreeIfNeeded()
        pumpMainRunLoop()
        textView = try XCTUnwrap(descendant(of: PasteInterceptingTextView.self, in: hostingView))
        XCTAssertTrue(window.makeFirstResponder(textView))
        XCTAssertEqual(textView.string, chatB.draft)
        XCTAssertFalse(textView.string.contains("chat A"))
        XCTAssertTrue(chatB.draftAttachments.isEmpty)
        textView.keyDown(with: try keyEvent(keyCode: 126, characters: "\u{F700}"))
        pumpMainRunLoop()
        XCTAssertEqual(chatB.draft, "focused chat B prompt")
        XCTAssertEqual(chatB.draftAttachments, [chatBAttachment])
        XCTAssertFalse(chatB.promptHistory.contains { $0.payload.text.contains("chat A") })
        textView.keyDown(with: try keyEvent(keyCode: 126, characters: "\u{F700}"))
        pumpMainRunLoop()
        XCTAssertEqual(chatB.draft, "older focused chat B prompt")
        XCTAssertTrue(chatB.draftAttachments.isEmpty)
        textView.keyDown(with: try keyEvent(keyCode: 125, characters: "\u{F701}"))
        pumpMainRunLoop()
        XCTAssertEqual(chatB.draft, "focused chat B prompt")
        XCTAssertEqual(chatB.draftAttachments, [chatBAttachment])
        let chatAItemsBeforeSubmit = chatA.items
        textView.keyDown(with: try keyEvent(keyCode: 36, characters: "\r"))
        let chatBUserTurns = chatB.items.compactMap { item -> (UUID, UserMessagePayload)? in
            guard case .user(let id, let payload) = item else { return nil }
            return (id, payload)
        }
        XCTAssertEqual(chatBUserTurns.count, 3)
        XCTAssertNotEqual(chatBUserTurns[1].0, chatBUserTurns[2].0)
        XCTAssertEqual(chatBUserTurns[2].1, chatBOriginalPayload)
        XCTAssertTrue(chatB.items.contains(.user(id: chatBOriginalID, chatBOriginalPayload)))
        XCTAssertEqual(chatA.items, chatAItemsBeforeSubmit)

        let assistantOnlyChat = PiConversationModel(modelSettings: settings)
        assistantOnlyChat.items = [.assistantText(text: "assistant-only transcript")]
        hostingView.rootView = PiConversationView(
            model: assistantOnlyChat,
            modelSettings: settings,
            onSelectFavorites: {}
        )
        hostingView.layoutSubtreeIfNeeded()
        pumpMainRunLoop()
        textView = try XCTUnwrap(descendant(of: PasteInterceptingTextView.self, in: hostingView))
        XCTAssertTrue(window.makeFirstResponder(textView))
        textView.keyDown(with: try keyEvent(keyCode: 126, characters: "\u{F700}"))
        XCTAssertEqual(assistantOnlyChat.draft, "")
        XCTAssertTrue(assistantOnlyChat.draftAttachments.isEmpty)
        XCTAssertTrue(assistantOnlyChat.promptHistory.isEmpty)
    }

    // 2119: REQ-009.1.1
    // 2119: REQ-009.1.2
    // 2119: REQ-009.1.3
    // 2119: REQ-009.1.4
    // 2119: REQ-009.1.5
    // 2119: REQ-009.2.1

    // 2119: REQ-009.1.1
    // 2119: REQ-009.1.2
    // 2119: REQ-009.1.3
    // 2119: REQ-009.1.4
    // 2119: REQ-009.1.5
    // 2119: REQ-009.1.6
    // 2119: REQ-009.1.7
    // 2119: REQ-009.2.1
    // 2119: REQ-009.2.2
    // 2119: REQ-009.2.3
    // 2119: REQ-009.2.4
    // 2119: REQ-009.2.7
    // 2119: REQ-009.2.8
    // 2119: REQ-009.3.1
    // 2119: REQ-009.3.2
    // 2119: REQ-009.3.3
    func testMountedComposerAttachmentEditAndChatSwitchResetHistory() throws {
        let oldestAttachment = makeFileAttachment("chat-a-oldest.txt")
        let newestAttachments = [
            makeFileAttachment("chat-a-one.txt"),
            makeImageAttachment("chat-a-image.png"),
            makeFileAttachment("chat-a-two.txt")
        ]
        let chatAModel = PiConversationModel()
        chatAModel.items = [
            .user(id: firstID, UserMessagePayload(text: "chat A oldest prompt", attachments: [oldestAttachment])),
            .assistantText(text: "assistant content must not enter prompt history"),
            .user(id: secondID, UserMessagePayload(
                text: "chat A exact\nnewest prompt",
                attachments: newestAttachments
            ))
        ]
        let chatBOwnAttachment = makeFileAttachment("chat-b-own.txt")
        let chatBModel = PiConversationModel()
        chatBModel.items = [
            .user(UserMessagePayload(text: "chat B older prompt")),
            .assistantText(text: "chat B assistant response"),
            .user(UserMessagePayload(
                text: "chat B recalled prompt",
                attachments: [makeFileAttachment("chat-b-history.txt")]
            ))
        ]
        let harness = PromptHistoryComposerHarness(
            draft: "",
            attachments: [],
            history: chatAModel.promptHistory,
            identity: "chat-A"
        )
        let hostingView = NSHostingView(rootView: PromptHistoryComposerHarnessView(harness: harness))
        hostingView.frame = NSRect(x: 0, y: 0, width: 700, height: 180)
        let window = testWindow(containing: hostingView)
        defer { tearDown(window: window) }
        hostingView.layoutSubtreeIfNeeded()
        pumpMainRunLoop()
        let textView = try XCTUnwrap(descendant(of: PasteInterceptingTextView.self, in: hostingView))
        XCTAssertTrue(window.makeFirstResponder(textView))

        textView.keyDown(with: try keyEvent(keyCode: 126, characters: "\u{F700}"))
        pumpMainRunLoop()
        XCTAssertEqual(harness.draft, "chat A exact\nnewest prompt")
        XCTAssertEqual(harness.attachments, newestAttachments)
        textView.setSelectedRange(NSRange(location: 1, length: 2))
        textView.keyDown(with: try keyEvent(keyCode: 126, characters: "\u{F700}"))
        pumpMainRunLoop()
        XCTAssertEqual(harness.draft, "chat A oldest prompt")
        XCTAssertEqual(harness.attachments, [oldestAttachment])
        textView.keyDown(with: try keyEvent(keyCode: 126, characters: "\u{F700}"))
        pumpMainRunLoop()
        XCTAssertEqual(harness.draft, "chat A oldest prompt")
        XCTAssertEqual(harness.attachments, [oldestAttachment])
        textView.keyDown(with: try keyEvent(keyCode: 125, characters: "\u{F701}"))
        pumpMainRunLoop()
        XCTAssertEqual(harness.draft, "chat A exact\nnewest prompt")
        XCTAssertEqual(harness.attachments, newestAttachments)
        textView.keyDown(with: try keyEvent(keyCode: 125, characters: "\u{F701}"))
        pumpMainRunLoop()
        XCTAssertEqual(harness.draft, "")
        XCTAssertTrue(harness.attachments.isEmpty)

        harness.draft = "typed draft must survive"
        pumpMainRunLoop()
        textView.keyDown(with: try keyEvent(keyCode: 126, characters: "\u{F700}"))
        XCTAssertEqual(harness.draft, "typed draft must survive")

        harness.draft = ""
        harness.history = []
        pumpMainRunLoop()
        textView.keyDown(with: try keyEvent(keyCode: 126, characters: "\u{F700}"))
        XCTAssertEqual(harness.draft, "")
        XCTAssertTrue(harness.attachments.isEmpty)
        harness.history = chatAModel.promptHistory
        pumpMainRunLoop()
        textView.keyDown(with: try keyEvent(keyCode: 126, characters: "\u{F700}"))
        pumpMainRunLoop()
        XCTAssertEqual(harness.draft, "chat A exact\nnewest prompt")

        let attachmentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("prompt-history-\(UUID().uuidString).txt")
        try "attachment".write(to: attachmentURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: attachmentURL) }
        NSPasteboard.general.clearContents()
        XCTAssertTrue(NSPasteboard.general.writeObjects([attachmentURL as NSURL]))
        textView.paste(nil)
        pumpMainRunLoop()
        XCTAssertEqual(harness.attachments.map(\.displayName), ["chat-a-one.txt", "chat-a-image.png", "chat-a-two.txt", attachmentURL.lastPathComponent])
        XCTAssertEqual(chatAModel.promptHistory.last?.payload.attachments, newestAttachments)
        XCTAssertEqual(harness.history, chatAModel.promptHistory)
        let attachmentsBeforeRejectedUp = harness.attachments
        textView.keyDown(with: try keyEvent(keyCode: 126, characters: "\u{F700}"))
        XCTAssertEqual(harness.draft, "chat A exact\nnewest prompt")
        XCTAssertEqual(harness.attachments, attachmentsBeforeRejectedUp)

        textView.string += " edited"
        textView.didChangeText()
        pumpMainRunLoop()
        let editedDraft = harness.draft
        textView.keyDown(with: try keyEvent(keyCode: 126, characters: "\u{F700}"))
        XCTAssertEqual(harness.draft, editedDraft)
        XCTAssertEqual(chatAModel.promptHistory.last?.payload.text, "chat A exact\nnewest prompt")

        harness.draft = ""
        harness.attachments = []
        pumpMainRunLoop()
        textView.keyDown(with: try keyEvent(keyCode: 126, characters: "\u{F700}"))
        pumpMainRunLoop()
        XCTAssertEqual(harness.attachments, newestAttachments)

        harness.draft = "chat B own draft"
        harness.attachments = [chatBOwnAttachment]
        harness.history = chatBModel.promptHistory
        harness.identity = "chat-B"
        pumpMainRunLoop()
        XCTAssertEqual(textView.string, "chat B own draft")
        XCTAssertFalse(textView.string.contains("chat A"))
        XCTAssertEqual(harness.attachments, [chatBOwnAttachment])
        XCTAssertFalse(harness.attachments.contains(oldestAttachment))
        XCTAssertFalse(harness.attachments.contains { newestAttachments.contains($0) })

        harness.draft = ""
        harness.attachments = []
        pumpMainRunLoop()
        textView.keyDown(with: try keyEvent(keyCode: 126, characters: "\u{F700}"))
        pumpMainRunLoop()
        XCTAssertEqual(harness.draft, "chat B recalled prompt")
        XCTAssertEqual(harness.attachments.map(\.displayName), ["chat-b-history.txt"])
        XCTAssertEqual(harness.history, chatBModel.promptHistory)
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

    private func descendant<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = descendant(of: type, in: subview) { return match }
        }
        return nil
    }

    private func pumpMainRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private func tearDown(window: NSWindow) {
        window.makeFirstResponder(nil)
        window.orderOut(nil)
    }

    private func testWindow<Content: View>(containing hostingView: NSHostingView<Content>) -> NSWindow {
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        retainedPromptHistoryTestWindows.append(window)
        pumpMainRunLoop()
        return window
    }
}

@MainActor
private final class PromptHistoryComposerHarness: ObservableObject {
    @Published var draft: String
    @Published var attachments: [ComposerAttachment]
    @Published var history: [ComposerPromptHistoryEntry]
    @Published var identity: String

    init(
        draft: String,
        attachments: [ComposerAttachment],
        history: [ComposerPromptHistoryEntry],
        identity: String
    ) {
        self.draft = draft
        self.attachments = attachments
        self.history = history
        self.identity = identity
    }
}

@MainActor
private struct PromptHistoryComposerHarnessView: View {
    @ObservedObject var harness: PromptHistoryComposerHarness

    var body: some View {
        AttachmentComposerShell(
            draft: $harness.draft,
            attachments: $harness.attachments,
            promptHistory: harness.history,
            placeholder: "",
            textIdentity: harness.identity,
            sendDisabled: false,
            isRunning: false,
            onAddAttachments: { harness.attachments.append(contentsOf: $0) },
            onRemoveAttachment: { id in harness.attachments.removeAll { $0.id == id } },
            onSubmit: {},
            onStop: {}
        ) {
            EmptyView()
        }
    }
}

// Xcode 16.4's XCTest memory checker can dereference a stale SwiftUI/AppKit
// bridge object when a hosted test window is deallocated after a test.
@MainActor private var retainedPromptHistoryTestWindows: [NSWindow] = []
