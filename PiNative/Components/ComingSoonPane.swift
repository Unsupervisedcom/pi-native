import SwiftUI

/// Shared empty/stub-state visual language, per implementation plan §E.
/// Used for every not-yet-wired pane/page this milestone (Terminal, Files,
/// Review, Side chat, Search, Scheduled, ...) so stubs read as intentional,
/// polished placeholders rather than bare "TODO" labels.
struct ComingSoonPane: View {
    var systemImage: String
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

#Preview {
    ComingSoonPane(
        systemImage: "terminal",
        title: "Terminal",
        subtitle: "Run commands alongside your conversation. Coming soon."
    )
    .frame(width: 340, height: 400)
}
