import SwiftUI

private enum ProjectSidebarPalette {
    static let background = ShellPalette.chrome
    static let projectText = AppTheme.dynamicColor(
        light: NSColor(calibratedWhite: 0.28, alpha: 0.92),
        dark: NSColor(calibratedWhite: 0.68, alpha: 0.92)
    )
}

struct ProjectSidebarView: View {
    @EnvironmentObject private var appModel: AppModel

    // Chat-overflow expansion is deliberately view-local @State (not
    // persisted): it resets to collapsed on every launch, per product
    // decision.
    @State private var expandedChatProjectIDs: Set<Project.ID> = []
    @State private var isStandaloneChatsExpanded = false

    private static let collapsedProjectChatRowLimit = 3
    private static let collapsedQuickChatRowLimit = 5

    var body: some View {
        VStack(spacing: 0) {
            primaryActions
            ShellSeparator()
            if !appModel.pinnedSessions.isEmpty {
                pinnedList
                ShellSeparator()
            }
            chatList
            ShellSeparator()
            projectList
            Spacer(minLength: 0)
            ShellSeparator()
            utilityActions

        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(sidebarBackground)
    }

    private var sidebarBackground: some View {
        ProjectSidebarPalette.background
    }

    private var primaryActions: some View {
        VStack(alignment: .leading, spacing: 1) {
            QuickActionRow(icon: "square.and.pencil", title: "New Chat", accessibilityIdentifier: "sidebar.newChatButton") {
                appModel.startNewChat()
            }
        }
        .padding(.horizontal, SidebarMetrics.sectionHorizontalPadding)
        .padding(.vertical, SidebarMetrics.sectionVerticalPadding)
    }

    private var utilityActions: some View {
        VStack(alignment: .leading, spacing: 1) {
            QuickActionRow(icon: "archivebox", title: "Archived Chats", accessibilityIdentifier: "sidebar.archivedChatsButton") {
                appModel.openRightPane(.archivedChats)
            }
        }
        .padding(.horizontal, SidebarMetrics.sectionHorizontalPadding)
        .padding(.vertical, SidebarMetrics.sectionVerticalPadding)
    }

    private var pinnedList: some View {
        SidebarSection(title: "Pinned") {
            ForEach(appModel.pinnedSessions, id: \.session.id) { item in
                chatRow(session: item.session, projectID: item.projectID)
            }
        }
    }

    private var projectList: some View {
        SidebarSection(title: "Projects") {
            ForEach(appModel.projects) { project in
                ProjectRowView(
                    project: project,
                    isSelected: project.id == appModel.selectedProjectID && appModel.selectedSessionID == nil,
                    onDiff: {
                        appModel.toggleProjectDiffPane(projectID: project.id)
                    },
                    onNewChat: {
                        appModel.startNewChat(in: project.id)
                    }
                ) {
                    appModel.select(projectID: project.id)
                }
                .contextMenu {
                    Button {
                        appModel.revealProjectInFinder(projectID: project.id)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                }

                projectChatRows(for: project)
            }
        }
    }

    @ViewBuilder
    private func projectChatRows(for project: Project) -> some View {
        let sessions = project.sessions.filter { !$0.isArchived && !$0.isPinned }
        let isExpanded = expandedChatProjectIDs.contains(project.id)
        let visible = isExpanded ? sessions : Array(sessions.prefix(Self.collapsedProjectChatRowLimit))

        if !visible.isEmpty || sessions.count > Self.collapsedProjectChatRowLimit {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(visible) { session in
                    chatRow(session: session, projectID: project.id)
                }

                if sessions.count > Self.collapsedProjectChatRowLimit {
                    ChatOverflowToggle(isExpanded: isExpanded, hiddenCount: sessions.count - Self.collapsedProjectChatRowLimit) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            if isExpanded {
                                expandedChatProjectIDs.remove(project.id)
                            } else {
                                expandedChatProjectIDs.insert(project.id)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, SidebarMetrics.nestedChatIndent)
            .padding(.top, -4)
            .overlay(alignment: .leading) {
                NestedChatGuideLine()
                    .padding(.leading, SidebarMetrics.projectIconCenterX)
            }
        }
    }

    private var chatList: some View {
        SidebarSection(title: "Quick Chats") {
            let unarchivedSessions = appModel.standaloneSessions.filter { !$0.isArchived }
            let sessions = unarchivedSessions.filter { !$0.isPinned }
            if unarchivedSessions.isEmpty {
                emptyChatsView
            } else if !sessions.isEmpty {
                let visible = isStandaloneChatsExpanded ? sessions : Array(sessions.prefix(Self.collapsedQuickChatRowLimit))
                ForEach(visible) { session in
                    chatRow(session: session, projectID: nil)
                }

                if sessions.count > Self.collapsedQuickChatRowLimit {
                    ChatOverflowToggle(isExpanded: isStandaloneChatsExpanded, hiddenCount: sessions.count - Self.collapsedQuickChatRowLimit) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            isStandaloneChatsExpanded.toggle()
                        }
                    }
                }
            }
        }
    }

    private func chatRow(session: Session, projectID: Project.ID?) -> some View {
        SessionRowView(
            session: session,
            shortcutIndex: shortcutIndex(for: session.id),
            showsShortcutHint: appModel.isCommandKeyHeld,
            isSelected: session.id == appModel.selectedSessionID && projectID == appModel.selectedProjectID,
            isRunning: appModel.isConversationRunning(sessionID: session.id, projectID: projectID),
            onArchive: {
                appModel.archiveSession(sessionID: session.id, in: projectID)
            },
            action: {
                appModel.select(sessionID: session.id, in: projectID)
            }
        )
        .contextMenu {
            if let projectID {
                Button {
                    appModel.showPendingChanges(projectID: projectID)
                } label: {
                    Label("Show Pending Changes", systemImage: "plusminus")
                }
            } else {
                Button {
                    appModel.presentPromoteToProject(session: session)
                } label: {
                    Label("Promote to Project", systemImage: "shippingbox")
                }
            }

            Button {
                appModel.setSessionPinned(!session.isPinned, sessionID: session.id, in: projectID)
            } label: {
                Label(session.isPinned ? "Unpin Chat" : "Pin Chat", systemImage: session.isPinned ? "pin.slash" : "pin")
            }

            Divider()

            Button {
                appModel.archiveSession(sessionID: session.id, in: projectID)
            } label: {
                Label("Archive Chat", systemImage: "archivebox")
            }
        }
    }

    private func shortcutIndex(for sessionID: Session.ID) -> Int? {
        appModel.visibleSessionShortcuts.first { $0.session.id == sessionID }?.shortcutIndex
    }

    private var emptyChatsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text("No chats yet")
                .font(.body.weight(.semibold))
            Text("Start a new chat or select a project to begin.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 180)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
    }

}

private enum SidebarMetrics {
    static let rowFontSize: CGFloat = 14
    static let sectionHeaderFontSize: CGFloat = 12
    static let supportingFontSize: CGFloat = 13
    static let sectionHorizontalPadding: CGFloat = 10
    static let sectionVerticalPadding: CGFloat = 10
    static let sectionTopPadding: CGFloat = 14
    static let sectionBottomPadding: CGFloat = 10
    static let sectionSpacing: CGFloat = 7
    static let headerHorizontalPadding: CGFloat = 8
    static let rowHorizontalPadding: CGFloat = 8
    static let rowVerticalPadding: CGFloat = 5
    static let chatRowVerticalPadding: CGFloat = 7
    static let rowCornerRadius: CGFloat = 9
    static let rowIconWidth: CGFloat = 24
    static let nestedChatIndent: CGFloat = 28
    static let projectIconCenterX: CGFloat = rowHorizontalPadding + (rowIconWidth / 2)
    static let projectControlSize: CGFloat = 24
    static let projectControlsReservedWidth: CGFloat = 72
    static let chatControlsReservedWidth: CGFloat = 48
}

private struct ShellSeparator: View {
    var body: some View {
        Rectangle()
            .fill(ShellPalette.internalSeparator)
            .frame(height: 1)
    }
}

private struct NestedChatGuideLine: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 0.5, style: .continuous)
            .fill(ShellPalette.internalSeparator)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .padding(.top, -4)
            .padding(.bottom, 2)
            .accessibilityHidden(true)
    }
}

