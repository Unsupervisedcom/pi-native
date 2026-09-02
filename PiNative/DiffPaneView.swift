import SwiftUI

struct DiffSummary: Equatable {
    var branchLine: String?
    var files: [DiffFileSummary]

    var additions: Int { files.reduce(0) { $0 + $1.additions } }
    var deletions: Int { files.reduce(0) { $0 + $1.deletions } }
    var changedFileCount: Int { files.count }
}

struct DiffFileSummary: Identifiable, Equatable {
    let id = UUID()
    var path: String
    var status: String
    var additions: Int
    var deletions: Int
}

/// Simple Git status-style model for the right-side Git Diff pane.
@MainActor
final class DiffModel: ObservableObject {
    @Published var summary: DiffSummary?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasLoadedOnce = false

    private var currentProjectPath: String?

    func refresh(projectPath: String) {
        let didChangeProject = currentProjectPath != projectPath
        currentProjectPath = projectPath
        if didChangeProject {
            summary = nil
            hasLoadedOnce = false
        }
        isLoading = true
        errorMessage = nil

        Task { [weak self, projectPath] in
            let result = await Task.detached {
                Self.runGitStatus(projectPath: projectPath)
            }.value
            guard let self, self.currentProjectPath == projectPath else { return }
            self.isLoading = false
            self.hasLoadedOnce = true
            switch result {
            case .success(let summary):
                self.summary = summary
            case .failure(let error):
                self.errorMessage = error.message
            }
        }
    }

    private struct GitDiffError: Error { let message: String }

    private nonisolated static func runGit(_ arguments: [String], projectPath: String) -> Result<String, GitDiffError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", projectPath] + arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return .failure(GitDiffError(message: "Couldn’t run git: \(error.localizedDescription)"))
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let message = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(GitDiffError(message: message?.isEmpty == false ? message! : "git failed (exit \(process.terminationStatus))"))
        }

        return .success(String(data: outData, encoding: .utf8) ?? "")
    }

    private nonisolated static func runGitStatus(projectPath: String) -> Result<DiffSummary, GitDiffError> {
        let environment = ProcessInfo.processInfo.environment
        if let gatePath = environment["PI_NATIVE_TEST_DIFF_STATUS_GATE_FIFO"],
           let gate = FileHandle(forReadingAtPath: gatePath) {
            _ = gate.readDataToEndOfFile()
            try? gate.close()
        }
        if let message = environment["PI_NATIVE_TEST_DIFF_STATUS_ERROR"] {
            return .failure(GitDiffError(message: message))
        }
        if environment["PI_NATIVE_TEST_DIFF_STATUS_PROJECT_PATH"] == projectPath,
           let summary = testSummary(from: environment["PI_NATIVE_TEST_DIFF_STATUS_PROJECT_SUMMARY"]) {
            return .success(summary)
        }
        if environment["PI_NATIVE_TEST_OTHER_DIFF_STATUS_PROJECT_PATH"] == projectPath,
           let summary = testSummary(from: environment["PI_NATIVE_TEST_OTHER_DIFF_STATUS_PROJECT_SUMMARY"]) {
            return .success(summary)
        }
        if let summary = testSummary(from: environment["PI_NATIVE_TEST_DIFF_STATUS_SUMMARY"]) {
            return .success(summary)
        }
        let statusOutput: String
        switch runGit(["status", "--short", "--branch"], projectPath: projectPath) {
        case .success(let output): statusOutput = output
        case .failure(let error): return .failure(error)
        }

        var numstats: [String: (additions: Int, deletions: Int)] = [:]
        if case .success(let output) = runGit(["diff", "--numstat"], projectPath: projectPath) {
            mergeNumstat(output, into: &numstats)
        }
        if case .success(let output) = runGit(["diff", "--cached", "--numstat"], projectPath: projectPath) {
            mergeNumstat(output, into: &numstats)
        }

        var branchLine: String?
        var files: [DiffFileSummary] = []

        for rawLine in statusOutput.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("## ") {
                branchLine = String(line.dropFirst(3))
                continue
            }
            guard line.count >= 4 else { continue }

            let status = String(line.prefix(2)).trimmingCharacters(in: .whitespaces)
            let pathStart = line.index(line.startIndex, offsetBy: 3)
            let path = String(line[pathStart...])
            let normalizedPath = path.components(separatedBy: " -> ").last ?? path
            let stat = numstats[normalizedPath] ?? (status == "??" ? untrackedStat(projectPath: projectPath, relativePath: normalizedPath) : (0, 0))
            files.append(DiffFileSummary(path: path, status: status.isEmpty ? "M" : status, additions: stat.additions, deletions: stat.deletions))
        }

        return .success(DiffSummary(branchLine: branchLine, files: files.sorted { $0.path < $1.path }))
    }

    private nonisolated static func testSummary(from rawValue: String?) -> DiffSummary? {
        guard let rawValue else { return nil }
        let parts = rawValue.split(separator: "|", omittingEmptySubsequences: false)
        let branchLine = parts.first.map(String.init).flatMap { $0.isEmpty ? nil : $0 }
        let filePart = parts.count > 1 ? String(parts[1]) : ""
        let files = filePart.split(separator: ";").compactMap { entry -> DiffFileSummary? in
            let fields = entry.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4,
                  let additions = Int(fields[2]),
                  let deletions = Int(fields[3])
            else { return nil }
            return DiffFileSummary(path: fields[0], status: fields[1], additions: additions, deletions: deletions)
        }
        return DiffSummary(branchLine: branchLine, files: files)
    }

    private nonisolated static func mergeNumstat(_ output: String?, into stats: inout [String: (additions: Int, deletions: Int)]) {
        guard let output else { return }
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count >= 3 else { continue }
            let path = String(parts[2])
            let current = stats[path] ?? (0, 0)
            stats[path] = (current.additions + (Int(parts[0]) ?? 0), current.deletions + (Int(parts[1]) ?? 0))
        }
    }

    private nonisolated static func untrackedStat(projectPath: String, relativePath: String) -> (additions: Int, deletions: Int) {
        let fileURL = URL(fileURLWithPath: projectPath).appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8)
        else { return (1, 0) }
        return (max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count), 0)
    }
}

