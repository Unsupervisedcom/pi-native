import SwiftUI

/// Right-pane Plugins content with tabbed Commands/Skills search and a card
/// grid. Renamed from `ExtensionsPaneView`, which rendered this as an
/// embedded sidebar list.
struct ExtensionsPageView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var model = ExtensionsModel()
    @State private var selectedTab: Tab = .commands
    @State private var searchText = ""

    enum Tab: String, CaseIterable, Identifiable {
        case commands = "Commands"
        case skills = "Skills"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 12)

            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(12)

            content
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: appModel.selectedProject?.path) {
            await model.refresh(projectPath: appModel.selectedProject?.path)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            ComingSoonPane(systemImage: "puzzlepiece.extension", title: "Not loaded", subtitle: "Loading Pi commands…")

        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading pi commands…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let catalog):
            let items = filteredItems(catalog)
            if items.isEmpty {
                ComingSoonPane(systemImage: "magnifyingglass", title: "No results", subtitle: "Try a different search or check back after installing plugins.")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                        ForEach(items) { command in
                            CommandCard(command: command)
                        }
                    }
                    .padding(12)
                }
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("Failed to load", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(message)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await model.refresh(projectPath: appModel.selectedProject?.path) }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
        }
    }

    /// Prompt templates fold into the Commands tab (with a source badge on
    /// each card) per the milestone doc's decision, rather than getting a
    /// third tab of their own.
    private func filteredItems(_ catalog: ExtensionCatalog) -> [ExtensionCommand] {
        let base: [ExtensionCommand] = selectedTab == .commands
            ? catalog.extensionCommands + catalog.promptTemplates
            : catalog.skills

        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
}

private struct CommandCard: View {
    let command: ExtensionCommand

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(command.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if let location = command.location {
                    Text(location)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }

            if let description = command.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Image(systemName: sourceIcon)
                Text(sourceLabel)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.14))
        }
    }

    private var sourceIcon: String {
        switch command.source {
        case "extension": "puzzlepiece.extension"
        case "prompt": "text.bubble"
        case "skill": "sparkles"
        default: "questionmark.circle"
        }
    }

    private var sourceLabel: String {
        switch command.source {
        case "extension": "Extension"
        case "prompt": "Prompt template"
        case "skill": "Skill"
        default: command.source.capitalized
        }
    }
}
