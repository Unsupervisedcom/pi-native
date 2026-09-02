# App Navigation

## Window and shell

- [PiNativeApp.swift](http://127.0.0.1:43117/open?path=PiNative/PiNativeApp.swift&line=1) creates one `WindowGroup`, injects a single `AppModel`, declares menu shortcuts, refreshes Git stats on activation, and stops every runtime on termination.
- [MainWindowView.swift](http://127.0.0.1:43117/open?path=PiNative/MainWindowView.swift&line=1) uses a manual `HStack`, not `NavigationSplitView`: left sidebar, center region, and right pane.
- Side panes animate width to zero instead of being removed, preserving state during collapse.
- The center chat remains mounted while side panes open, close, or switch modes, preserving transcript scroll and view-local expansion state.
- [WindowChromeConfigurator.swift](http://127.0.0.1:43117/open?path=PiNative/Components/WindowChromeConfigurator.swift&line=1) bridges into AppKit for hidden titlebar styling and custom leading/trailing titlebar controls.

## Navigation state in `AppModel`

- `selectedProjectID` + `selectedSessionID` identify the selected conversation.
- `isRightPaneOpen` and nullable `rightPaneMode` distinguish closed, picker-open, and selected-mode states.
- Left visibility and pane widths persist; right-pane open state intentionally resets at launch.

## Entry points

- [ProjectSidebarView.swift](http://127.0.0.1:43117/open?path=PiNative/ProjectSidebarView.swift&line=1) routes New Chat, project rows, chat rows, pin/archive actions, promotion, and pending changes.
- `⌘N` starts a projectless Quick Chat; `⌘1…⌘9` follows visible sidebar order.
- Right-pane shortcuts open Pending Changes and Browser without replacing the selected conversation.
- Settings and Promote to Project are sheets owned by [MainWindowView.swift](http://127.0.0.1:43117/open?path=PiNative/MainWindowView.swift&line=1).