struct DiffPaneView: View {
    @ObservedObject var model: DiffModel
    let projectPath: String

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(.white.opacity(0.12))
            content
        }
        .onAppear { model.refresh(projectPath: projectPath) }
        .onChange(of: projectPath) { _, newPath in model.refresh(projectPath: newPath) }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.forwardslash.minus")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: projectPath).lastPathComponent)
                    .font(.callout.weight(.semibold))
                if let branchLine = model.summary?.branchLine {
                    Text(branchLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button { model.refresh(projectPath: projectPath) } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(model.isLoading)
            .accessibilityLabel("Refresh Diff")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && !model.hasLoadedOnce {
            VStack(spacing: 8) {
                ProgressView()
                    .accessibilityIdentifier("diff.loading")
                Text("Loading Git status…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = model.errorMessage {
            ComingSoonPane(systemImage: "exclamationmark.triangle", title: "Couldn’t load Git status", subtitle: errorMessage)
        } else if let summary = model.summary, summary.files.isEmpty {
            ComingSoonPane(systemImage: "checkmark.seal", title: "No Changes", subtitle: "The working tree has no uncommitted changes.")
        } else if let summary = model.summary {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    DiffTotalsView(summary: summary)
                    VStack(spacing: 6) {
                        ForEach(summary.files) { file in
                            DiffFileRow(file: file)
                        }
                    }
                }
                .padding(14)
            }
        }
    }
}

private struct DiffTotalsView: View {
    let summary: DiffSummary

    var body: some View {
        HStack(spacing: 10) {
            StatCard(label: "Files", value: "\(summary.changedFileCount)", color: .secondary)
            StatCard(label: "Added", value: "+\(summary.additions)", color: .green)
            StatCard(label: "Deleted", value: "-\(summary.deletions)", color: .red)
        }
    }
}

private struct StatCard: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct DiffFileRow: View {
    let file: DiffFileSummary

    var body: some View {
        HStack(spacing: 10) {
            Text(file.status)
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(statusColor)
                .frame(width: 28, alignment: .leading)
            Text(file.path)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            HStack(spacing: 5) {
                if file.additions > 0 {
                    Text("+\(file.additions)").foregroundStyle(.green)
                }
                if file.deletions > 0 {
                    Text("-\(file.deletions)").foregroundStyle(.red)
                }
            }
            .font(.caption.monospacedDigit().weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var statusColor: Color {
        if file.status.contains("?") || file.status.contains("A") { return .green }
        if file.status.contains("D") { return .red }
        return .orange
    }
}
