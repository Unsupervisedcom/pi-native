import AppKit
import SwiftUI

struct WindowChromeConfigurator: NSViewRepresentable {
    @ObservedObject var appModel: AppModel

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(window: view.window, context: context) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(window: nsView.window, context: context) }
    }

    private func configure(window: NSWindow?, context: Context) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar = nil
        window.isOpaque = true
        window.backgroundColor = ShellPalette.chromeNSColor

        context.coordinator.installOrUpdateAccessory(in: window, appModel: appModel)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        private weak var installedWindow: NSWindow?
        private var leadingAccessory: NSTitlebarAccessoryViewController?
        private var leadingHostingController: NSHostingController<AnyView>?
        private var trailingAccessory: NSTitlebarAccessoryViewController?
        private var trailingHostingController: NSHostingController<AnyView>?

        func installOrUpdateAccessory(in window: NSWindow, appModel: AppModel) {
            if installedWindow !== window {
                removeInstalledAccessories()
                installedWindow = window
            }

            installOrUpdateLeadingAccessory(in: window, appModel: appModel)
            installOrUpdateTrailingAccessory(in: window, appModel: appModel)
        }

        private func installOrUpdateLeadingAccessory(in window: NSWindow, appModel: AppModel) {
            let accessoryWidth: CGFloat = appModel.isLeftPaneVisible ? 128 : 176
            let content = AnyView(
                LeadingTitlebarAccessoryControlsView(appModel: appModel)
                    .frame(width: accessoryWidth, height: 44, alignment: .topLeading)
            )

            if leadingAccessory == nil || leadingHostingController == nil {
                let hostingController = makeHostingController(rootView: content, width: accessoryWidth)
                let accessory = NSTitlebarAccessoryViewController()
                accessory.view = hostingController.view
                accessory.layoutAttribute = .left
                accessory.fullScreenMinHeight = 44
                window.addTitlebarAccessoryViewController(accessory)
                leadingAccessory = accessory
                leadingHostingController = hostingController
            } else {
                leadingHostingController?.rootView = content
                leadingHostingController?.view.frame.size = NSSize(width: accessoryWidth, height: 44)
            }
        }

        private func installOrUpdateTrailingAccessory(in window: NSWindow, appModel: AppModel) {
            if appModel.isRightPaneOpen {
                let accessoryWidth: CGFloat = 46
                let content = AnyView(
                    TrailingTitlebarAccessoryControlsView(appModel: appModel)
                        .frame(width: accessoryWidth, height: 44, alignment: .topTrailing)
                )

                if trailingAccessory == nil || trailingHostingController == nil {
                    let hostingController = makeHostingController(rootView: content, width: accessoryWidth)
                    let accessory = NSTitlebarAccessoryViewController()
                    accessory.view = hostingController.view
                    accessory.layoutAttribute = .right
                    accessory.fullScreenMinHeight = 44
                    window.addTitlebarAccessoryViewController(accessory)
                    trailingAccessory = accessory
                    trailingHostingController = hostingController
                } else {
                    trailingHostingController?.rootView = content
                    trailingHostingController?.view.frame.size = NSSize(width: accessoryWidth, height: 44)
                }
            } else if let trailingAccessory,
                      let index = window.titlebarAccessoryViewControllers.firstIndex(of: trailingAccessory) {
                window.removeTitlebarAccessoryViewController(at: index)
                self.trailingAccessory = nil
                self.trailingHostingController = nil
            }
        }

        private func makeHostingController(rootView: AnyView, width: CGFloat) -> NSHostingController<AnyView> {
            let hostingController = NSHostingController(rootView: rootView)
            hostingController.view.frame = NSRect(x: 0, y: 0, width: width, height: 44)
            hostingController.view.wantsLayer = true
            hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
            return hostingController
        }

        private func removeInstalledAccessories() {
            guard let installedWindow else { return }
            for accessory in [leadingAccessory, trailingAccessory].compactMap({ $0 }) {
                if let index = installedWindow.titlebarAccessoryViewControllers.firstIndex(of: accessory) {
                    installedWindow.removeTitlebarAccessoryViewController(at: index)
                }
            }
            leadingAccessory = nil
            leadingHostingController = nil
            trailingAccessory = nil
            trailingHostingController = nil
        }
    }
}

private struct LeadingTitlebarAccessoryControlsView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        HStack(spacing: 6) {
            TitlebarChromeButton(systemName: "gearshape", accessibilityLabel: "Settings", accessibilityIdentifier: "sidebar.settingsButton") {
                appModel.presentSettings()
            }

            TitlebarChromeButton(systemName: "sidebar.leading", accessibilityLabel: appModel.isLeftPaneVisible ? "Hide Sidebar" : "Show Sidebar") {
                appModel.toggleLeftPane()
            }

            TitlebarChromeButton(systemName: "folder.badge.plus", accessibilityLabel: "Add Project", accessibilityIdentifier: "sidebar.addProjectButton") {
                appModel.addProjectWithFolderPicker()
            }

            if !appModel.isLeftPaneVisible {
                TitlebarChromeButton(systemName: "square.and.pencil", accessibilityLabel: "New Chat", accessibilityIdentifier: "sidebar.newChatButton") {
                    appModel.startNewChat()
                }
            }
        }
        .padding(.leading, 8)
        .padding(.top, 2)
    }
}

private struct TrailingTitlebarAccessoryControlsView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        HStack(spacing: 0) {
            TitlebarChromeButton(systemName: "sidebar.right", accessibilityLabel: "Hide Right Pane", accessibilityIdentifier: "shell.toggleRightPaneButton") {
                appModel.toggleRightPane()
            }
        }
        .padding(.trailing, 8)
        .padding(.top, 2)
    }
}

private struct TitlebarChromeButton: View {
    let systemName: String
    let accessibilityLabel: String
    var accessibilityIdentifier: String? = nil
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(isHovering ? Color.primary.opacity(0.08) : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier ?? accessibilityLabel)
        .onHover { isHovering = $0 }
    }
}