/// Icon-only, low-emphasis affordance revealing the rest of a chat list
/// when more than the collapsed row limit exist. Resets to collapsed on
/// every launch by design.
private struct ChatOverflowToggle: View {
    let isExpanded: Bool
    let hiddenCount: Int
    let action: () -> Void
    @State private var isHovering = false

    private let pillPadding: CGFloat = 5

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: isExpanded ? "chevron.up" : "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isHovering ? .secondary : .tertiary)
                    .padding(pillPadding)
                    .background(isHovering ? Color.primary.opacity(0.07) : .clear, in: Capsule())
                    .contentShape(Capsule())
                Spacer(minLength: 0)
            }
            // Align the glyph itself to the same leading edge as chat-row text;
            // the capsule extends equally around it via `pillPadding`.
            .padding(.leading, SidebarMetrics.rowHorizontalPadding - pillPadding - 1)
            .padding(.trailing, SidebarMetrics.rowHorizontalPadding)
            .padding(.top, 3)
            .padding(.bottom, 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(isExpanded ? "Show fewer chats" : "Show \(hiddenCount) more chats")
        .accessibilityIdentifier("sidebar.chatOverflowToggle")
        .help(isExpanded ? "Show fewer chats" : "Show \(hiddenCount) more")
    }
}

private struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SidebarMetrics.sectionSpacing) {
            SidebarSectionHeader(title)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SidebarMetrics.sectionHorizontalPadding)
        .padding(.top, SidebarMetrics.sectionTopPadding)
        .padding(.bottom, SidebarMetrics.sectionBottomPadding)
    }
}

