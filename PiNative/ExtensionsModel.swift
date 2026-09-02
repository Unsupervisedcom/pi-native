import Foundation

@MainActor
final class ExtensionsModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(ExtensionCatalog)
        case failed(String)
    }

    @Published var state: LoadState = .idle

    func refresh(projectPath: String?) async {
        guard let projectPath else {
            state = .failed("No selected project")
            return
        }

        state = .loading

        do {
            let client = PiRPCClient(workingDirectory: URL(fileURLWithPath: projectPath))
            try await client.start()
            defer { Task { await client.stop() } }

            let envelope = try await client.getCommands()
            state = .loaded(try Self.parseCatalog(envelope))
        } catch {
            state = .failed(Self.userVisibleError(error.localizedDescription))
        }
    }

    private static func userVisibleError(_ message: String) -> String {
        message
            .replacingOccurrences(of: "Pi RPC", with: "pi")
            .replacingOccurrences(of: "pi RPC", with: "pi")
            .replacingOccurrences(of: "RPC", with: "pi")
            .replacingOccurrences(of: "Pi rpc", with: "pi")
            .replacingOccurrences(of: "pi rpc", with: "pi")
            .replacingOccurrences(of: "rpc", with: "pi")
    }

    private static func parseCatalog(_ envelope: RPCEnvelope) throws -> ExtensionCatalog {
        guard envelope.success != false else {
            throw ParseError.rpcError(envelope.error?.stringValue ?? "get_commands failed")
        }

        guard
            let data = envelope.data?.objectValue,
            let commandValues = data["commands"]?.arrayValue
        else {
            return ExtensionCatalog(commands: [])
        }

        let commands = commandValues.compactMap { value -> ExtensionCommand? in
            guard let object = value.objectValue, let name = object["name"]?.stringValue else { return nil }
            return ExtensionCommand(
                name: name,
                description: object["description"]?.stringValue,
                source: object["source"]?.stringValue ?? "unknown",
                location: object["location"]?.stringValue,
                path: object["path"]?.stringValue
            )
        }

        return ExtensionCatalog(commands: commands.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    private enum ParseError: LocalizedError {
        case rpcError(String)

        var errorDescription: String? {
            switch self {
            case .rpcError(let message): message
            }
        }
    }
}

struct ExtensionCatalog: Equatable, Hashable {
    var commands: [ExtensionCommand]

    var extensionCommands: [ExtensionCommand] { commands.filter { $0.source == "extension" } }
    var promptTemplates: [ExtensionCommand] { commands.filter { $0.source == "prompt" } }
    var skills: [ExtensionCommand] { commands.filter { $0.source == "skill" } }
}

struct ExtensionCommand: Identifiable, Equatable, Hashable {
    var id: String { "\(source):\(name):\(path ?? "")" }
    var name: String
    var description: String?
    var source: String
    var location: String?
    var path: String?
}
