import XCTest
@testable import PiNative

final class PromoteToProjectTests: XCTestCase {
    override func setUp() {
        super.setUp()
        setenv("PI_NATIVE_TEST_PROMOTE_STEP_DELAY_MS", "0", 1)
    }

    override func tearDown() {
        unsetenv("PI_NATIVE_TEST_PROMOTE_STEP_DELAY_MS")
        super.tearDown()
    }

    // 2119: REQ-002.1.2
    // 2119: REQ-002.1.3
    func testDestinationIsDerivedReusedAndUnsafeDestinationsAreRejected() throws {
        let root = try temporaryDirectory(named: "PiNativePromoteDestination")
        let outside = try temporaryDirectory(named: "PiNativePromoteOutside")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        var auditedWrites: [URL] = []
        let service = PromoteToProjectService(fileManager: .default, now: fixedNow, recordWrite: { auditedWrites.append($0) })
        let session = sourceSession()
        let request = PromoteToProjectRequest(
            sourceSession: session,
            projectName: "Safe Project!",
            codeFolder: root.path,
            options: PromoteToProjectOptions(initializeGitRepo: false, seedProjectMemory: false, addAgentInstructions: false)
        )

        let destination = try service.validate(request)
        XCTAssertEqual(destination.destinationURL.deletingLastPathComponent().path, root.standardizedFileURL.path)
        XCTAssertEqual(destination.destinationURL.lastPathComponent, "safe-project")
        let traversalDestination = try service.validate(PromoteToProjectRequest(
            sourceSession: session,
            projectName: "../../Escape/../Name",
            codeFolder: root.path,
            options: request.options
        ))
        XCTAssertEqual(traversalDestination.destinationURL.deletingLastPathComponent().path, root.standardizedFileURL.path)
        XCTAssertEqual(traversalDestination.destinationURL.lastPathComponent, "escape-name")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("escape-name").path))
        try service.prepareDestination(destination, sourceSession: session)
        _ = try service.createArtifacts(request: request, destination: destination)
        XCTAssertFalse(auditedWrites.isEmpty)
        let auditedWritesOutsideDestination = auditedWrites.filter { url in
            let path = url.standardizedFileURL.path
            return path != destination.destinationURL.path && !path.hasPrefix(destination.destinationURL.path + "/")
        }
        XCTAssertTrue(auditedWritesOutsideDestination.isEmpty, "Promotion attempted writes outside the destination: \(auditedWritesOutsideDestination.map(\.path))")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.destinationURL.appendingPathComponent("promoted-chat.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("promoted-chat.md").path))

        let reused = try service.validate(request)
        XCTAssertEqual(reused.destinationURL.path, destination.destinationURL.path)

        // 2119: REQ-002.1.5
        let nestedDocs = destination.destinationURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.removeItem(at: nestedDocs)
        try FileManager.default.createSymbolicLink(at: nestedDocs, withDestinationURL: outside)
        XCTAssertThrowsError(try service.createArtifacts(request: request, destination: destination)) { error in
            XCTAssertEqual(error as? PromoteToProjectServiceError, .destinationEscapesCodeFolder)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("project-plan.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("project-log.md").path))

        let fileDestination = root.appendingPathComponent("file-destination")
        try "not a directory".write(to: fileDestination, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try service.validate(PromoteToProjectRequest(
            sourceSession: session,
            projectName: "File Destination",
            codeFolder: root.path,
            options: request.options
        ))) { error in
            XCTAssertEqual(error as? PromoteToProjectServiceError, .destinationIsFile(fileDestination.path))
        }

        let nonEmptyUnmarked = root.appendingPathComponent("non-empty-unmarked", isDirectory: true)
        try FileManager.default.createDirectory(at: nonEmptyUnmarked, withIntermediateDirectories: true)
        try "user work".write(to: nonEmptyUnmarked.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try service.validate(PromoteToProjectRequest(
            sourceSession: session,
            projectName: "Non Empty Unmarked",
            codeFolder: root.path,
            options: request.options
        ))) { error in
            XCTAssertEqual(error as? PromoteToProjectServiceError, .nonEmptyUnmarkedDestination(nonEmptyUnmarked.path))
        }

        let forgedMarked = root.appendingPathComponent("forged-marked", isDirectory: true)
        try FileManager.default.createDirectory(at: forgedMarked.appendingPathComponent(".pinative", isDirectory: true), withIntermediateDirectories: true)
        try "user work".write(to: forgedMarked.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try """
        { "schemaVersion": 1, "projectName": "Forged Marked", "destinationPath": "\(forgedMarked.path)", "sourceSessionID": "\(UUID().uuidString)", "createdAt": "2026-08-04T00:00:00Z" }
        """.write(to: forgedMarked.appendingPathComponent(".pinative/promote-to-project.json"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try service.validate(PromoteToProjectRequest(
            sourceSession: session,
            projectName: "Forged Marked",
            codeFolder: root.path,
            options: request.options
        ))) { error in
            XCTAssertEqual(error as? PromoteToProjectServiceError, .nonEmptyUnmarkedDestination(forgedMarked.path))
        }

        let wrongDestinationMarked = root.appendingPathComponent("wrong-destination-marked", isDirectory: true)
        try FileManager.default.createDirectory(at: wrongDestinationMarked.appendingPathComponent(".pinative", isDirectory: true), withIntermediateDirectories: true)
        try "user work".write(to: wrongDestinationMarked.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try """
        { "schemaVersion": 1, "projectName": "Wrong Destination Marked", "destinationPath": "\(root.appendingPathComponent("somewhere-else").path)", "sourceSessionID": "\(session.id.uuidString)", "createdAt": "2026-08-04T00:00:00Z" }
        """.write(to: wrongDestinationMarked.appendingPathComponent(".pinative/promote-to-project.json"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try service.validate(PromoteToProjectRequest(
            sourceSession: session,
            projectName: "Wrong Destination Marked",
            codeFolder: root.path,
            options: request.options
        ))) { error in
            XCTAssertEqual(error as? PromoteToProjectServiceError, .nonEmptyUnmarkedDestination(wrongDestinationMarked.path))
        }

        let inspectionFails = root.appendingPathComponent("inspection-fails", isDirectory: true)
        try FileManager.default.createDirectory(at: inspectionFails, withIntermediateDirectories: true)
        let inspectionFailingFileManager = DirectoryInspectionFailingFileManager()
        inspectionFailingFileManager.failingDirectoryPath = inspectionFails.standardizedFileURL.path
        let inspectionFailingService = PromoteToProjectService(fileManager: inspectionFailingFileManager, now: fixedNow)
        XCTAssertThrowsError(try inspectionFailingService.validate(PromoteToProjectRequest(
            sourceSession: session,
            projectName: "Inspection Fails",
            codeFolder: root.path,
            options: request.options
        ))) { error in
            XCTAssertEqual(error as? PromoteToProjectServiceError, .nonEmptyUnmarkedDestination(inspectionFails.path))
        }

        let symlink = root.appendingPathComponent("escape", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)
        XCTAssertThrowsError(try service.validate(PromoteToProjectRequest(
            sourceSession: session,
            projectName: "Escape",
            codeFolder: root.path,
            options: request.options
        ))) { error in
            XCTAssertEqual(error as? PromoteToProjectServiceError, .destinationEscapesCodeFolder)
        }

        let raceDestination = try service.validate(PromoteToProjectRequest(
            sourceSession: session,
            projectName: "Race Escape",
            codeFolder: root.path,
            options: request.options
        ))
        try FileManager.default.createSymbolicLink(at: raceDestination.destinationURL, withDestinationURL: outside)
        XCTAssertThrowsError(try service.prepareDestination(raceDestination, sourceSession: session)) { error in
            XCTAssertEqual(error as? PromoteToProjectServiceError, .destinationEscapesCodeFolder)
        }

        let forgedOutsideDestination = PromoteToProjectDestination(
            projectName: "Forged Outside",
            slug: "forged-outside",
            codeFolderURL: root.standardizedFileURL,
            destinationURL: outside.appendingPathComponent("forged-outside", isDirectory: true).standardizedFileURL
        )
        XCTAssertThrowsError(try service.prepareDestination(forgedOutsideDestination, sourceSession: session)) { error in
            XCTAssertEqual(error as? PromoteToProjectServiceError, .destinationEscapesCodeFolder)
        }
        XCTAssertThrowsError(try service.createArtifacts(request: request, destination: forgedOutsideDestination)) { error in
            XCTAssertEqual(error as? PromoteToProjectServiceError, .destinationEscapesCodeFolder)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: forgedOutsideDestination.destinationURL.path))
    }

    // 2119: REQ-002.1.5
    func testPromotionFileManagerRejectsAnyAttemptedWriteOutsideDerivedDestination() throws {
        let root = try temporaryDirectory(named: "PiNativePromoteWriteGuard")
        defer { try? FileManager.default.removeItem(at: root) }
        let trackingFileManager = DestinationRejectingFileManager()
        let service = PromoteToProjectService(fileManager: trackingFileManager, now: fixedNow)
        let session = sourceSession()
        let request = PromoteToProjectRequest(
            sourceSession: session,
            projectName: "Guarded Project",
            codeFolder: root.path,
            options: PromoteToProjectOptions(initializeGitRepo: false, seedProjectMemory: true, addAgentInstructions: true)
        )
        let destination = try service.validate(request)
        trackingFileManager.allowedDestination = destination.destinationURL.standardizedFileURL

        try service.prepareDestination(destination, sourceSession: session)
        _ = try service.createArtifacts(request: request, destination: destination)

        let gitMetadataURL = destination.destinationURL.appendingPathComponent(".git", isDirectory: true)
        try trackingFileManager.createDirectory(at: gitMetadataURL, withIntermediateDirectories: true)
        XCTAssertTrue(trackingFileManager.createFile(atPath: gitMetadataURL.appendingPathComponent("HEAD").path, contents: Data("ref: refs/heads/main\n".utf8)))
        XCTAssertFalse(trackingFileManager.createFile(atPath: root.appendingPathComponent("outside-git-metadata").path, contents: Data()))

        XCTAssertFalse(trackingFileManager.attemptedWriteURLs.isEmpty)
        XCTAssertEqual(trackingFileManager.rejectedWriteURLs.map(\.path), [root.appendingPathComponent("outside-git-metadata").standardizedFileURL.path])
        XCTAssertTrue(trackingFileManager.attemptedWriteURLs.allSatisfy { url in
            let path = url.standardizedFileURL.path
            return path == root.appendingPathComponent("outside-git-metadata").standardizedFileURL.path
                || path == destination.destinationURL.path
                || path.hasPrefix(destination.destinationURL.path + "/")
        })
    }

    // 2119: REQ-002.2.1
    func testEnabledContextArtifactsAreCreatedWithoutOverwritingExistingFiles() throws {
        let root = try temporaryDirectory(named: "PiNativePromoteArtifacts")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = PromoteToProjectService(fileManager: .default, now: fixedNow)
        let session = sourceSession()
        let request = PromoteToProjectRequest(
            sourceSession: session,
            projectName: "Context Artifacts",
            codeFolder: root.path,
            options: PromoteToProjectOptions(initializeGitRepo: false, seedProjectMemory: true, addAgentInstructions: true)
        )
        let destination = try service.validate(request)
        try service.prepareDestination(destination, sourceSession: session)
        let agentsURL = destination.destinationURL.appendingPathComponent("AGENTS.md")
        let planURL = destination.destinationURL.appendingPathComponent("docs/project-plan.md")
        try FileManager.default.createDirectory(at: planURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "existing agent instructions".write(to: agentsURL, atomically: true, encoding: .utf8)
        try "existing project plan".write(to: planURL, atomically: true, encoding: .utf8)

        let notes = try service.createArtifacts(request: request, destination: destination)

        XCTAssertTrue(notes.contains("Skipped existing AGENTS.md"))
        XCTAssertTrue(notes.contains("Skipped existing project-plan.md"))
        XCTAssertEqual(try String(contentsOf: agentsURL), "existing agent instructions")
        XCTAssertEqual(try String(contentsOf: planURL), "existing project plan")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.destinationURL.appendingPathComponent("docs/project-log.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.destinationURL.appendingPathComponent("promoted-chat.md").path))
    }

    @MainActor
    // 2119: REQ-002.1.2
    // 2119: REQ-002.1.5
    func testWorkflowUsesSettingsDefaultCodeFolderAndKeepsGeneratedFilesInsideDestination() async throws {
        let sandbox = try temporaryDirectory(named: "PiNativePromoteSettingsSandbox")
        let root = sandbox.appendingPathComponent("Code", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let siblingOutsideDestination = sandbox.appendingPathComponent("outside-destination.txt")
        try "outside sentinel".write(to: siblingOutsideDestination, atomically: true, encoding: .utf8)
        let existingCodeFolderSibling = root.appendingPathComponent("existing-user-project", isDirectory: true)
        try FileManager.default.createDirectory(at: existingCodeFolderSibling, withIntermediateDirectories: true)
        try "existing user project data".write(
            to: existingCodeFolderSibling.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o640],
            ofItemAtPath: existingCodeFolderSibling.appendingPathComponent("notes.txt").path
        )
        defer { try? FileManager.default.removeItem(at: sandbox) }
        UserDefaults.standard.set(root.path, forKey: "promote.defaultCodeFolder")
        UserDefaults.standard.set(false, forKey: "promote.initializeGitRepo")
        UserDefaults.standard.set(true, forKey: "promote.seedProjectMemory")
        UserDefaults.standard.set(true, forKey: "promote.addAgentInstructions")
        defer { UserDefaults.standard.removeObject(forKey: "promote.defaultCodeFolder") }
        let appModel = controlledAppModel()
        XCTAssertEqual(appModel.promoteDefaultCodeFolder, root.path)
        let source = sourceSession(name: "Settings Folder Source")
        defer {
            UserDefaults.standard.removeObject(forKey: "promote.initializeGitRepo")
            UserDefaults.standard.removeObject(forKey: "promote.seedProjectMemory")
            UserDefaults.standard.removeObject(forKey: "promote.addAgentInstructions")
        }
        let baselineOutsideDestination = try recursiveRelativePaths(in: sandbox)
        let baselineFileContents = try recursiveUTF8FileContents(in: sandbox)
        let baselineEntrySignatures = try recursiveEntrySignatures(in: sandbox)
        let workflow = PromoteToProjectWorkflowModel(
            session: source,
            codeFolder: appModel.promoteDefaultCodeFolder,
            options: appModel.promoteOptions
        )
        workflow.projectName = "Settings Folder Project"

        await workflow.start()

        let result = try XCTUnwrap(workflow.result)
        let destination = URL(fileURLWithPath: result.projectPath).standardizedFileURL
        XCTAssertEqual(destination.deletingLastPathComponent().path, root.standardizedFileURL.path)
        let afterPaths = try recursiveRelativePaths(in: sandbox)
        let afterFileContents = try recursiveUTF8FileContents(in: sandbox)
        let afterEntrySignatures = try recursiveEntrySignatures(in: sandbox)
        let destinationPrefix = "Code/settings-folder-project"
        let isInsideDestination: (String) -> Bool = { $0.hasPrefix(destinationPrefix + "/") || $0 == destinationPrefix }
        let newPathsOutsideDestination = afterPaths.subtracting(baselineOutsideDestination).filter { !isInsideDestination($0) }
        XCTAssertTrue(newPathsOutsideDestination.isEmpty, "Promotion wrote outside the derived destination: \(newPathsOutsideDestination.sorted())")
        let removedPathsOutsideDestination = baselineOutsideDestination.subtracting(afterPaths).filter { !isInsideDestination($0) }
        XCTAssertTrue(removedPathsOutsideDestination.isEmpty, "Promotion removed or moved entries outside the derived destination: \(removedPathsOutsideDestination.sorted())")
        let modifiedExistingFilesOutsideDestination = baselineFileContents.filter { relativePath, beforeContents in
            !isInsideDestination(relativePath) && afterFileContents[relativePath] != beforeContents
        }
        XCTAssertTrue(
            modifiedExistingFilesOutsideDestination.isEmpty,
            "Promotion modified existing files outside the derived destination: \(modifiedExistingFilesOutsideDestination.keys.sorted())"
        )
        let changedEntrySignaturesOutsideDestination = baselineEntrySignatures.filter { relativePath, beforeSignature in
            !isInsideDestination(relativePath) && afterEntrySignatures[relativePath] != beforeSignature
        }
        XCTAssertTrue(
            changedEntrySignaturesOutsideDestination.isEmpty,
            "Promotion changed entry types or permissions outside the derived destination: \(changedEntrySignaturesOutsideDestination.keys.sorted())"
        )
        XCTAssertEqual(try String(contentsOf: siblingOutsideDestination), "outside sentinel")
        XCTAssertEqual(
            try String(contentsOf: existingCodeFolderSibling.appendingPathComponent("notes.txt")),
            "existing user project data"
        )

        let generatedRelativePaths = [
            "README.md", ".pinative/promote-to-project.json", "AGENTS.md",
            "docs", "docs/project-plan.md", "docs/project-log.md", "promoted-chat.md"
        ]
        for relativePath in generatedRelativePaths {
            let generatedURL = destination.appendingPathComponent(relativePath)
            XCTAssertTrue(generatedURL.standardizedFileURL.path.hasPrefix(destination.path + "/") || generatedURL.standardizedFileURL.path == destination.path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: generatedURL.path), "Missing generated artifact: \(relativePath)")
        }

        let existingDestinationSentinel = destination.appendingPathComponent("existing-user-file.txt")
        try "preserve on reuse".write(to: existingDestinationSentinel, atomically: true, encoding: .utf8)
        let reuseWorkflow = PromoteToProjectWorkflowModel(
            session: source,
            codeFolder: appModel.promoteDefaultCodeFolder,
            options: appModel.promoteOptions
        )
        reuseWorkflow.projectName = "Settings Folder Project"

        // 2119: REQ-002.1.2
        await reuseWorkflow.start()

        XCTAssertEqual(reuseWorkflow.result?.projectPath, destination.path)
        XCTAssertEqual(try String(contentsOf: existingDestinationSentinel), "preserve on reuse")
    }

    @MainActor
    // 2119: REQ-002.2.1
    func testWorkflowCreatesOnlyTheSettingsEnabledContextArtifacts() async throws {
        let memoryRoot = try temporaryDirectory(named: "PiNativeMemoryOnly")
        let agentRoot = try temporaryDirectory(named: "PiNativeAgentOnly")
        defer {
            try? FileManager.default.removeItem(at: memoryRoot)
            try? FileManager.default.removeItem(at: agentRoot)
            UserDefaults.standard.removeObject(forKey: "promote.initializeGitRepo")
            UserDefaults.standard.removeObject(forKey: "promote.seedProjectMemory")
            UserDefaults.standard.removeObject(forKey: "promote.addAgentInstructions")
        }
        let source = sourceSession(name: "Settings Context Source")

        UserDefaults.standard.set(false, forKey: "promote.initializeGitRepo")
        UserDefaults.standard.set(true, forKey: "promote.seedProjectMemory")
        UserDefaults.standard.set(false, forKey: "promote.addAgentInstructions")
        let memorySettings = controlledAppModel()
        let memoryWorkflow = PromoteToProjectWorkflowModel(
            session: source,
            codeFolder: memoryRoot.path,
            options: memorySettings.promoteOptions
        )
        memoryWorkflow.projectName = "Memory Only"
        await memoryWorkflow.start()
        let memoryPath = try XCTUnwrap(memoryWorkflow.result?.projectPath)
        let memoryURL = URL(fileURLWithPath: memoryPath)
        let plan = try String(contentsOf: memoryURL.appendingPathComponent("docs/project-plan.md"))
        let log = try String(contentsOf: memoryURL.appendingPathComponent("docs/project-log.md"))
        XCTAssertTrue(plan.contains("# Project Plan"))
        XCTAssertTrue(plan.contains("Settings Context Source"))
        XCTAssertTrue(plan.contains("Treat the promoted chat transcript as the source plan"))
        XCTAssertTrue(log.contains("# Project Log"))
        XCTAssertTrue(log.contains(source.id.uuidString))
        XCTAssertFalse(FileManager.default.fileExists(atPath: memoryURL.appendingPathComponent("AGENTS.md").path))

        UserDefaults.standard.set(false, forKey: "promote.seedProjectMemory")
        UserDefaults.standard.set(true, forKey: "promote.addAgentInstructions")
        let agentSettings = controlledAppModel()
        let agentWorkflow = PromoteToProjectWorkflowModel(
            session: source,
            codeFolder: agentRoot.path,
            options: agentSettings.promoteOptions
        )
        agentWorkflow.projectName = "Agent Only"
        await agentWorkflow.start()
        let agentPath = try XCTUnwrap(agentWorkflow.result?.projectPath)
        let agentURL = URL(fileURLWithPath: agentPath)
        let agents = try String(contentsOf: agentURL.appendingPathComponent("AGENTS.md"))
        XCTAssertTrue(agents.contains("# Agent Instructions"))
        XCTAssertTrue(agents.contains("Keep durable project context in `docs/`"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: agentURL.appendingPathComponent("docs/project-plan.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: agentURL.appendingPathComponent("docs/project-log.md").path))
    }

    @MainActor
    // 2119: REQ-002.2.1
    func testSettingsDrivenWorkflowSkipsExistingContextArtifactsWithoutOverwriting() async throws {
        let root = try temporaryDirectory(named: "PiNativeSettingsNoOverwrite")
        defer {
            try? FileManager.default.removeItem(at: root)
            UserDefaults.standard.removeObject(forKey: "promote.initializeGitRepo")
            UserDefaults.standard.removeObject(forKey: "promote.seedProjectMemory")
            UserDefaults.standard.removeObject(forKey: "promote.addAgentInstructions")
        }
        UserDefaults.standard.set(false, forKey: "promote.initializeGitRepo")
        UserDefaults.standard.set(true, forKey: "promote.seedProjectMemory")
        UserDefaults.standard.set(true, forKey: "promote.addAgentInstructions")
        let settingsModel = controlledAppModel()
        let source = sourceSession(name: "No Overwrite Source")
        let service = PromoteToProjectService(fileManager: .default, now: fixedNow)
        let request = PromoteToProjectRequest(
            sourceSession: source,
            projectName: "No Overwrite Settings",
            codeFolder: root.path,
            options: settingsModel.promoteOptions
        )
        let destination = try service.validate(request)
        try service.prepareDestination(destination, sourceSession: source)
        let agentsURL = destination.destinationURL.appendingPathComponent("AGENTS.md")
        let planURL = destination.destinationURL.appendingPathComponent("docs/project-plan.md")
        let logURL = destination.destinationURL.appendingPathComponent("docs/project-log.md")
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "existing agent instructions".write(to: agentsURL, atomically: true, encoding: .utf8)
        try "existing project plan".write(to: planURL, atomically: true, encoding: .utf8)
        try "existing project log".write(to: logURL, atomically: true, encoding: .utf8)

        let workflow = PromoteToProjectWorkflowModel(session: source, codeFolder: root.path, options: settingsModel.promoteOptions, service: service)
        workflow.projectName = request.projectName
        await workflow.start()

        XCTAssertEqual(workflow.phase, .succeeded)
        XCTAssertEqual(try String(contentsOf: agentsURL), "existing agent instructions")
        XCTAssertEqual(try String(contentsOf: planURL), "existing project plan")
        XCTAssertEqual(try String(contentsOf: logURL), "existing project log")
        guard case .skipped(let detail) = workflow.steps.first(where: { $0.step == .createArtifacts })?.status else {
            return XCTFail("Expected existing artifacts to be reported as skipped")
        }
        XCTAssertTrue(detail.contains("Skipped existing AGENTS.md"))
        XCTAssertTrue(detail.contains("Skipped existing project-plan.md"))
        XCTAssertTrue(detail.contains("Skipped existing project-log.md"))
    }

    @MainActor
    // 2119: REQ-002.1.1
    // 2119: REQ-002.2.2
    // 2119: REQ-002.4.1
    func testNameOnlyWorkflowCreatesDocsProvenanceAndHandoffChat() async throws {
        setenv("PI_NATIVE_TEST_RPC_STALL", "1", 1)
        defer { unsetenv("PI_NATIVE_TEST_RPC_STALL") }
        let root = try temporaryDirectory(named: "PiNativePromoteWorkflow")
        defer { try? FileManager.default.removeItem(at: root) }
        let expectedTranscriptText = [
            "Build the workflow",
            "Implementation plan goes here",
            "Keep the migration reversible",
            "Add rollback checkpoints",
            "Verify every generated artifact",
            "Record the final handoff"
        ]
        let source = sourceSession(name: "Planning Chat", transcript: [
            .user(UserMessagePayload(text: expectedTranscriptText[0])),
            .assistantText(text: expectedTranscriptText[1]),
            .user(UserMessagePayload(text: expectedTranscriptText[2])),
            .assistantText(text: expectedTranscriptText[3]),
            .user(UserMessagePayload(text: expectedTranscriptText[4])),
            .assistantText(text: expectedTranscriptText[5])
        ])
        let workflow = PromoteToProjectWorkflowModel(
            session: source,
            codeFolder: root.path,
            options: PromoteToProjectOptions(initializeGitRepo: false, seedProjectMemory: false, addAgentInstructions: false)
        )
        workflow.projectName = "Name Only Project"

        await workflow.start()

        let result = try XCTUnwrap(workflow.result)
        XCTAssertEqual(workflow.phase, .succeeded)
        XCTAssertEqual(URL(fileURLWithPath: result.projectPath).lastPathComponent, "name-only-project")
        let provenance = try String(contentsOf: URL(fileURLWithPath: result.projectPath).appendingPathComponent("promoted-chat.md"))
        XCTAssertTrue(provenance.contains(source.id.uuidString))
        let timestampLine = try XCTUnwrap(provenance.split(separator: "\n").first { $0.contains("Promotion timestamp:") })
        let timestamp = timestampLine.replacingOccurrences(of: "- Promotion timestamp: ", with: "")
        XCTAssertNotNil(ISO8601DateFormatter().date(from: timestamp))
        XCTAssertTrue(provenance.contains("Cached transcript included"))
        for message in expectedTranscriptText {
            XCTAssertTrue(provenance.contains(message), "Provenance omitted cached transcript text: \(message)")
        }

        let appModel = controlledAppModel()
        appModel.standaloneSessions = [source]
        appModel.presentPromoteToProject(session: source)
        let projectID = appModel.completePromotion(projectPath: result.projectPath)
        XCTAssertEqual(appModel.selectedProjectID, projectID)
        let standardizedProjectPath = URL(fileURLWithPath: result.projectPath).standardizedFileURL.path
        XCTAssertEqual(appModel.selectedProject?.path, standardizedProjectPath)
        let addedProjects = appModel.projects.filter { $0.path == standardizedProjectPath }
        XCTAssertEqual(addedProjects.count, 1)
        XCTAssertEqual(addedProjects.first?.id, projectID)
        let selectedSession = try XCTUnwrap(appModel.selectedSession)
        XCTAssertNotEqual(selectedSession.id, source.id)
        XCTAssertEqual(appModel.selectedProject?.sessions.contains { $0.id == selectedSession.id }, true)
        let handoffPrompt = try XCTUnwrap(selectedSession.pendingInitialPrompt?.message)
        XCTAssertTrue(handoffPrompt.contains("Planning Chat"))
        XCTAssertTrue(handoffPrompt.contains("promoted from the Quick Chat planning conversation"))
        XCTAssertTrue(handoffPrompt.contains(URL(fileURLWithPath: result.projectPath).standardizedFileURL.path))
        XCTAssertTrue(handoffPrompt.contains("promoted-chat.md"))
        for message in expectedTranscriptText {
            XCTAssertTrue(handoffPrompt.contains(message), "Handoff omitted cached planning context: \(message)")
        }
    }

    @MainActor
    // 2119: REQ-002.4.1
    func testPromotionHandoffReusesExistingProjectAndDisplaysProjectScopedPlanningPrompt() throws {
        setenv("PI_NATIVE_MOCK_RPC_RESPONSE", "handoff mock response", 1)
        unsetenv("PI_NATIVE_TEST_RPC_STALL")
        defer { unsetenv("PI_NATIVE_MOCK_RPC_RESPONSE") }
        let root = try temporaryDirectory(named: "PiNativePromoteExistingProject")
        defer { try? FileManager.default.removeItem(at: root) }
        let existingSession = Session(name: "Existing project chat", status: .idle)
        let existingProject = Project(name: "Existing", path: root.path, sessions: [existingSession], diffStats: nil)
        let source = sourceSession(name: "Reusable Planning", transcript: [
            .user(UserMessagePayload(text: "reuse this promoted plan")),
            .assistantText(text: "implementation context")
        ])
        let appModel = controlledAppModel()
        appModel.projects = [existingProject]
        appModel.standaloneSessions = [source]
        appModel.presentPromoteToProject(session: source)

        let projectID = appModel.completePromotion(projectPath: root.path)

        XCTAssertEqual(projectID, existingProject.id)
        XCTAssertEqual(appModel.projects.filter { $0.path == root.standardizedFileURL.path }.count, 1)
        XCTAssertEqual(appModel.selectedProjectID, existingProject.id)
        let selectedSession = try XCTUnwrap(appModel.selectedSession)
        XCTAssertNotEqual(selectedSession.id, existingSession.id)
        XCTAssertNotEqual(selectedSession.id, source.id)
        XCTAssertEqual(appModel.selectedProject?.sessions.first?.id, selectedSession.id)
        let displayedUserText = appModel.activeConversationModel?.items.compactMap { item -> String? in
            if case .user(_, let payload) = item { return payload.text }
            return nil
        }.joined(separator: "\n") ?? ""
        XCTAssertTrue(displayedUserText.contains("Reusable Planning"))
        XCTAssertTrue(displayedUserText.contains("reuse this promoted plan"))
        XCTAssertTrue(displayedUserText.contains("implementation context"))
        XCTAssertTrue(displayedUserText.contains(root.standardizedFileURL.path))
        XCTAssertTrue(displayedUserText.contains("promoted-chat.md"))
    }

    @MainActor
    // 2119: REQ-002.2.2
    func testWorkflowRecordsEmptyTranscriptAvailabilityInProvenance() async throws {
        let root = try temporaryDirectory(named: "PiNativePromoteEmptyProvenance")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = sourceSession(name: "Empty Planning Chat", transcript: [])
        let workflow = PromoteToProjectWorkflowModel(
            session: source,
            codeFolder: root.path,
            options: PromoteToProjectOptions(initializeGitRepo: false, seedProjectMemory: false, addAgentInstructions: false)
        )
        workflow.projectName = "Empty Provenance Project"

        await workflow.start()

        let result = try XCTUnwrap(workflow.result)
        let provenance = try String(contentsOf: URL(fileURLWithPath: result.projectPath).appendingPathComponent("promoted-chat.md"))
        XCTAssertTrue(provenance.contains(source.id.uuidString))
        let timestampLine = try XCTUnwrap(provenance.split(separator: "\n").first { $0.contains("Promotion timestamp:") })
        let timestamp = String(timestampLine).replacingOccurrences(of: "- Promotion timestamp: ", with: "")
        XCTAssertNotEqual(timestamp, "")
        XCTAssertNotNil(ISO8601DateFormatter().date(from: timestamp))
        XCTAssertTrue(provenance.contains("No cached transcript available"))
        XCTAssertTrue(provenance.contains("No cached transcript was available when this project was promoted."))
    }

    @MainActor
    // 2119: REQ-002.3.3
    // 2119: REQ-002.4.2
    func testRetryAfterPartialFailureDoesNotOverwriteArtifactsDuplicateEntriesOrRegisterTwice() async throws {
        setenv("PI_NATIVE_TEST_RPC_STALL", "1", 1)
        defer { unsetenv("PI_NATIVE_TEST_RPC_STALL") }
        let root = try temporaryDirectory(named: "PiNativePromoteRetry")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = sourceSession(name: "Retry Source", transcript: [.user(UserMessagePayload(text: "retry transcript"))])
        var shouldFailAfterArtifacts = true
        var writeAttempts: [URL] = []
        let service = PromoteToProjectService(
            fileManager: .default,
            now: fixedNow,
            recordWrite: { writeAttempts.append($0.standardizedFileURL) },
            afterArtifactsCreated: {
                if shouldFailAfterArtifacts {
                    shouldFailAfterArtifacts = false
                    throw PromoteToProjectServiceError.cannotWriteArtifact("Injected partial failure after artifacts")
                }
            }
        )
        let request = PromoteToProjectRequest(
            sourceSession: source,
            projectName: "Retry Project",
            codeFolder: root.path,
            options: PromoteToProjectOptions(initializeGitRepo: false, seedProjectMemory: true, addAgentInstructions: true)
        )
        let destination = try service.validate(request)
        let readmeURL = destination.destinationURL.appendingPathComponent("README.md")
        let logURL = destination.destinationURL.appendingPathComponent("docs/project-log.md")
        let provenanceURL = destination.destinationURL.appendingPathComponent("promoted-chat.md")
        let agentsURL = destination.destinationURL.appendingPathComponent("AGENTS.md")
        let planURL = destination.destinationURL.appendingPathComponent("docs/project-plan.md")
        let markerURL = destination.destinationURL.appendingPathComponent(".pinative/promote-to-project.json")
        let appModel = controlledAppModel()
        appModel.standaloneSessions = [source]
        appModel.presentPromoteToProject(session: source)

        let workflow = PromoteToProjectWorkflowModel(session: source, codeFolder: root.path, options: request.options, service: service)
        workflow.projectName = request.projectName
        await workflow.start()

        guard case .failed(let firstFailure) = workflow.phase else {
            return XCTFail("Expected the first run to fail after creating partial artifacts")
        }
        XCTAssertTrue(firstFailure.contains("Injected partial failure"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: readmeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: provenanceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: agentsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: planURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))
        XCTAssertEqual(appModel.projects.filter { $0.path == destination.destinationURL.path }.count, 0)
        XCTAssertFalse(try XCTUnwrap(appModel.standaloneSessions.first { $0.id == source.id }).isArchived)
        let logAfterFailure = try String(contentsOf: logURL)
        let provenanceAfterFailure = try String(contentsOf: provenanceURL)
        let agentsAfterFailure = try String(contentsOf: agentsURL)
        let planAfterFailure = try String(contentsOf: planURL)
        let markerAfterFailure = try String(contentsOf: markerURL)
        let artifactURLs = [readmeURL, logURL, provenanceURL, agentsURL, planURL, markerURL].map { $0.standardizedFileURL }

        // Counterexample: a user edits a generated artifact between the failed attempt and the
        // retry. If retry ever overwrote existing artifacts, this hand-authored edit would be lost.
        let userEditedReadmeContents = "# Retry Project\n\nUser added deployment notes before retrying promotion."
        try userEditedReadmeContents.write(to: readmeURL, atomically: true, encoding: .utf8)
        let readmeModificationDateBeforeRetry = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: readmeURL.path)[.modificationDate] as? Date
        )
        writeAttempts.removeAll()

        await workflow.retry()

        let artifactWriteAttemptsDuringRetry = writeAttempts.filter { attemptedURL in
            artifactURLs.contains { $0.path == attemptedURL.path }
        }
        XCTAssertTrue(artifactWriteAttemptsDuringRetry.isEmpty, "Retry attempted to rewrite existing artifacts: \(artifactWriteAttemptsDuringRetry.map(\.path))")
        XCTAssertEqual(workflow.phase, .succeeded)

        // The user's hand-authored edit must survive retry untouched, both in content and on disk
        // (mtime unchanged proves the file was never reopened for writing, not just that its final
        // text happens to match).
        XCTAssertEqual(try String(contentsOf: readmeURL), userEditedReadmeContents, "Retry overwrote a user's manual edit to an existing generated artifact")
        let readmeModificationDateAfterRetry = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: readmeURL.path)[.modificationDate] as? Date
        )
        XCTAssertEqual(readmeModificationDateAfterRetry, readmeModificationDateBeforeRetry, "Retry rewrote README.md on disk even though its content was preserved")

        XCTAssertEqual(try String(contentsOf: logURL), logAfterFailure)
        XCTAssertEqual(try String(contentsOf: provenanceURL), provenanceAfterFailure)
        XCTAssertEqual(try String(contentsOf: agentsURL), agentsAfterFailure)
        XCTAssertEqual(try String(contentsOf: planURL), planAfterFailure)
        XCTAssertEqual(try String(contentsOf: markerURL), markerAfterFailure)

        // Duplication must be checked against every distinguishing field a duplicate retry could
        // append, not just the session ID: the log/provenance headers, the promotion timestamp
        // line, and the log's dated entry heading must each appear exactly once.
        let logAfterRetry = try String(contentsOf: logURL)
        let provenanceAfterRetry = try String(contentsOf: provenanceURL)
        XCTAssertEqual(logAfterRetry.components(separatedBy: "# Project Log").count - 1, 1, "project-log.md gained a duplicate document header")
        XCTAssertEqual(logAfterRetry.components(separatedBy: "— Promoted to Project").count - 1, 1, "project-log.md gained a duplicate dated entry")
        XCTAssertEqual(logAfterRetry.components(separatedBy: source.id.uuidString).count - 1, 1, "project-log.md gained a duplicate source session ID")
        XCTAssertEqual(provenanceAfterRetry.components(separatedBy: "- Promotion timestamp:").count - 1, 1, "promoted-chat.md gained a duplicate promotion timestamp")
        XCTAssertEqual(provenanceAfterRetry.components(separatedBy: source.id.uuidString).count - 1, 1, "promoted-chat.md gained a duplicate source session ID")

        // Registration idempotency: completing promotion twice for the same destination (the retry
        // path a user takes by re-running the workflow after it already succeeded once) must still
        // register exactly one project, not merely "exactly one project after a single call."
        let retryResult = try XCTUnwrap(workflow.result)
        let firstProjectID = appModel.completePromotion(projectPath: retryResult.projectPath)
        appModel.presentPromoteToProject(session: source)
        let secondProjectID = appModel.completePromotion(projectPath: retryResult.projectPath)
        XCTAssertEqual(firstProjectID, secondProjectID, "Re-registering the same destination must reuse the existing project rather than create a new one")
        let registeredProjects = appModel.projects.filter { $0.path == destination.destinationURL.path }
        XCTAssertEqual(registeredProjects.count, 1, "Registering the promoted destination twice must not create duplicate project entries")
        XCTAssertEqual(registeredProjects.first?.id, firstProjectID)
        XCTAssertTrue(try XCTUnwrap(appModel.standaloneSessions.first { $0.id == source.id }).isArchived)
    }

    @MainActor
    // 2119: REQ-002.4.2
    func testSuccessfulHandoffArchivesSourceQuickChatWhileRetainingRecoveryData() throws {
        setenv("PI_NATIVE_TEST_RPC_STALL", "1", 1)
        defer { unsetenv("PI_NATIVE_TEST_RPC_STALL") }
        let root = try temporaryDirectory(named: "PiNativePromoteArchive")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessionFile = root.appendingPathComponent("pinative-source-session.jsonl")
        try "source session data".write(to: sessionFile, atomically: true, encoding: .utf8)
        let source = sourceSession(
            name: "Archive Me",
            filePath: sessionFile.path,
            transcript: [.user(UserMessagePayload(text: "recover me later"))]
        )
        let appModel = controlledAppModel()
        appModel.standaloneSessions = [source]
        appModel.presentPromoteToProject(session: source)

        _ = appModel.completePromotion(projectPath: root.path)

        let archived = try XCTUnwrap(appModel.standaloneSessions.first { $0.id == source.id })
        XCTAssertTrue(archived.isArchived)
        XCTAssertEqual(archived.filePath, source.filePath)
        XCTAssertEqual(archived.cachedTranscript, source.cachedTranscript)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionFile.path))
        XCTAssertEqual(try String(contentsOf: sessionFile), "source session data")

        let persistedData = try XCTUnwrap(UserDefaults.standard.data(forKey: "sessions.standalone"))
        let persistedSessions = try JSONDecoder().decode([TestPersistedSession].self, from: persistedData)
        let recovered = try XCTUnwrap(persistedSessions.first { $0.id == source.id })
        XCTAssertTrue(recovered.isArchived)
        XCTAssertEqual(recovered.filePath, sessionFile.path)
        XCTAssertEqual(recovered.cachedTranscript, source.cachedTranscript)
        XCTAssertEqual(max(recovered.messageCount, recovered.cachedTranscript.count), source.cachedTranscript.count)

        let reloadedModel = AppModel()
        let recoveredChat = try XCTUnwrap(reloadedModel.archivedChats.first { $0.session.id == source.id }?.session)
        XCTAssertTrue(recoveredChat.isArchived)
        XCTAssertEqual(recoveredChat.filePath, sessionFile.path)
        XCTAssertEqual(recoveredChat.cachedTranscript, source.cachedTranscript)
        XCTAssertEqual(recoveredChat.messageCount, source.cachedTranscript.count)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionFile.path))
        XCTAssertEqual(try String(contentsOf: sessionFile), "source session data")
    }

    @MainActor
    // 2119: REQ-002.1.4
    func testMissingPersistedDefaultInitializesProjectsFolderUnderHome() throws {
        let tempHome = try temporaryDirectory(named: "PiNativeDefaultHome")
        setenv("PI_NATIVE_TEST_RPC_STALL", "1", 1)
        setenv("PI_NATIVE_TEST_HOME", tempHome.path, 1)
        UserDefaults.standard.removeObject(forKey: "projects.paths")
        UserDefaults.standard.removeObject(forKey: "projects.selectedPath")
        UserDefaults.standard.removeObject(forKey: "sessions.standalone")
        UserDefaults.standard.removeObject(forKey: "promote.defaultCodeFolder")
        defer {
            unsetenv("PI_NATIVE_TEST_RPC_STALL")
            unsetenv("PI_NATIVE_TEST_HOME")
            UserDefaults.standard.removeObject(forKey: "projects.paths")
            UserDefaults.standard.removeObject(forKey: "projects.selectedPath")
            UserDefaults.standard.removeObject(forKey: "sessions.standalone")
            try? FileManager.default.removeItem(at: tempHome)
        }

        let model = AppModel()

        XCTAssertEqual(model.promoteDefaultCodeFolder, "~/Projects")
        var isDirectory: ObjCBool = false
        let projectsURL = tempHome.appendingPathComponent("Projects", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectsURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    @MainActor
    // 2119: REQ-002.1.4
    func testPersistedProjectFolderOverridesProjectsDefaultAndIsCreated() throws {
        let tempHome = try temporaryDirectory(named: "PiNativePersistedDefaultHome")
        let persistedFolder = "~/Custom Workspace"
        let customWorkspaceURL = tempHome.appendingPathComponent("Custom Workspace", isDirectory: true)
        let projectsURL = tempHome.appendingPathComponent("Projects", isDirectory: true)
        setenv("PI_NATIVE_TEST_RPC_STALL", "1", 1)
        setenv("PI_NATIVE_TEST_HOME", tempHome.path, 1)
        UserDefaults.standard.set(persistedFolder, forKey: "promote.defaultCodeFolder")
        defer {
            unsetenv("PI_NATIVE_TEST_RPC_STALL")
            unsetenv("PI_NATIVE_TEST_HOME")
            UserDefaults.standard.removeObject(forKey: "promote.defaultCodeFolder")
            try? FileManager.default.removeItem(at: tempHome)
        }

        let model = AppModel()

        XCTAssertEqual(model.promoteDefaultCodeFolder, persistedFolder)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: customWorkspaceURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectsURL.path))
    }

}

