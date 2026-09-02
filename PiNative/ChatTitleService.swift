import Foundation
import OSLog

struct FirstExchangeSnapshot: Codable, Hashable, Sendable {
    let id: UUID
    let userPrompt: String
    let assistantText: String

    init(id: UUID = UUID(), userPrompt: String, assistantText: String) {
        self.id = id
        self.userPrompt = userPrompt
        self.assistantText = assistantText
    }
}

enum AutomaticTitleState: Codable, Hashable, Sendable {
    case ineligible
    case waitingForFirstResponse
    case pending(FirstExchangeSnapshot)
    case complete
}

enum ChatTitleSource: String, Codable, Hashable, Sendable {
    case placeholder
    case fallback
    case generated
    case authoritative
}

enum ChatTitleFormatting {
    static let maximumLength = 48

    static func fallback(from message: String) -> String {
        var phrase = collapsed(message)
        let prefixes = [
            "can you please ", "could you please ", "would you please ",
            "can you ", "could you ", "would you ", "please ",
            "i want you to ", "i need you to "
        ]
        let lowercase = phrase.lowercased()
        if let prefix = prefixes.first(where: { lowercase.hasPrefix($0) }) {
            phrase.removeFirst(prefix.count)
        }
        phrase = phrase.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
        guard !phrase.isEmpty else { return "New Chat" }
        phrase.replaceSubrange(phrase.startIndex...phrase.startIndex, with: String(phrase[phrase.startIndex]).uppercased())
        return limited(phrase)
    }

    static func semanticTitle(from output: String, firstUserPrompt: String) -> String? {
        var title = output
            .split(whereSeparator: \ .isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
        title = collapsed(title)
        if title.lowercased().hasPrefix("title:") {
            title.removeFirst("title:".count)
        }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'“”‘’`.,:;!?—–-"))
        guard !title.isEmpty else { return nil }
        title = limited(title)
        guard title.caseInsensitiveCompare(collapsed(firstUserPrompt)) != .orderedSame else { return nil }
        return title
    }

    static func prompt(for snapshot: FirstExchangeSnapshot) -> String {
        let assistant = snapshot.assistantText.isEmpty ? "(No assistant text was returned.)" : snapshot.assistantText
        return """
        Create a concise sidebar title for this completed first chat exchange.

        Return only a 3–7 word noun phrase describing the primary topic or task. Do not use quotes, labels, commentary, or trailing punctuation. Use at most 48 characters. Do not copy the user prompt verbatim.

        User: \(snapshot.userPrompt)

        Assistant: \(assistant)
        """
    }

    private static func collapsed(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func limited(_ title: String) -> String {
        guard title.count > maximumLength else { return title }
        let contentLimit = maximumLength - 1
        let prefix = String(title.prefix(contentLimit))
        let boundary = prefix.lastIndex(of: " ")
        let base = boundary.map { String(prefix[..<$0]) } ?? prefix
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? prefix : trimmed).prefix(contentLimit)) + "…"
    }
}

protocol ChatTitleGenerating: Sendable {
    func generateTitle(for snapshot: FirstExchangeSnapshot, workingDirectory: String) async throws -> String
}

actor PiChatTitleService: ChatTitleGenerating {
    static let shared = PiChatTitleService()

    enum GenerationError: LocalizedError {
        case emptyResponse
        case streamEnded
        case timedOut

        var errorDescription: String? {
            switch self {
            case .emptyResponse: "Pi returned no chat title."
            case .streamEnded: "Pi title generation ended before the agent settled."
            case .timedOut: "Pi title generation timed out."
            }
        }
    }

    private enum DeadlineResult: @unchecked Sendable {
        case output(String)
        case failure(any Error)
    }

    private static let logger = Logger(subsystem: "com.unsupervised.PiNative", category: "ChatTitles")
    private let timeoutNanoseconds: UInt64
    private var isGenerating = false
    private var queue: [CheckedContinuation<Void, Never>] = []

    init(timeoutNanoseconds: UInt64 = 45_000_000_000) {
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func generateTitle(for snapshot: FirstExchangeSnapshot, workingDirectory: String) async throws -> String {
        await acquireSlot()
        defer { releaseSlot() }
        try Task.checkCancellation()

        let startedAt = ContinuousClock.now
        Self.logger.info("title job started snapshot=\(snapshot.id.uuidString, privacy: .public)")
        do {
            let output = try await runIsolatedRPC(snapshot: snapshot, workingDirectory: workingDirectory)
            let elapsed = ContinuousClock.now - startedAt
            Self.logger.info("title job succeeded snapshot=\(snapshot.id.uuidString, privacy: .public) duration=\(String(describing: elapsed), privacy: .public)")
            return output
        } catch {
            Self.logger.error("title job failed snapshot=\(snapshot.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func acquireSlot() async {
        guard isGenerating else {
            isGenerating = true
            return
        }
        await withCheckedContinuation { continuation in
            queue.append(continuation)
        }
    }

    private func releaseSlot() {
        if queue.isEmpty {
            isGenerating = false
        } else {
            queue.removeFirst().resume()
        }
    }

    private func runIsolatedRPC(snapshot: FirstExchangeSnapshot, workingDirectory: String) async throws -> String {
        let client = PiRPCClient(
            workingDirectory: URL(fileURLWithPath: workingDirectory),
            usesIsolatedCommand: true
        )
        let (events, continuation) = AsyncStream<RPCEnvelope>.makeStream()
        await client.setOnEvent { event in continuation.yield(event) }

        do {
            let deadlineResult = await withTaskGroup(of: DeadlineResult.self) { group in
                group.addTask {
                    do {
                        try await client.start()
                        _ = try await client.prompt(ChatTitleFormatting.prompt(for: snapshot))
                        for await event in events {
                            try Task.checkCancellation()
                            if event.type == "agent_settled" {
                                let response = try await client.getLastAssistantText()
                                let output = response.data?.objectValue?["text"]?.stringValue?
                                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                guard !output.isEmpty else { throw GenerationError.emptyResponse }
                                return .output(output)
                            }
                        }
                        throw GenerationError.streamEnded
                    } catch {
                        return .failure(error)
                    }
                }
                group.addTask { [timeoutNanoseconds] in
                    do {
                        try await Task.sleep(nanoseconds: timeoutNanoseconds)
                        return .failure(GenerationError.timedOut)
                    } catch {
                        return .failure(error)
                    }
                }
                let first = await group.next() ?? .failure(GenerationError.streamEnded)
                group.cancelAll()
                return first
            }
            let output: String
            switch deadlineResult {
            case .output(let value): output = value
            case .failure(let error): throw error
            }
            continuation.finish()
            await client.stop()
            return output
        } catch {
            continuation.finish()
            await client.stop()
            throw error
        }
    }
}
