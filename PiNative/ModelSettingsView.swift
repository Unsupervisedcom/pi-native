import SwiftUI

struct ModelSettingsView: View {
    @ObservedObject var model: ModelSettingsModel
    let onRefresh: (_ force: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(.bottom, 24)

            content
        }
        .padding(.horizontal, 30)
        .onAppear { onRefresh(false) }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search \(model.catalog.count) models…", text: $model.searchQuery)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("settings.models.searchField")
            if !model.searchQuery.isEmpty {
                Button {
                    model.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear model search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        switch model.catalogState {
        case .idle:
            ModelSettingsStateView(
                title: "Models have not loaded yet",
                message: "PiNative will load the available models from Pi.",
                actionTitle: "Load Models",
                action: { onRefresh(true) }
            )
        case .loading:
            ModelSettingsStateView(title: "Loading models…", message: "Fetching the available model catalog from Pi.")
        case .failed(let message):
            ModelSettingsStateView(
                title: "Could not load models",
                message: message,
                actionTitle: "Retry",
                action: { onRefresh(true) }
            )
        case .loaded:
            modelList
        }
    }

    private var modelList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if hasMatchingFavorites {
                    sectionHeader("Favorites", identifier: "settings.models.favoritesSection")
                    ForEach(model.filteredAvailableFavorites, id: \.stableID) { favorite in
                        favoriteModelRow(favorite)
                    }
                    ForEach(model.filteredUnavailableFavorites, id: \.stableID) { favorite in
                        UnavailableModelRow(
                            model: favorite,
                            canRemove: model.canRemoveFavorite(favorite)
                        ) {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                model.removeFavorite(favorite)
                            }
                        }
                    }
                }

                if model.catalog.isEmpty {
                    ModelSettingsStateView(
                        title: "No models available",
                        message: "Pi did not report any available models.",
                        actionTitle: "Retry",
                        action: { onRefresh(true) }
                    )
                } else if !hasMatchingFavorites && model.filteredOtherModels.isEmpty {
                    ModelSettingsStateView(
                        title: "No matching models",
                        message: "Try a different provider, model ID, or display name."
                    )
                } else {
                    sectionHeader(
                        "Available Models",
                        identifier: "settings.models.availableModelsSection",
                        topPadding: hasMatchingFavorites ? 24 : 0
                    )
                    if model.filteredOtherModels.isEmpty {
                        Text(model.searchQuery.isEmpty ? "All available models are favorites." : "No other models match this search.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(model.filteredOtherModels, id: \.stableID) { option in
                            availableModelRow(option)
                        }
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var hasMatchingFavorites: Bool {
        !model.filteredAvailableFavorites.isEmpty || !model.filteredUnavailableFavorites.isEmpty
    }

    private func sectionHeader(_ title: String, identifier: String, topPadding: CGFloat = 0) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(identifier)
            Divider()
        }
        .padding(.top, topPadding)
        .padding(.bottom, 6)
    }

    private func favoriteModelRow(_ option: PiModelOption) -> some View {
        ModelSettingsRow(
            model: option,
            isFavorite: true,
            canRemove: model.canRemoveFavorite(option)
        ) { _ in
            withAnimation(.easeInOut(duration: 0.16)) {
                model.setFavorite(false, for: option)
            }
        }
        .id("favorite-\(option.stableID)")
    }

    private func availableModelRow(_ option: PiModelOption) -> some View {
        ModelSettingsRow(
            model: option,
            isFavorite: false,
            canRemove: true
        ) { _ in
            withAnimation(.easeInOut(duration: 0.16)) {
                model.setFavorite(true, for: option)
            }
        }
        .id("available-\(option.stableID)")
    }
}

private struct ModelSettingsRow: View {
    let model: PiModelOption
    let isFavorite: Bool
    let canRemove: Bool
    let onFavoriteChange: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(model.provider) • \(model.id)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Button {
                onFavoriteChange(!isFavorite)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isFavorite ? Color.accentColor : Color.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isFavorite && !canRemove)
            .accessibilityLabel(isFavorite && !canRemove ? "\(model.name) is the only favorite" : (isFavorite ? "Remove \(model.name) from favorites" : "Add \(model.name) to favorites"))
            .accessibilityHint(isFavorite && !canRemove ? "Add another favorite before removing this one." : "")
            .accessibilityIdentifier("settings.models.favorite.\(model.stableID)")
            .help(isFavorite && !canRemove ? "Add another favorite before removing this one." : (isFavorite ? "Remove from favorites" : "Add to favorites"))
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.models.row.\(model.stableID)")
    }
}

private struct UnavailableModelRow: View {
    let model: PiModelOption
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.system(size: 14, weight: .medium))
                Text("\(model.provider) • \(model.id)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text("Unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.07), in: Capsule())
            Button("Remove", action: onRemove)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(!canRemove)
                .accessibilityLabel(canRemove ? "Remove \(model.name) from favorites" : "\(model.name) is the only favorite")
                .accessibilityHint(canRemove ? "" : "Add another favorite before removing this one.")
                .help(canRemove ? "Remove from favorites" : "Add another favorite before removing this one.")
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("settings.models.unavailable.\(model.stableID)")
    }
}

private struct ModelSettingsStateView: View {
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
        .accessibilityIdentifier("settings.models.state")
    }
}
