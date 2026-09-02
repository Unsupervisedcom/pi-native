import SwiftUI

extension RightPaneMode {
    var title: String {
        switch self {
        case .review: "Pending Changes"
        case .browser: "Browser"
        case .plugins: "Plugins"
        case .archivedChats: "View Archived Chats"
        }
    }

    var systemImage: String {
        switch self {
        case .review: "plus.forwardslash.minus"
        case .browser: "globe"
        case .plugins: "puzzlepiece.extension"
        case .archivedChats: "archivebox"
        }
    }

    var shortcutLabel: String? {
        switch self {
        case .review: "^⇧G"
        case .browser: "⌘T"
        case .plugins, .archivedChats: nil
        }
    }
}

/// Right-side pane router. The empty state is a compact mode picker; selecting
/// a mode swaps in its content while the top-right control collapses the pane.
struct RightPaneView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(ShellPalette.separator)
                .frame(height: 1)
            content
        }
        .background(ShellPalette.chrome)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if appModel.rightPaneMode != nil {
                Button {
                    appModel.rightPaneMode = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Back to pane picker")
                .accessibilityLabel("Back to Pane Picker")
            }

            if let mode = appModel.rightPaneMode {
                Text(mode.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(ShellPalette.chrome)
    }

    @ViewBuilder
    private var content: some View {
        switch appModel.rightPaneMode {
        case nil:
            RightPanePickerView()
        case .review:
            if let model = appModel.diffModel, let projectPath = appModel.reviewProject?.path {
                DiffPaneView(model: model, projectPath: projectPath)
            } else {
                ComingSoonPane(systemImage: "folder.badge.questionmark", title: "No Project", subtitle: "Select a project to review its Git changes.")
            }
        case .browser:
            if let model = appModel.browserModel {
                BrowserPaneView(model: model)
            } else {
                ProgressView()
            }
        case .plugins:
            ExtensionsPageView()
        case .archivedChats:
            ArchivedChatsPaneView()
        }
    }
}

private struct ArchivedChatsPaneView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Group {
            if appModel.archivedChats.isEmpty {
                ComingSoonPane(
                    systemImage: "archivebox",
                    title: "No Archived Chats",
                    subtitle: "Archived chats will appear here so you can restore them later."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(appModel.archivedChats, id: \.session.id) { item in
                            ArchivedChatRow(
                                session: item.session,
                                projectName: item.projectName,
                                onUnarchive: {
                                    appModel.unarchiveSession(sessionID: item.session.id, in: item.projectID)
                                }
                            )
                        }
                    }
                    .padding(14)
                }
            }
        }
        .accessibilityIdentifier("archivedChats.pane")
    }
}

private struct ArchivedChatRow: View {
    let session: Session
    let projectName: String?
    let onUnarchive: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "bubble.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button("Unarchive", action: onUnarchive)
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("archivedChats.unarchiveButton")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var subtitle: String {
        let location = projectName ?? "Quick Chat"
        let count = session.messageCount == 1 ? "1 message" : "\(session.messageCount) messages"
        return "\(location) · \(count)"
    }
}

struct RightPanePickerView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 6) {
                ForEach(RightPaneMode.availableModes) { mode in
                    Button {
                        appModel.selectRightPaneMode(mode)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mode.systemImage)
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 20)
                                .foregroundStyle(.secondary)
                            Text(mode.title)
                                .font(.body.weight(.medium))
                            Spacer()
                            if let shortcut = mode.shortcutLabel {
                                Text(shortcut)
                                    .font(.caption.monospaced().weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(.white.opacity(0.08), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 28)
            Spacer()
        }
    }
}
