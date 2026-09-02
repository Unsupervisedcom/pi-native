import AppKit
import SwiftUI

struct PromoteToProjectOptions: Equatable {
    var initializeGitRepo = true
    var seedProjectMemory = true
    var addAgentInstructions = true

    init(
        initializeGitRepo: Bool = true,
        seedProjectMemory: Bool = true,
        addAgentInstructions: Bool = true
    ) {
        self.initializeGitRepo = initializeGitRepo
        self.seedProjectMemory = seedProjectMemory
        self.addAgentInstructions = addAgentInstructions
    }
}

struct PromoteToProjectResult: Equatable {
    var projectName: String
    var projectPath: String
}

enum PromoteToProjectPhase: Equatable {
    case idle
    case running
    case succeeded
    case failed(String)
}

enum PromoteToProjectStep: String, CaseIterable, Identifiable {
    case validateInputs
    case prepareDestination
    case createArtifacts
    case checkGit
    case registerProject
    case prepareHandoff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .validateInputs: "Validating input"
        case .prepareDestination: "Preparing destination"
        case .createArtifacts: "Creating project context"
        case .checkGit: "Checking git"
        case .registerProject: "Registering project"
        case .prepareHandoff: "Preparing handoff"
        }
    }
}

enum PromoteToProjectStepStatus: Equatable {
    case pending
    case running
    case succeeded(String? = nil)
    case skipped(String)
    case failed(String)

    var detail: String? {
        switch self {
        case .pending, .running: nil
        case .succeeded(let message): message
        case .skipped(let message), .failed(let message): message
        }
    }
}

struct PromoteToProjectStepState: Identifiable, Equatable {
    var step: PromoteToProjectStep
    var status: PromoteToProjectStepStatus = .pending
    var id: PromoteToProjectStep.ID { step.id }
}

struct PromoteToProjectRequest {
    var sourceSession: Session
    var projectName: String
    var codeFolder: String
    var options: PromoteToProjectOptions
}

struct PromoteToProjectDestination: Equatable {
    var projectName: String
    var slug: String
    var codeFolderURL: URL
    var destinationURL: URL
}

enum PromoteToProjectServiceError: LocalizedError, Equatable {
    case emptyProjectName
    case emptySlug
    case relativeCodeFolder
    case destinationEscapesCodeFolder
    case destinationIsFile(String)
    case nonEmptyUnmarkedDestination(String)
    case cannotCreateDirectory(String)
    case cannotWriteArtifact(String)
    case gitFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyProjectName: "Enter a project name."
        case .emptySlug: "Choose a project name with at least one letter or number."
        case .relativeCodeFolder: "Enter an absolute code folder path."
        case .destinationEscapesCodeFolder: "The destination must stay inside the selected code folder."
        case .destinationIsFile(let path): "The destination is a file, not a folder: \(path)"
        case .nonEmptyUnmarkedDestination(let path): "Choose an empty folder or an existing PiNative-promoted folder: \(path)"
        case .cannotCreateDirectory(let message): "Couldn’t create the project folder: \(message)"
        case .cannotWriteArtifact(let message): "Couldn’t write project context: \(message)"
        case .gitFailed(let message): "Couldn’t initialize git: \(message)"
        }
    }
}

struct PromoteToProjectService {
    var fileManager: FileManager = .default
    var now: () -> Date = Date.init
    var recordWrite: ((URL) -> Void)? = nil
    var afterArtifactsCreated: (() throws -> Void)? = nil

    private let markerRelativePath = ".pinative/promote-to-project.json"

    func validate(_ request: PromoteToProjectRequest) throws -> PromoteToProjectDestination {
        let trimmedName = request.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw PromoteToProjectServiceError.emptyProjectName }
        let slug = Self.slug(from: trimmedName)
        guard !slug.isEmpty else { throw PromoteToProjectServiceError.emptySlug }

