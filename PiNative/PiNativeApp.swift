import SwiftUI
import AppKit

@main
struct PiNativeApp: App {
    @StateObject private var appModel: AppModel

    init() {
        self.init(analytics: AppAnalytics.shared)
    }

    init(analytics: any AnalyticsControlling) {
        _appModel = StateObject(wrappedValue: AppModel(analytics: analytics))
        // This app doesn't use macOS's automatic multi-window tab bar (the
        // shell has its own custom pane/navigation model), so suppress the
        // system-provided tab "+"/tab-bar chrome it would otherwise add to
        // the toolbar for a plain `WindowGroup` scene.
        NSWindow.allowsAutomaticWindowTabbing = false
        analytics.track(.appOpened)
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appModel)
                .frame(minWidth: 1200, minHeight: 640)
                .dynamicTypeSize(.xLarge)
                .imageScale(.large)
                .onAppear {
                    appModel.startCommandKeyTracking()
                    if ProcessInfo.processInfo.environment["PI_NATIVE_RESET_PROJECTS"] == "1" {
                        NSApplication.shared.setActivationPolicy(.regular)
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                }
                .onDisappear { appModel.stopCommandKeyTracking() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    appModel.refreshProjectDiffStats()
                    if appModel.piHealthIssue != nil {
                        Task {
                            guard await appModel.checkPiHealthAfterRecoveryIfNeeded() else { return }
                            guard appModel.piHealthIssue == nil else { return }
                            appModel.startActiveConversationIfNeeded()
                            await appModel.refreshModelCatalog()
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    appModel.stopAllRuntimes()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1400, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    appModel.startNewChat()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }

            // ⌘P is spec-mandated for Files (implementation plan §C /
            // milestone doc's shortcut table), which collides with macOS's
            // conventional Print shortcut. This app has no print feature, but
            // explicitly claim/empty the slot anyway rather than leaving a
            // default-but-disabled "Print…" menu item showing the same ⌘P
            // label next to Files in the menu bar. Found by adversarial review.
            CommandGroup(replacing: .printItem) {}

            CommandGroup(after: .toolbar) {
                Button("Pending Changes") { appModel.openRightPane(.review) }
                    .keyboardShortcut("g", modifiers: [.control, .shift])
                Button("Browser") { appModel.openRightPane(.browser) }
                    .keyboardShortcut("t", modifiers: [.command])
            }

            CommandGroup(after: .windowArrangement) {
                ForEach(1...9, id: \.self) { index in
                    Button("Switch to Session \(index)") {
                        appModel.selectSession(shortcutIndex: index)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: [.command])
                    .disabled(appModel.visibleSessionShortcuts.count < index)
                }
            }
        }
    }
}