private struct SidebarSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: SidebarMetrics.sectionHeaderFontSize, weight: .bold))
            .tracking(1.1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, SidebarMetrics.headerHorizontalPadding)
    }
}

private struct SidebarRowButton<Content: View>: View {
    var isSelected = false
    let action: () -> Void
    @ViewBuilder var content: Content
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, SidebarMetrics.rowHorizontalPadding)
                .padding(.vertical, SidebarMetrics.rowVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering in
            // Highlight instantly on hover-in (matching native Mac row
            // behavior — an animated fade-in reads as input lag), and only
            // fade on the way out.
            if hovering {
                isHovering = true
            } else {
                withAnimation(.easeOut(duration: 0.15)) { isHovering = false }
            }
        }
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var backgroundColor: Color {
        if isSelected { return Color.primary.opacity(0.14) }
        if isHovering { return Color.primary.opacity(0.07) }
        return .clear
    }

}

private struct QuickActionRow: View {
    let icon: String
    let title: String
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    var body: some View {
        SidebarRowButton(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body)
                    .frame(width: SidebarMetrics.rowIconWidth)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: SidebarMetrics.rowFontSize))
                Spacer()
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier ?? title)
    }
}

private struct DiffStatPill: View {
    let stats: DiffStats

    var body: some View {
        HStack(spacing: 4) {
            if stats.additions > 0 {
                Text("+\(stats.additions)")
                    .foregroundStyle(.green)
            }
            if stats.deletions > 0 {
                Text("-\(stats.deletions)")
                    .foregroundStyle(.red)
            }
        }
        .font(.system(size: SidebarMetrics.supportingFontSize, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 6)
        .frame(height: SidebarMetrics.projectControlSize)
        .background(.primary.opacity(0.06), in: Capsule())
    }
}

private enum SidebarUITestOverrides {
    static let hidesHoverControls = ProcessInfo.processInfo.environment["PI_NATIVE_TEST_HIDE_SIDEBAR_HOVER_CONTROLS"] == "1"
}

private struct ProjectRowView: View {
    let project: Project
    let isSelected: Bool
    let onDiff: () -> Void
    let onNewChat: () -> Void
    let action: () -> Void
    @State private var isHovering = false
    @State private var isNewChatHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.body)
                    .foregroundStyle(projectForegroundStyle)
                    .frame(width: SidebarMetrics.rowIconWidth)
                Text(project.name)
                    .font(.system(size: SidebarMetrics.rowFontSize, weight: .medium))
                    .foregroundStyle(projectForegroundStyle)
                    .lineLimit(1)
                Spacer(minLength: SidebarMetrics.projectControlsReservedWidth)
            }
            .padding(.horizontal, SidebarMetrics.rowHorizontalPadding)
            .padding(.vertical, SidebarMetrics.rowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("project.row")
        .buttonStyle(.plain)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous))
        .overlay(alignment: .trailing) {
            projectControls
                .padding(.trailing, SidebarMetrics.rowHorizontalPadding)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            // Same instant-in/fade-out hover treatment as SidebarRowButton.
            if hovering {
                isHovering = true
            } else {
                withAnimation(.easeOut(duration: 0.15)) { isHovering = false }
            }
        }
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(project.path)
    }

    private var projectControls: some View {
        HStack(spacing: 8) {
            if hoverControlsVisible {
                if let diffStats = project.diffStats {
                    Button(action: onDiff) {
                        DiffStatPill(stats: diffStats)
                            .frame(height: SidebarMetrics.projectControlSize, alignment: .center)
                    }
                    .buttonStyle(.plain)
                    .help("Show Git diff")
                    .accessibilityIdentifier("project.diffPill")
                    .transition(.opacity)
                }

                Button(action: onNewChat) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: SidebarMetrics.projectControlSize, height: SidebarMetrics.projectControlSize)
                        .background(isNewChatHovering ? Color.primary.opacity(0.10) : Color.clear, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("New chat in \(project.name)")
                .accessibilityLabel("New chat in \(project.name)")
                .accessibilityIdentifier("project.newChatButton")
                .onHover { isNewChatHovering = $0 }
                .transition(.opacity)
            }
        }
    }

    private var hoverControlsVisible: Bool {
        isHovering && !SidebarUITestOverrides.hidesHoverControls
    }

    private var projectForegroundStyle: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.primary) }
        if isHovering { return AnyShapeStyle(projectHoverForeground) }
        return AnyShapeStyle(ProjectSidebarPalette.projectText)
    }

    private var projectHoverForeground: Color {
        AppTheme.dynamicColor(
            light: NSColor(calibratedWhite: 0.06, alpha: 0.92),
            dark: NSColor(calibratedWhite: 1.0, alpha: 0.84)
        )
    }

    private var backgroundColor: Color {
        if isSelected { return Color.primary.opacity(0.14) }
        if isHovering { return Color.primary.opacity(0.07) }
        return .clear
    }
}