        let expandedCodeFolder = (request.codeFolder as NSString).expandingTildeInPath
        guard expandedCodeFolder.hasPrefix("/") else { throw PromoteToProjectServiceError.relativeCodeFolder }
        let codeFolderURL = URL(fileURLWithPath: expandedCodeFolder).standardizedFileURL.resolvingSymlinksInPath()
        let destinationURL = codeFolderURL.appendingPathComponent(slug, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        guard isURL(destinationURL, equalToOrInside: codeFolderURL) else {
            throw PromoteToProjectServiceError.destinationEscapesCodeFolder
        }

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: destinationURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw PromoteToProjectServiceError.destinationIsFile(destinationURL.path) }
            let destination = PromoteToProjectDestination(projectName: trimmedName, slug: slug, codeFolderURL: codeFolderURL, destinationURL: destinationURL)
            if !isAllowedExistingDestination(destination, sourceSession: request.sourceSession) {
                throw PromoteToProjectServiceError.nonEmptyUnmarkedDestination(destinationURL.path)
            }
        }

        return PromoteToProjectDestination(projectName: trimmedName, slug: slug, codeFolderURL: codeFolderURL, destinationURL: destinationURL)
    }

    func prepareDestination(_ destination: PromoteToProjectDestination, sourceSession: Session) throws {
        do {
            try assertDestinationStaysInsideCodeFolder(destination)
            try createDirectory(at: destination.destinationURL, inside: destination.destinationURL)
            try createDirectory(at: destination.destinationURL.appendingPathComponent(".pinative", isDirectory: true), inside: destination.destinationURL)
            _ = try createFileIfMissing(
                destination.destinationURL.appendingPathComponent(markerRelativePath),
                contents: markerJSON(destination: destination, sourceSession: sourceSession),
                inside: destination.destinationURL
            )
        } catch let error as PromoteToProjectServiceError {
            throw error
        } catch {
            throw PromoteToProjectServiceError.cannotCreateDirectory(error.localizedDescription)
        }
    }

    func createArtifacts(request: PromoteToProjectRequest, destination: PromoteToProjectDestination) throws -> [String] {
        var notes: [String] = []
        do {
            try assertDestinationStaysInsideCodeFolder(destination)
            try createFileIfMissing(
                destination.destinationURL.appendingPathComponent("README.md"),
                contents: """
                # \(destination.projectName)

                This project was promoted from a PiNative chat on \(Self.isoString(now())).
                """,
                inside: destination.destinationURL
            ).map { notes.append($0) }

            try createDirectory(at: destination.destinationURL.appendingPathComponent("docs", isDirectory: true), inside: destination.destinationURL)

            if request.options.seedProjectMemory {
                try createFileIfMissing(
                    destination.destinationURL.appendingPathComponent("docs/project-plan.md"),
                    contents: """
                    # Project Plan

                    Promoted from PiNative Quick Chat “\(request.sourceSession.name)” on \(Self.isoString(now())).

                    ## Implementation directive

                    Treat the promoted chat transcript as the source plan for this project. Begin implementation from that plan immediately; do not continue planning unless the transcript is missing a blocking decision.

                    ## Project context

                    Use this file to capture goals, decisions, and next steps as the project evolves.
                    """,
                    inside: destination.destinationURL
                ).map { notes.append($0) }
                try createFileIfMissing(
                    destination.destinationURL.appendingPathComponent("docs/project-log.md"),
                    contents: """
                    # Project Log

                    ## \(Self.isoString(now())) — Promoted to Project

                    - Source chat: \(request.sourceSession.name)
                    - Source session ID: \(request.sourceSession.id.uuidString)
                    - Handoff: start implementation from the promoted planning transcript.
                    """,
                    inside: destination.destinationURL
                ).map { notes.append($0) }
            }

            if request.options.addAgentInstructions {
                try createFileIfMissing(
                    destination.destinationURL.appendingPathComponent("AGENTS.md"),
                    contents: """
                    # Agent Instructions

                    This project was created from a PiNative Promote to Project flow. Keep durable project context in `docs/` and update it as decisions are made.
                    """,
                    inside: destination.destinationURL
                ).map { notes.append($0) }
            }

            try createFileIfMissing(
                destination.destinationURL.appendingPathComponent("promoted-chat.md"),
                contents: provenanceMarkdown(for: request.sourceSession),
                inside: destination.destinationURL
            ).map { notes.append($0) }

            try afterArtifactsCreated?()
        } catch let error as PromoteToProjectServiceError {
            throw error
        } catch {
            throw PromoteToProjectServiceError.cannotWriteArtifact(error.localizedDescription)
        }
        return notes
    }

    func initializeGitIfNeeded(destination: PromoteToProjectDestination, enabled: Bool) throws -> String {
        try assertDestinationStaysInsideCodeFolder(destination)
        guard enabled else { return "Git initialization disabled" }
        if isInsideGitWorkTree(destination.destinationURL) {
            return "Already inside a git work tree"
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init"]
        process.currentDirectoryURL = destination.destinationURL
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw PromoteToProjectServiceError.gitFailed(error.localizedDescription)
        }
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PromoteToProjectServiceError.gitFailed(message?.isEmpty == false ? message! : "git init exited with status \(process.terminationStatus)")
        }
        return "Initialized git repository"
    }

    static func slug(from name: String) -> String {
        var scalars: [UnicodeScalar] = []
        var previousWasDash = false
        for scalar in name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().unicodeScalars {
            let isAlphaNumeric = ("a"..."z").contains(Character(scalar)) || ("0"..."9").contains(Character(scalar))
            if isAlphaNumeric {
                scalars.append(scalar)
                previousWasDash = false
            } else if !previousWasDash {
                scalars.append("-")
                previousWasDash = true
            }
        }
        return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func isAllowedExistingDestination(_ destination: PromoteToProjectDestination, sourceSession: Session) -> Bool {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: destination.destinationURL.path) else { return false }
        let visibleContents = contents.filter { $0 != ".DS_Store" }
        if visibleContents.isEmpty { return true }
        let markerURL = destination.destinationURL.appendingPathComponent(markerRelativePath)
        guard let markerData = fileManager.contents(atPath: markerURL.path),
              let object = try? JSONSerialization.jsonObject(with: markerData),
              let marker = object as? [String: Any] else { return false }
        return marker["schemaVersion"] as? Int == 1
            && marker["projectName"] as? String == destination.projectName
            && marker["destinationPath"] as? String == destination.destinationURL.path
            && marker["sourceSessionID"] as? String == sourceSession.id.uuidString
            && (marker["createdAt"] as? String)?.isEmpty == false
    }

    private func assertDestinationStaysInsideCodeFolder(_ destination: PromoteToProjectDestination) throws {
        let resolvedDestinationURL = destination.destinationURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCodeFolderURL = destination.codeFolderURL.resolvingSymlinksInPath().standardizedFileURL
        guard isURL(resolvedDestinationURL, equalToOrInside: resolvedCodeFolderURL) else {
            throw PromoteToProjectServiceError.destinationEscapesCodeFolder
        }
    }

    private func createDirectory(at url: URL, inside destinationURL: URL) throws {
        try assertWriteURL(url, staysInside: destinationURL)
        recordWrite?(url.standardizedFileURL)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func createFileIfMissing(_ url: URL, contents: String, inside destinationURL: URL) throws -> String? {
        try assertWriteURL(url, staysInside: destinationURL)
        if fileManager.fileExists(atPath: url.path) { return "Skipped existing \(url.lastPathComponent)" }
        try createDirectory(at: url.deletingLastPathComponent(), inside: destinationURL)
        recordWrite?(url.standardizedFileURL)
        guard fileManager.createFile(atPath: url.path, contents: Data(contents.utf8)) else {
            throw PromoteToProjectServiceError.cannotWriteArtifact("Could not create \(url.path)")
        }
        return nil
    }

    private func assertWriteURL(_ url: URL, staysInside destinationURL: URL) throws {
        let resolvedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedDestinationURL = destinationURL.standardizedFileURL.resolvingSymlinksInPath()
        guard isURL(resolvedURL, equalToOrInside: resolvedDestinationURL) else {
            throw PromoteToProjectServiceError.destinationEscapesCodeFolder
        }
    }

    private func markerJSON(destination: PromoteToProjectDestination, sourceSession: Session) -> String {
        """
        {
          "schemaVersion": 1,
          "projectName": "\(Self.jsonEscape(destination.projectName))",
          "destinationPath": "\(Self.jsonEscape(destination.destinationURL.path))",
          "sourceSessionID": "\(sourceSession.id.uuidString)",
          "createdAt": "\(Self.isoString(now()))"
        }
        """
    }

    private func provenanceMarkdown(for session: Session) -> String {
        let transcriptAvailability = session.cachedTranscript.isEmpty ? "No cached transcript available" : "Cached transcript included"
        var lines: [String] = [
            "# Promoted Chat Provenance",
            "",
            "- Source chat: \(session.name)",
            "- Source session ID: \(session.id.uuidString)",
            "- Promotion timestamp: \(Self.isoString(now()))",
            "- Transcript availability: \(transcriptAvailability)",
            "- Handoff instruction: use this transcript as the implementation plan."
        ]
        if let filePath = session.filePath {
            lines.append("- Source session file: \(filePath)")
        }
        lines.append(contentsOf: ["", "## Cached transcript", ""])
        if session.cachedTranscript.isEmpty {
            lines.append("No cached transcript was available when this project was promoted.")
        } else {
            for item in session.cachedTranscript {
                lines.append(Self.markdown(for: item))
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func isInsideGitWorkTree(_ url: URL) -> Bool {
        var current = url.standardizedFileURL
        while true {
            if fileManager.fileExists(atPath: current.appendingPathComponent(".git").path) { return true }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return false }
            current = parent
        }
    }

    private func isURL(_ child: URL, equalToOrInside parent: URL) -> Bool {
        let childPath = child.standardizedFileURL.path
        let parentPath = parent.standardizedFileURL.path
        return childPath == parentPath || childPath.hasPrefix(parentPath.hasSuffix("/") ? parentPath : parentPath + "/")
    }

    private static func markdown(for item: TranscriptItem) -> String {
        switch item {
        case .user(_, let payload):
            let userText = payload.text.isEmpty ? "(No text)" : payload.text
            var text = "### User\n\n\(userText)"
            if !payload.attachments.isEmpty {
                text += "\n\nAttachments: " + payload.attachments.map(\.displayName).joined(separator: ", ")
            }
            return text
        case .assistantText(_, let text):
            return "### Assistant\n\n\(text)"
        case .activity(let group):
            return "### Activity\n\n\(group.tools.map { "- \($0.name): \($0.status.label)" }.joined(separator: "\n"))"
        case .notice(_, let text):
            return "### Notice\n\n\(text)"
        }
    }

    private static func jsonEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

@MainActor
final class PromoteToProjectWorkflowModel: ObservableObject {
    @Published var projectName: String
    @Published private(set) var steps: [PromoteToProjectStepState] = PromoteToProjectStep.allCases.map { .init(step: $0) }
    @Published private(set) var phase: PromoteToProjectPhase = .idle
    @Published private(set) var result: PromoteToProjectResult?
    @Published private(set) var validationMessage: String?

    private let session: Session
    private let codeFolder: String
    private let options: PromoteToProjectOptions
    private let service: PromoteToProjectService
    private let stepDelayNanoseconds: UInt64

    init(
        session: Session,
        codeFolder: String,
        options: PromoteToProjectOptions,
        service: PromoteToProjectService = PromoteToProjectService()
    ) {
        self.session = session
        self.codeFolder = codeFolder
        self.options = options
        self.service = service
        self.projectName = session.name == "New Chat" ? "New Project" : session.name
        let delayMS = UInt64(ProcessInfo.processInfo.environment["PI_NATIVE_TEST_PROMOTE_STEP_DELAY_MS"] ?? "140") ?? 140
        self.stepDelayNanoseconds = delayMS * 1_000_000
    }

    var isRunning: Bool { phase == .running }
    var canPromote: Bool { !isRunning && !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var destinationPreview: String {
        let expanded = (codeFolder as NSString).expandingTildeInPath
        let slug = PromoteToProjectService.slug(from: projectName)
        return URL(fileURLWithPath: expanded).appendingPathComponent(slug.isEmpty ? "project-folder" : slug).standardizedFileURL.path
    }

    func start() async {
        guard !isRunning else { return }
        resetSteps()
        result = nil
        validationMessage = nil
        phase = .running
        let request = PromoteToProjectRequest(sourceSession: session, projectName: projectName, codeFolder: codeFolder, options: options)
        do {
            set(.validateInputs, .running)
            try await delayIfNeeded()
            let destination = try service.validate(request)
            set(.validateInputs, .succeeded(destination.destinationURL.path))

            set(.prepareDestination, .running)
            try await delayIfNeeded()
            try service.prepareDestination(destination, sourceSession: session)
            set(.prepareDestination, .succeeded(destination.destinationURL.path))

            set(.createArtifacts, .running)
            try await delayIfNeeded()
            let artifactNotes = try service.createArtifacts(request: request, destination: destination)
            set(.createArtifacts, artifactNotes.isEmpty ? .succeeded("Project context ready") : .skipped(artifactNotes.joined(separator: ", ")))

            set(.checkGit, .running)
            try await delayIfNeeded()
            let gitMessage = try service.initializeGitIfNeeded(destination: destination, enabled: options.initializeGitRepo)
            if gitMessage.contains("disabled") || gitMessage.contains("Already") {
                set(.checkGit, .skipped(gitMessage))
            } else {
                set(.checkGit, .succeeded(gitMessage))
            }

            set(.registerProject, .running)
            try await delayIfNeeded()
            set(.registerProject, .succeeded("Ready to add to PiNative"))

            set(.prepareHandoff, .running)
            try await delayIfNeeded()
            set(.prepareHandoff, .succeeded("Opening the promoted project"))

            result = PromoteToProjectResult(projectName: destination.projectName, projectPath: destination.destinationURL.path)
            phase = .succeeded
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            failRunningStep(message)
            validationMessage = message
            phase = .failed(message)
        }
    }

    func retry() async {
        await start()
    }

    private func resetSteps() {
        withAnimation(.smooth(duration: 0.18)) {
            steps = PromoteToProjectStep.allCases.map { .init(step: $0) }
        }
    }

    private func set(_ step: PromoteToProjectStep, _ status: PromoteToProjectStepStatus) {
        guard let index = steps.firstIndex(where: { $0.step == step }) else { return }
        withAnimation(.smooth(duration: 0.22)) {
            steps[index].status = status
        }
    }

    private func failRunningStep(_ message: String) {
        guard let running = steps.first(where: { if case .running = $0.status { return true } else { return false } }) else { return }
        set(running.step, .failed(message))
    }

    private func delayIfNeeded() async throws {
        if stepDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: stepDelayNanoseconds)
        }
    }
}

struct PromoteToProjectModal: View {
    let session: Session
    let onCancel: () -> Void
    let onComplete: (String) -> Project.ID

    @StateObject private var workflow: PromoteToProjectWorkflowModel
    @State private var didAttemptAutomaticHandoff = false

    init(
        session: Session,
        defaultCodeFolder: String,
        options: PromoteToProjectOptions,
        onCancel: @escaping () -> Void,
        onComplete: @escaping (String) -> Project.ID
    ) {
        self.session = session
        self.onCancel = onCancel
        self.onComplete = onComplete
        _workflow = StateObject(wrappedValue: PromoteToProjectWorkflowModel(session: session, codeFolder: defaultCodeFolder, options: options))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            fields
            progress
            if let message = workflow.validationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("promoteToProject.errorMessage")
            }
            buttons
        }
        .padding(28)
        .frame(width: 460)
        .accessibilityIdentifier("promoteToProject.modal")
        .onChange(of: workflow.phase) { _, phase in
            guard phase == .succeeded else { return }
            completeHandoffIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Promote to Project", systemImage: "shippingbox")
                .font(.title2.weight(.semibold))
            Text("Name the project. Folder location and project-context defaults are managed in Settings → Projects.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 10) {
            labeledField("Project name") {
                TextField("Project name", text: $workflow.projectName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(workflow.isRunning)
                    .accessibilityIdentifier("promoteToProject.projectNameField")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Destination")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(workflow.destinationPreview)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("promoteToProject.destinationPreview")
            }
        }
    }

    @ViewBuilder
    private var progress: some View {
        if workflow.phase != .idle {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(workflow.steps) { step in
                    PromoteProgressRow(state: step)
                }
            }
            .padding(.top, 2)
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            switch workflow.phase {
            case .idle:
                Button("Cancel", action: onCancel)
                    .accessibilityIdentifier("promoteToProject.cancelButton")
                Button("Promote") {
                    Task { await workflow.start() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!workflow.canPromote)
                .accessibilityIdentifier("promoteToProject.promoteButton")
            case .running:
                Button("Cancel", action: {})
                    .disabled(true)
                    .accessibilityIdentifier("promoteToProject.cancelButton")
                Button("Promoting…", action: {})
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
                    .accessibilityIdentifier("promoteToProject.promoteButton")
            case .failed:
                Button("Cancel", action: onCancel)
                    .accessibilityIdentifier("promoteToProject.cancelButton")
                Button("Retry") {
                    Task { await workflow.retry() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("promoteToProject.retryButton")
            case .succeeded:
                Button("Opening Project…", action: {})
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
                    .accessibilityIdentifier("promoteToProject.doneButton")
            }
        }
    }

    private func completeHandoffIfNeeded() {
        guard !didAttemptAutomaticHandoff, let result = workflow.result else { return }
        didAttemptAutomaticHandoff = true
        _ = onComplete(result.projectPath)
    }

    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

private struct PromoteProgressRow: View {
    let state: PromoteToProjectStepState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PromoteStatusGlyph(status: state.status, identifierBase: "promoteToProject.step.\(state.step.id)")
                .contentTransition(.symbolEffect(.replace))
                .animation(.smooth(duration: 0.22), value: state.status)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.step.title)
                    .font(.caption.weight(.semibold))
                if let detail = state.status.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(isError ? .red : .secondary)
                        .lineLimit(2)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }

    private var isError: Bool {
        if case .failed = state.status { return true }
        return false
    }
}

private struct PromoteStatusGlyph: View {
    let status: PromoteToProjectStepStatus
    let identifierBase: String

    var body: some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("\(identifierBase).pending")
        case .running:
            ProgressView()
                .controlSize(.small)
                .accessibilityIdentifier("\(identifierBase).spinner")
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityIdentifier("\(identifierBase).checkmark")
        case .skipped:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("\(identifierBase).skipped")
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityIdentifier("\(identifierBase).error")
        }
    }
}
