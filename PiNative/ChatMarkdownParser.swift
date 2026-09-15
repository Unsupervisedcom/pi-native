import Foundation

struct ChatMarkdownDocument {
    var blocks: [ChatMarkdownBlock]
}

struct ChatMarkdownBlock {
    enum Role: Equatable {
        case paragraph
        case heading(level: Int)
        case code(language: String?)
        case thematicBreak
    }

    enum ListStyle: Equatable {
        case ordered
        case unordered
    }

    struct ListContext: Equatable {
        var style: ListStyle
        var ordinal: Int
        var depth: Int
    }

    var role: Role
    var content: AttributedString
    var list: ListContext?
    var quoteDepth: Int
}

enum ChatMarkdownParser {
    static func parse(_ source: String) -> ChatMarkdownDocument {
        guard !source.isEmpty else { return ChatMarkdownDocument(blocks: []) }

        let parsed: AttributedString
        do {
            parsed = try AttributedString(
                markdown: preservingSoftBreaks(in: source),
                options: .init(
                    interpretedSyntax: .full,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        } catch {
            return plainTextDocument(source)
        }

        let visibleText = String(parsed.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !visibleText.isEmpty || source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return plainTextDocument(source)
        }

        var blocks: [ChatMarkdownBlock] = []
        var currentIdentity: Int?
        var currentIntent: PresentationIntent?
        var currentContent = AttributedString()

        func appendCurrentBlock() {
            guard !currentContent.characters.isEmpty else { return }
            blocks.append(block(content: currentContent, intent: currentIntent))
        }

        for run in parsed.runs {
            let intent = run.presentationIntent
            let identity = intent?.components.first?.identity
            if !currentContent.characters.isEmpty, identity != currentIdentity {
                appendCurrentBlock()
                currentContent = AttributedString()
            }
            currentIdentity = identity
            currentIntent = intent
            currentContent.append(AttributedString(parsed[run.range]))
        }
        appendCurrentBlock()

        if blocks.isEmpty, !source.isEmpty {
            return plainTextDocument(source)
        }
        return ChatMarkdownDocument(blocks: blocks)
    }

    private static func preservingSoftBreaks(in source: String) -> String {
        var isInsideFence = false
        return source.components(separatedBy: .newlines).map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                isInsideFence.toggle()
                return line
            }
            guard !isInsideFence, !trimmed.isEmpty, !line.hasSuffix("  ") else { return line }
            return line + "  "
        }.joined(separator: "\n")
    }

    private static func block(content: AttributedString, intent: PresentationIntent?) -> ChatMarkdownBlock {
        let components = intent?.components ?? []
        var role: ChatMarkdownBlock.Role = .paragraph
        var listStyle: ChatMarkdownBlock.ListStyle?
        var ordinal = 1
        var quoteDepth = 0

        for component in components {
            switch component.kind {
            case .header(let level):
                role = .heading(level: level)
            case .codeBlock(let languageHint):
                role = .code(language: languageHint)
            case .thematicBreak:
                role = .thematicBreak
            case .orderedList:
                listStyle = .ordered
            case .unorderedList:
                listStyle = .unordered
            case .listItem(let itemOrdinal):
                ordinal = itemOrdinal
            case .blockQuote:
                quoteDepth += 1
            default:
                break
            }
        }

        let list = listStyle.map {
            ChatMarkdownBlock.ListContext(
                style: $0,
                ordinal: ordinal,
                depth: max((intent?.indentationLevel ?? 1) - 1, 0)
            )
        }
        return ChatMarkdownBlock(role: role, content: content, list: list, quoteDepth: quoteDepth)
    }

    private static func plainTextDocument(_ source: String) -> ChatMarkdownDocument {
        ChatMarkdownDocument(
            blocks: [ChatMarkdownBlock(role: .paragraph, content: AttributedString(source), list: nil, quoteDepth: 0)]
        )
    }
}

enum ChatMessageLayout {
    static let activityWrappedLineSpacing: CGFloat = 0
    static let activitySummarySpacing: CGFloat = 10
}