private struct SessionRowView: View {
    let session: Session
    let shortcutIndex: Int?
    let showsShortcutHint: Bool
    let isSelected: Bool
    let isRunning: Bool
    let onArchive: () -> Void
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(session.name)
                    .font(.system(size: SidebarMetrics.rowFontSize))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(session.name)
                Spacer(minLength: SidebarMetrics.chatControlsReservedWidth)
            }
            .padding(.horizontal, SidebarMetrics.rowHorizontalPadding)
            .padding(.vertical, SidebarMetrics.chatRowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            SessionRowBackground(isSelected: isSelected, isHovering: isHovering, isRunning: isRunning)
        }
        .overlay(alignment: .trailing) {
            chatControls
                .id(isRunning)
                .padding(.trailing, SidebarMetrics.rowHorizontalPadding)
                .transaction { transaction in
                    if !isRunning {
                        transaction.disablesAnimations = true
                        transaction.animation = nil
                    }
                }
                .animation(nil, value: isRunning)
        }
        .overlay {
            RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous)
                .stroke(isRunning ? Color.accentColor.opacity(0.14) : (isHovering && !isSelected ? Color.white.opacity(0.5) : .clear), lineWidth: 0.5)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                isHovering = true
            } else {
                withAnimation(.easeOut(duration: 0.15)) { isHovering = false }
            }
        }
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: showsShortcutHint)
        .transaction { transaction in
            if !isRunning {
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
        }
    }

    private var hoverControlsVisible: Bool {
        isHovering && !SidebarUITestOverrides.hidesHoverControls
    }

    private var chatControls: some View {
        HStack(spacing: 6) {
            if isRunning {
                RunningChatShimmerRing()
                    .frame(width: 24, height: 24)
                    .accessibilityLabel("Chat is working")
                    .accessibilityIdentifier("chat.runningSpinner")
                    .transition(.identity)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
            } else {
                if showsShortcutHint, let shortcutIndex {
                    Text("⌘\(shortcutIndex)")
                        .font(.system(size: SidebarMetrics.supportingFontSize, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                        .allowsHitTesting(false)
                }

                if hoverControlsVisible {
                    Button(action: onArchive) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chat.archiveButton")
                    .accessibilityLabel("Archive Chat")
                    .help("Archive chat")
                    .transition(.opacity)
                }
            }
        }
    }
}

private struct SessionRowBackground: View {
    let isSelected: Bool
    let isHovering: Bool
    let isRunning: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous)
            .fill(baseColor)
    }

    private var baseColor: Color {
        if isSelected { return AppTheme.skyAccent.opacity(0.28) }
        if isHovering { return Color.primary.opacity(0.07) }
        return .clear
    }
}

private struct RunningChatShimmerRing: View {
    var body: some View {
        TimelineView(.animation) { context in
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.24), lineWidth: 2.2)
                    .frame(width: 17, height: 17)

                Circle()
                    .trim(from: 0.0, to: 0.34)
                    .stroke(
                        AngularGradient(
                            stops: [
                                .init(color: Color.primary.opacity(0.10), location: 0.0),
                                .init(color: Color.primary.opacity(0.72), location: 0.55),
                                .init(color: Color.primary, location: 1.0)
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 2.8, lineCap: .butt)
                    )
                    .frame(width: 17, height: 17)
                    .rotationEffect(.degrees(rotation(for: context.date)))
            }
        }
    }

    private func rotation(for date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.7) / 1.7 * 360
    }
}
