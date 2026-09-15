import Foundation
import XCTest
@testable import PiNative

final class ChatMessageFormattingTests: XCTestCase {
    // 2119: REQ-014.1.1
    func testCommonMarkdownProducesStructuredBlocksAndInlineSemanticsWithoutDelimiters() throws {
        let source = """
        # Heading

        First paragraph with *emphasis*, **strong emphasis**, [a link](https://example.com), and `inline code`.

        Second paragraph.

        - Unordered item

        1. Ordered item

        > Quoted guidance

        ```swift
        let answer = 42
        ```
        """

        let document = ChatMarkdownParser.parse(source)
        let visibleText = document.blocks.map { String($0.content.characters) }.joined(separator: "\n")

        XCTAssertTrue(document.blocks.contains { $0.role == .heading(level: 1) && String($0.content.characters) == "Heading" })
        XCTAssertGreaterThanOrEqual(document.blocks.filter { $0.role == .paragraph && $0.list == nil && $0.quoteDepth == 0 }.count, 2)
        XCTAssertTrue(document.blocks.contains { $0.list?.style == .unordered && String($0.content.characters) == "Unordered item" })
        XCTAssertTrue(document.blocks.contains { $0.list?.style == .ordered && $0.list?.ordinal == 1 && String($0.content.characters) == "Ordered item" })
        XCTAssertTrue(document.blocks.contains { $0.quoteDepth == 1 && String($0.content.characters) == "Quoted guidance" })
        XCTAssertTrue(document.blocks.contains { $0.role == .code(language: "swift") && String($0.content.characters).contains("let answer = 42") })

        let runs = document.blocks.flatMap { Array($0.content.runs) }
        XCTAssertTrue(runs.contains { $0.inlinePresentationIntent?.contains(.emphasized) == true })
        XCTAssertTrue(runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        XCTAssertTrue(runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
        XCTAssertTrue(runs.contains { $0.link?.absoluteString == "https://example.com" })
        for delimiter in ["# Heading", "*emphasis*", "**strong emphasis**", "[a link]", "`inline code`", "```swift"] {
            XCTAssertFalse(visibleText.contains(delimiter), "Rendered content retained Markdown delimiter: \(delimiter)")
        }
    }

    func testPlainMultilineAssistantTextPreservesLineBreaks() {
        let source = (1...60).map { "Streaming response line \($0)" }.joined(separator: "\n")

        let document = ChatMarkdownParser.parse(source)

        XCTAssertEqual(String(document.blocks.first?.content.characters ?? AttributedString().characters), source)
    }

    // 2119: REQ-014.2.1
    func testActivitySummaryParagraphSpacingExceedsWrappedLineSpacing() {
        XCTAssertGreaterThan(
            ChatMessageLayout.activitySummarySpacing,
            ChatMessageLayout.activityWrappedLineSpacing,
            "Separate activity summaries must use more spacing than wrapped lines within one summary."
        )
    }

    // 2119: REQ-014.1.2
    func testIncompleteStreamingMarkdownAlwaysProducesReadableVisibleContent() {
        for source in ["#", "**streaming emphasis", "[link](", "-", "```swift\nlet value = 1"] {
            let document = ChatMarkdownParser.parse(source)
            let visibleText = document.blocks
                .map { String($0.content.characters) }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            XCTAssertFalse(visibleText.isEmpty, "Streaming prefix disappeared: \(source.debugDescription)")
        }
    }
}
