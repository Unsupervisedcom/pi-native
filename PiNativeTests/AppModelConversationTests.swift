import XCTest
@testable import PiNative

@MainActor
final class AppModelConversationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        setenv("PI_NATIVE_TEST_RPC_STALL", "1", 1)
        UserDefaults.standard.removeObject(forKey: "projects.paths")
        UserDefaults.standard.removeObject(forKey: "projects.selectedPath")
        UserDefaults.standard.removeObject(forKey: "sessions.standalone")
    }

    override func tearDown() {
        unsetenv("PI_NATIVE_TEST_RPC_STALL")
        UserDefaults.standard.removeObject(forKey: "projects.paths")
        UserDefaults.standard.removeObject(forKey: "projects.selectedPath")
        UserDefaults.standard.removeObject(forKey: "sessions.standalone")
        super.tearDown()
    }

    func testSelectedChatSameSessionResyncDisplaysUpdatedAvailableTranscript() throws {
        let root = try temporaryDirectory(named: "PiNativeSelectedResync")
        defer { try? FileManager.default.removeItem(at: root) }
        let session = Session(
            name: "selected resync chat",
            status: .idle,
            filePath: "/tmp/pinative-selected-resync.jsonl",
            cachedTranscript: [.user(UserMessagePayload(text: "initial selected transcript"))]
        )
        let project = Project(name: "Selected Resync", path: root.path, sessions: [session], diffStats: nil)
        let model = AppModel()
        model.projects = [project]

        model.select(sessionID: session.id, in: project.id)
        XCTAssertEqual(model.activeConversationModel?.items, session.cachedTranscript)

        let updatedTranscript: [TranscriptItem] = [
            .user(UserMessagePayload(text: "updated selected transcript first")),
            .assistantText(text: "updated selected transcript latest")
        ]
        model.projects[0].sessions[0].cachedTranscript = updatedTranscript
        model.projects[0].sessions[0].messageCount = updatedTranscript.count
        model.select(sessionID: session.id, in: project.id)

        XCTAssertEqual(model.selectedSessionID, session.id)
        XCTAssertEqual(model.activeConversationModel?.items, updatedTranscript)
    }

    func testProjectRowWithOnlyPinnedOrArchivedChatsDoesNotSelectThoseChats() throws {
        let root = try temporaryDirectory(named: "PiNativePinnedOnlyProject")
        defer { try? FileManager.default.removeItem(at: root) }
        let pinned = Session(name: "only pinned chat", status: .idle, updatedAt: Date(timeIntervalSince1970: 20), isPinned: true)
        let archived = Session(name: "only archived chat", status: .idle, updatedAt: Date(timeIntervalSince1970: 30), isArchived: true)
        let project = Project(name: "Pinned Only", path: root.path, sessions: [pinned, archived], diffStats: nil)
        let model = AppModel()
        model.projects = [project]
        model.selectedProjectID = nil
        model.selectedSessionID = nil

        // 2119: REQ-003.3.2
        // 2119: REQ-003.3.3
        model.select(projectID: project.id)

        XCTAssertEqual(model.selectedProjectID, project.id)
        XCTAssertNil(model.selectedSessionID)
        XCTAssertNotEqual(model.selectedSessionID, pinned.id)
        XCTAssertNotEqual(model.selectedSessionID, archived.id)
    }

    // 2119: REQ-003.3.1
    func testProjectRowRejectsNewerArchivedChatInFavorOfNewestVisibleUnpinnedChat() throws {
        let root = try temporaryDirectory(named: "PiNativeArchivedNewerProject")
        defer { try? FileManager.default.removeItem(at: root) }
        let olderVisible = Session(name: "older visible", status: .idle, updatedAt: Date(timeIntervalSince1970: 10))
        let newestVisible = Session(name: "newest visible", status: .idle, updatedAt: Date(timeIntervalSince1970: 20))
        let newerArchived = Session(name: "newer archived", status: .idle, updatedAt: Date(timeIntervalSince1970: 30), isArchived: true)
        let project = Project(name: "Archived Newer", path: root.path, sessions: [olderVisible, newerArchived, newestVisible], diffStats: nil)
        let model = AppModel()
        model.projects = [project]
        model.selectedProjectID = nil
        model.selectedSessionID = nil

        model.select(projectID: project.id)

        XCTAssertEqual(model.selectedProjectID, project.id)
        XCTAssertEqual(model.selectedSessionID, newestVisible.id)
        XCTAssertNotEqual(model.selectedSessionID, newerArchived.id)
        XCTAssertNotEqual(model.selectedSessionID, olderVisible.id)
    }

    // 2119: REQ-003.3.1
    func testProjectRowSelectsNewestVisibleUnpinnedChatLoadedFromPiSessions() throws {
        let tempHome = try temporaryDirectory(named: "PiNativeSessionSourceHome")
        let projectRoot = try temporaryDirectory(named: "PiNativeSessionSourceProject")
        defer {
            unsetenv("PI_NATIVE_RESET_PROJECTS")
            unsetenv("PI_NATIVE_TEST_PROJECT_PATH")
            unsetenv("PI_NATIVE_TEST_HOME")
            try? FileManager.default.removeItem(at: tempHome)
            try? FileManager.default.removeItem(at: projectRoot)
        }
        setenv("PI_NATIVE_RESET_PROJECTS", "1", 1)
        setenv("PI_NATIVE_TEST_PROJECT_PATH", projectRoot.path, 1)
        setenv("PI_NATIVE_TEST_HOME", tempHome.path, 1)
        let encodedProjectPath = projectRoot.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "/", with: "-")
        let sessionDirectory = tempHome.appendingPathComponent(".pi/agent/sessions/--\(encodedProjectPath)--", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)

        func writeSession(name: String, timestamp: String) throws {
            let fileURL = sessionDirectory.appendingPathComponent("\(name.replacingOccurrences(of: " ", with: "-"))-\(UUID().uuidString).jsonl")
            try """
            {"type":"session_info","name":"\(name)","timestamp":"\(timestamp)"}
            {"type":"message","timestamp":"\(timestamp)","message":{"role":"user","content":"\(name) content"}}
            """.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        try writeSession(name: "oldest loaded visible", timestamp: "2026-08-05T12:00:00.000Z")
        try writeSession(name: "newest loaded visible", timestamp: "2026-08-05T12:01:00.000Z")
        try writeSession(name: "newest loaded pinned", timestamp: "2026-08-05T12:02:00.000Z")

        let model = AppModel()
        let project = try XCTUnwrap(model.projects.first)
        let pinned = try XCTUnwrap(project.sessions.first(where: { $0.name == "newest loaded pinned" }))
        model.setSessionPinned(true, sessionID: pinned.id, in: project.id)
        model.selectedProjectID = nil
        model.selectedSessionID = nil

        model.select(projectID: project.id)

        XCTAssertEqual(model.selectedProjectID, project.id)
        XCTAssertEqual(model.selectedSession?.name, "newest loaded visible")
        XCTAssertNotEqual(model.selectedSessionID, pinned.id)
    }

    func testOpeningArchivedChatsWithNoArchivedSessionsShowsEmptyArchiveModel() {
        let model = AppModel()
        let selected = Session(name: "Visible selected", status: .idle)
        let project = Project(name: "Visible Project", path: "/tmp/visible", sessions: [selected], diffStats: nil)
        model.projects = [project]
        model.standaloneSessions = [Session(name: "Quick visible", status: .idle)]
        model.select(sessionID: selected.id, in: project.id)

        // 2119: REQ-013.1.2
        model.openRightPane(.archivedChats)

        XCTAssertTrue(model.isRightPaneOpen)
        XCTAssertEqual(model.rightPaneMode, .archivedChats)
        XCTAssertTrue(model.archivedChats.isEmpty)
        XCTAssertEqual(model.selectedSessionID, selected.id)
    }

    func testArchivedChatsListAndRestorePreserveSelectionAndMetadata() throws {
        let root = try temporaryDirectory(named: "PiNativeArchivedChats")
        defer { try? FileManager.default.removeItem(at: root) }
        let projectChat = Session(name: "Project archive", status: .idle, filePath: root.appendingPathComponent("project.jsonl").path, updatedAt: Date(timeIntervalSince1970: 20), messageCount: 2, isArchived: true, isPinned: true, cachedTranscript: [.user(UserMessagePayload(text: "project"))])
        let quickChat = Session(name: "Quick archive", status: .idle, filePath: root.appendingPathComponent("quick.jsonl").path, updatedAt: Date(timeIntervalSince1970: 30), messageCount: 3, isArchived: true, cachedTranscript: [.user(UserMessagePayload(text: "quick"))])
        let selected = Session(name: "Selected", status: .idle)
        let project = Project(name: "Archive Project", path: root.path, sessions: [projectChat, selected], diffStats: nil)
        let model = AppModel()
        model.projects = [project]
        model.standaloneSessions = [quickChat]
        model.select(sessionID: selected.id, in: project.id)

        // 2119: REQ-013.1.1
        // 2119: REQ-013.1.3
        model.openRightPane(.archivedChats)
        XCTAssertEqual(model.archivedChats.map(\.session.id), [quickChat.id, projectChat.id])
        XCTAssertEqual(model.archivedChats[0].session.name, "Quick archive")
        XCTAssertNil(model.archivedChats[0].projectID)
        XCTAssertNil(model.archivedChats[0].projectName)
        XCTAssertEqual(model.archivedChats[0].session.messageCount, 3)
        XCTAssertEqual(model.archivedChats[1].session.name, "Project archive")
        XCTAssertEqual(model.archivedChats[1].projectID, project.id)
        XCTAssertEqual(model.archivedChats[1].projectName, "Archive Project")
        XCTAssertEqual(model.archivedChats[1].session.messageCount, 2)
        XCTAssertEqual(model.selectedSessionID, selected.id)

        // 2119: REQ-013.2.1
        // 2119: REQ-013.2.2
        // 2119: REQ-013.3.1
        model.unarchiveSession(sessionID: projectChat.id, in: project.id)
        let restored = try XCTUnwrap(model.projects[0].sessions.first { $0.id == projectChat.id })
        XCTAssertFalse(restored.isArchived)
        XCTAssertTrue(restored.isPinned)
        XCTAssertEqual(restored.filePath, projectChat.filePath)
        XCTAssertEqual(restored.cachedTranscript, projectChat.cachedTranscript)
        XCTAssertFalse(model.archivedChats.contains { $0.session.id == projectChat.id })
        XCTAssertTrue(model.pinnedSessions.contains { $0.session.id == projectChat.id && $0.projectID == project.id })
        XCTAssertEqual(model.selectedSessionID, selected.id)

        // 2119: REQ-013.2.1
        model.unarchiveSession(sessionID: quickChat.id, in: nil)
        let restoredQuick = try XCTUnwrap(model.standaloneSessions.first { $0.id == quickChat.id })
        XCTAssertFalse(restoredQuick.isArchived)
        XCTAssertFalse(restoredQuick.isPinned)
        XCTAssertTrue(model.visibleSessionShortcuts.contains { $0.projectID == nil && $0.session.id == quickChat.id })
        XCTAssertFalse(model.pinnedSessions.contains { $0.session.id == quickChat.id })
        XCTAssertFalse(model.projects[0].sessions.contains { $0.id == quickChat.id })
    }

    func testRestoringArchivedChatsReturnsThemToSectionFromAssociationAndPinnedState() throws {
        let root = try temporaryDirectory(named: "PiNativeRestoreSections")
        defer { try? FileManager.default.removeItem(at: root) }
        let unpinnedProjectChat = Session(name: "Project unpinned archive", status: .idle, updatedAt: Date(timeIntervalSince1970: 10), isArchived: true)
        let pinnedQuickChat = Session(name: "Quick pinned archive", status: .idle, updatedAt: Date(timeIntervalSince1970: 20), isArchived: true, isPinned: true)
        let project = Project(name: "Restore Section Project", path: root.path, sessions: [unpinnedProjectChat], diffStats: nil)
        let model = AppModel()
        model.projects = [project]
        model.standaloneSessions = [pinnedQuickChat]

        // 2119: REQ-013.2.1
        model.unarchiveSession(sessionID: unpinnedProjectChat.id, in: project.id)
        model.unarchiveSession(sessionID: pinnedQuickChat.id, in: nil)

        XCTAssertFalse(model.archivedChats.contains { $0.session.id == unpinnedProjectChat.id })
        XCTAssertFalse(model.archivedChats.contains { $0.session.id == pinnedQuickChat.id })
        XCTAssertTrue(model.visibleSessionShortcuts.contains { $0.projectID == project.id && $0.session.id == unpinnedProjectChat.id })
        XCTAssertFalse(model.pinnedSessions.contains { $0.session.id == unpinnedProjectChat.id })
        XCTAssertTrue(model.pinnedSessions.contains { $0.projectID == nil && $0.session.id == pinnedQuickChat.id })
        XCTAssertTrue(model.standaloneSessions.contains { $0.id == pinnedQuickChat.id && $0.isPinned && !$0.isArchived })
        XCTAssertFalse(model.projects[0].sessions.contains { $0.id == pinnedQuickChat.id })
    }

    func testArchivePreservesIdentityAssociationFileTranscriptAndPinnedState() throws {
        let root = try temporaryDirectory(named: "PiNativeArchivePreservation")
        defer { try? FileManager.default.removeItem(at: root) }
        let projectChat = Session(name: "Project to archive", status: .idle, filePath: root.appendingPathComponent("project-archive.jsonl").path, updatedAt: Date(timeIntervalSince1970: 10), messageCount: 1, isPinned: true, cachedTranscript: [.user(UserMessagePayload(text: "project archive"))])
        let quickChat = Session(name: "Quick to archive", status: .idle, filePath: root.appendingPathComponent("quick-archive.jsonl").path, updatedAt: Date(timeIntervalSince1970: 20), messageCount: 1, cachedTranscript: [.user(UserMessagePayload(text: "quick archive"))])
        let project = Project(name: "Archive Preservation Project", path: root.path, sessions: [projectChat], diffStats: nil)
        let model = AppModel()
        model.projects = [project]
        model.standaloneSessions = [quickChat]

        // 2119: REQ-013.3.1
        model.archiveSession(sessionID: projectChat.id, in: project.id)
        model.archiveSession(sessionID: quickChat.id, in: nil)

        let archivedProject = try XCTUnwrap(model.projects[0].sessions.first { $0.id == projectChat.id })
        XCTAssertTrue(archivedProject.isArchived)
        XCTAssertTrue(archivedProject.isPinned)
        XCTAssertEqual(archivedProject.filePath, projectChat.filePath)
        XCTAssertEqual(archivedProject.cachedTranscript, projectChat.cachedTranscript)
        XCTAssertFalse(model.standaloneSessions.contains { $0.id == projectChat.id })

        let archivedQuick = try XCTUnwrap(model.standaloneSessions.first { $0.id == quickChat.id })
        XCTAssertTrue(archivedQuick.isArchived)
        XCTAssertFalse(archivedQuick.isPinned)
        XCTAssertEqual(archivedQuick.filePath, quickChat.filePath)
        XCTAssertEqual(archivedQuick.cachedTranscript, quickChat.cachedTranscript)
        XCTAssertFalse(model.projects[0].sessions.contains { $0.id == quickChat.id })
    }

    func testArchivedAndRestoredChatsPersistAcrossRelaunch() throws {
        UserDefaults.standard.removeObject(forKey: "sessions.standalone")
        let root = try temporaryDirectory(named: "PiNativeArchivePersistenceProject")
        defer { try? FileManager.default.removeItem(at: root) }
        UserDefaults.standard.set([root.path], forKey: "projects.paths")
        let quickSource = Session(name: "Persisted archived quick chat", status: .idle, filePath: "/tmp/persisted-archive.jsonl", updatedAt: Date(timeIntervalSince1970: 40), messageCount: 1, cachedTranscript: [.user(UserMessagePayload(text: "persist quick"))])
        let projectSource = Session(name: "Persisted archived project chat", status: .idle, filePath: root.appendingPathComponent("persisted-project.jsonl").path, updatedAt: Date(timeIntervalSince1970: 50), messageCount: 1, cachedTranscript: [.user(UserMessagePayload(text: "persist project"))])
        let model = AppModel()
        let project = Project(name: "Archive Persistence Project", path: root.path, sessions: [projectSource], diffStats: nil)
        model.projects = [project]
        model.standaloneSessions = [quickSource]

        // 2119: REQ-013.3.2
        model.archiveSession(sessionID: quickSource.id, in: nil)
        model.archiveSession(sessionID: projectSource.id, in: project.id)
        let relaunchedArchived = AppModel()
        XCTAssertTrue(relaunchedArchived.archivedChats.contains { $0.projectID == nil && $0.session.id == quickSource.id })
        XCTAssertTrue(relaunchedArchived.archivedChats.contains { $0.projectID == relaunchedArchived.projects.first?.id && $0.session.id == projectSource.id })

        relaunchedArchived.unarchiveSession(sessionID: quickSource.id, in: nil)
        let relaunchedProjectID = try XCTUnwrap(relaunchedArchived.projects.first?.id)
        relaunchedArchived.unarchiveSession(sessionID: projectSource.id, in: relaunchedProjectID)
        let relaunchedRestored = AppModel()
        let restoredQuick = try XCTUnwrap(relaunchedRestored.standaloneSessions.first { $0.id == quickSource.id })
        XCTAssertFalse(restoredQuick.isArchived)
        XCTAssertEqual(restoredQuick.filePath, quickSource.filePath)
        XCTAssertEqual(restoredQuick.cachedTranscript, quickSource.cachedTranscript)
        let restoredProject = try XCTUnwrap(relaunchedRestored.projects.first?.sessions.first { $0.id == projectSource.id })
        XCTAssertFalse(restoredProject.isArchived)
        XCTAssertEqual(restoredProject.filePath, projectSource.filePath)
        XCTAssertEqual(restoredProject.cachedTranscript, projectSource.cachedTranscript)
    }

    func testShowPendingChangesOpensProjectReviewWithoutChangingSelectedConversation() throws {
        let firstRoot = try temporaryDirectory(named: "PiNativePendingChangesContextFirst")
        let secondRoot = try temporaryDirectory(named: "PiNativePendingChangesContextSecond")
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }
        let selected = Session(name: "Selected chat", status: .idle)
        let contextMenuChat = Session(name: "Context chat", status: .idle)
        let selectedProject = Project(name: "Selected Project", path: firstRoot.path, sessions: [selected], diffStats: nil)
        let contextProject = Project(name: "Context Project", path: secondRoot.path, sessions: [contextMenuChat], diffStats: nil)
        let model = AppModel()
        model.projects = [selectedProject, contextProject]
        model.select(sessionID: selected.id, in: selectedProject.id)

        // 2119: REQ-012.1.1
        // 2119: REQ-012.1.2
        model.showPendingChanges(projectID: contextProject.id)

        XCTAssertTrue(model.isRightPaneOpen)
        XCTAssertEqual(model.rightPaneMode, .review)
        XCTAssertEqual(model.reviewProjectID, contextProject.id)
        XCTAssertEqual(model.reviewProject?.path, secondRoot.path)
        XCTAssertEqual(model.selectedProjectID, selectedProject.id)
        XCTAssertEqual(model.selectedSessionID, selected.id)
    }

    func testDiffModelParsesPendingGitWorkAndRefreshReplacesResult() async throws {
        let root = try temporaryDirectory(named: "PiNativePendingChangesGit")
        defer { try? FileManager.default.removeItem(at: root) }
        try runGit(["init", "-b", "main"], in: root)
        try runGit(["config", "user.email", "test@example.com"], in: root)
        try runGit(["config", "user.name", "Test User"], in: root)
        try "one\ntwo\nthree\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try "staged original\nstaged removed\n".write(to: root.appendingPathComponent("staged.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt", "staged.txt"], in: root)
        try runGit(["commit", "-m", "initial"], in: root)
        try "one\ntwo changed\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try "staged replacement\n".write(to: root.appendingPathComponent("staged.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "staged.txt"], in: root)
        try "alpha\nbeta\n".write(to: root.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)

        let model = DiffModel()
        // 2119: REQ-012.2.1
        model.refresh(projectPath: root.path)
        try await waitForDiffModel(model)
        var summary = try XCTUnwrap(model.summary)
        XCTAssertEqual(summary.branchLine, "main")
        XCTAssertEqual(summary.changedFileCount, 3)
        XCTAssertEqual(summary.additions, 5)
        XCTAssertEqual(summary.deletions, 4)
        XCTAssertEqual(summary.files.first { $0.path == "tracked.txt" }?.status, "M")
        XCTAssertEqual(summary.files.first { $0.path == "tracked.txt" }?.additions, 1)
        XCTAssertEqual(summary.files.first { $0.path == "tracked.txt" }?.deletions, 2)
        XCTAssertEqual(summary.files.first { $0.path == "staged.txt" }?.status, "M")
        XCTAssertEqual(summary.files.first { $0.path == "staged.txt" }?.additions, 1)
        XCTAssertEqual(summary.files.first { $0.path == "staged.txt" }?.deletions, 2)
        XCTAssertEqual(summary.files.first { $0.path == "new.txt" }?.status, "??")
        XCTAssertEqual(summary.files.first { $0.path == "new.txt" }?.additions, 3)

        try "one\ntwo changed\nthree restored\nfour new\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["restore", "--staged", "--worktree", "staged.txt"], in: root)
        // 2119: REQ-012.3.1
        model.refresh(projectPath: root.path)
        try await waitForDiffModel(model)
        summary = try XCTUnwrap(model.summary)
        XCTAssertEqual(summary.changedFileCount, 2)
        XCTAssertEqual(summary.files.filter { $0.path == "tracked.txt" }.count, 1)
        XCTAssertFalse(summary.files.contains { $0.path == "staged.txt" })
        XCTAssertEqual(summary.files.first { $0.path == "tracked.txt" }?.additions, 3)
        XCTAssertEqual(summary.files.first { $0.path == "tracked.txt" }?.deletions, 2)
    }

    func testDiffModelReportsDistinctLoadingCleanNoProjectAndFailureStates() async throws {
        let cleanRoot = try temporaryDirectory(named: "PiNativePendingChangesClean")
        let nonGitRoot = try temporaryDirectory(named: "PiNativePendingChangesFailure")
        defer {
            try? FileManager.default.removeItem(at: cleanRoot)
            try? FileManager.default.removeItem(at: nonGitRoot)
        }
        try runGit(["init"], in: cleanRoot)
        try runGit(["config", "user.email", "test@example.com"], in: cleanRoot)
        try runGit(["config", "user.name", "Test User"], in: cleanRoot)
        try "clean\n".write(to: cleanRoot.appendingPathComponent("clean.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "clean.txt"], in: cleanRoot)
        try runGit(["commit", "-m", "clean"], in: cleanRoot)

        let noProjectModel = DiffModel()
        XCTAssertNil(noProjectModel.summary)
        XCTAssertFalse(noProjectModel.hasLoadedOnce)
        XCTAssertFalse(noProjectModel.isLoading)

        let cleanModel = DiffModel()
        cleanModel.refresh(projectPath: cleanRoot.path)
        XCTAssertTrue(cleanModel.isLoading)
        XCTAssertFalse(cleanModel.hasLoadedOnce)
        try await waitForDiffModel(cleanModel)
        XCTAssertTrue(try XCTUnwrap(cleanModel.summary).files.isEmpty)
        XCTAssertNil(cleanModel.errorMessage)

        let failureModel = DiffModel()
        failureModel.refresh(projectPath: nonGitRoot.path)
        try await waitForDiffModel(failureModel)
        XCTAssertNil(failureModel.summary)
        XCTAssertNotNil(failureModel.errorMessage)
    }

    func testSwitchingPendingChangesProjectsClearsPriorSummaryBeforeLoading() async throws {
        let firstProject = try temporaryDirectory(named: "PiNativePendingChangesFirst")
        let secondProject = try temporaryDirectory(named: "PiNativePendingChangesSecond")
        defer {
            try? FileManager.default.removeItem(at: firstProject)
            try? FileManager.default.removeItem(at: secondProject)
        }
        try runGit(["init", "-b", "main"], in: firstProject)
        try "first\n".write(to: firstProject.appendingPathComponent("first-only.swift"), atomically: true, encoding: .utf8)

        let model = DiffModel()
        model.refresh(projectPath: firstProject.path)
        try await waitForDiffModel(model)
        XCTAssertEqual(model.summary?.files.first?.path, "first-only.swift")

        // 2119: REQ-012.2.3
        model.refresh(projectPath: secondProject.path)

        XCTAssertNil(model.summary, "A prior project's result must not be displayed while the new project loads.")
        XCTAssertFalse(model.hasLoadedOnce)
    }
}

private func temporaryDirectory(named prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func runGit(_ arguments: [String], in directory: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", directory.path] + arguments
    let stderr = Pipe()
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw XCTSkip("git \(arguments.joined(separator: " ")) failed: \(message)")
    }
}

@MainActor
private func waitForDiffModel(_ model: DiffModel, timeout: TimeInterval = 5) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while model.isLoading || !model.hasLoadedOnce {
        if Date() > deadline {
            XCTFail("Timed out waiting for DiffModel refresh")
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}
