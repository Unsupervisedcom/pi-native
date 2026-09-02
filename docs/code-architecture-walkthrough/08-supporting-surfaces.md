# Supporting Surfaces

## Right pane router

[RightPaneView.swift](http://127.0.0.1:43117/open?path=PiNative/RightPaneView.swift&line=1) keeps a picker plus four routed modes:

- **Pending Changes:** [DiffPaneView.swift](http://127.0.0.1:43117/open?path=PiNative/DiffPaneView.swift&line=1) runs `/usr/bin/git status` and numstat off the main actor, then shows branch, totals, and file rows.
- **Browser:** [BrowserPaneView.swift](http://127.0.0.1:43117/open?path=PiNative/BrowserPaneView.swift&line=1) wraps a retained `WKWebView`, normalizes URLs/searches/local dev servers, and preserves history across mode changes.
- **Plugins:** [ExtensionsPageView.swift](http://127.0.0.1:43117/open?path=PiNative/ExtensionsPageView.swift&line=1) presents commands, prompt templates, and skills with tabs/search.
- **Archived Chats:** lists retained archived sessions and removes the archive flag on restore.

## Independent supporting models

- `BrowserModel` and `DiffModel` are lazily instantiated by `AppModel` outside SwiftUI body evaluation and retained for app lifetime.
- [ExtensionsModel.swift](http://127.0.0.1:43117/open?path=PiNative/ExtensionsModel.swift&line=1) launches a short-lived Pi client in the selected project and calls `get_commands`.
- Supporting panes do not own or retarget the selected conversation runtime.

## Settings

- Settings currently persists appearance and Promote-to-Project defaults; model favorites are planned next.