private func temporaryDirectory(named prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func fixedNow() -> Date {
    Date(timeIntervalSince1970: 0)
}

private func recursiveRelativePaths(in root: URL) throws -> Set<String> {
    let root = root.standardizedFileURL
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
    var paths = Set<String>()
    for case let url as URL in enumerator {
        let path = url.standardizedFileURL.path
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard path.hasPrefix(prefix) else { continue }
        paths.insert(String(path.dropFirst(prefix.count)))
    }
    return paths
}

private func recursiveUTF8FileContents(in root: URL) throws -> [String: String] {
    let root = root.standardizedFileURL
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
    var contents: [String: String] = [:]
    let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
    for case let url as URL in enumerator {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { continue }
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(prefix) else { continue }
        contents[String(path.dropFirst(prefix.count))] = try String(contentsOf: url)
    }
    return contents
}

private struct FilesystemEntrySignature: Equatable {
    var type: String
    var posixPermissions: Int
}

private func recursiveEntrySignatures(in root: URL) throws -> [String: FilesystemEntrySignature] {
    let root = root.standardizedFileURL
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [:] }
    var signatures: [String: FilesystemEntrySignature] = [:]
    let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
    for case let url as URL in enumerator {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(prefix) else { continue }
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        signatures[String(path.dropFirst(prefix.count))] = FilesystemEntrySignature(
            type: String(describing: attributes[.type] ?? "unknown"),
            posixPermissions: (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
        )
    }
    return signatures
}

private final class DirectoryInspectionFailingFileManager: FileManager, @unchecked Sendable {
    var failingDirectoryPath: String?

    override func contentsOfDirectory(atPath path: String) throws -> [String] {
        if path == failingDirectoryPath {
            throw CocoaError(.fileReadNoPermission)
        }
        return try super.contentsOfDirectory(atPath: path)
    }
}

private struct TestPersistedSession: Decodable {
    var id: UUID
    var filePath: String?
    var messageCount: Int
    var isArchived: Bool
    var cachedTranscript: [TranscriptItem]
}

private final class DestinationRejectingFileManager: FileManager, @unchecked Sendable {
    var allowedDestination: URL?
    private(set) var attemptedWriteURLs: [URL] = []
    private(set) var rejectedWriteURLs: [URL] = []

    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey: Any]? = nil) throws {
        try recordAndValidateWrite(to: url)
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }

    override func createFile(atPath path: String, contents data: Data?, attributes attr: [FileAttributeKey: Any]? = nil) -> Bool {
        do {
            try recordAndValidateWrite(to: URL(fileURLWithPath: path))
        } catch {
            return false
        }
        return super.createFile(atPath: path, contents: data, attributes: attr)
    }

    private func recordAndValidateWrite(to url: URL) throws {
        let standardizedURL = url.standardizedFileURL
        attemptedWriteURLs.append(standardizedURL)
        guard let allowedDestination else { return }
        let path = standardizedURL.path
        let allowedPath = allowedDestination.standardizedFileURL.path
        guard path == allowedPath || path.hasPrefix(allowedPath + "/") else {
            rejectedWriteURLs.append(standardizedURL)
            throw CocoaError(.fileWriteNoPermission)
        }
    }
}

private func sourceSession(
    name: String = "Source Chat",
    filePath: String? = nil,
    transcript: [TranscriptItem] = [.user(UserMessagePayload(text: "Build the thing"))]
) -> Session {
    Session(
        id: UUID(),
        name: name,
        status: .idle,
        filePath: filePath,
        updatedAt: Date(timeIntervalSince1970: 10),
        messageCount: transcript.count,
        cachedTranscript: transcript
    )
}

@MainActor
private func controlledAppModel() -> AppModel {
    UserDefaults.standard.removeObject(forKey: "projects.paths")
    UserDefaults.standard.removeObject(forKey: "projects.selectedPath")
    UserDefaults.standard.removeObject(forKey: "sessions.standalone")
    let model = AppModel()
    model.projects = []
    model.standaloneSessions = []
    model.selectedProjectID = nil
    model.selectedSessionID = nil
    model.activeConversationModel = nil
    model.activeConversationIsRunning = false
    return model
}
