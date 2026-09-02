# Change Map

## Where a new developer usually starts

| Goal | Primary files |
|---|---|
| Change shell layout/titlebar/panes | [MainWindowView.swift](http://127.0.0.1:43117/open?path=PiNative/MainWindowView.swift&line=1), [WindowChromeConfigurator.swift](http://127.0.0.1:43117/open?path=PiNative/Components/WindowChromeConfigurator.swift&line=1) |
| Change sidebar/projects/chat selection | [ProjectSidebarView.swift](http://127.0.0.1:43117/open?path=PiNative/ProjectSidebarView.swift&line=1), [AppModel.swift](http://127.0.0.1:43117/open?path=PiNative/AppModel.swift&line=1) |
| Change runtime ownership/persistence | [AppModel.swift](http://127.0.0.1:43117/open?path=PiNative/AppModel.swift&line=1) |
| Add or interpret Pi RPC commands/events | [PiRPCClient.swift](http://127.0.0.1:43117/open?path=PiNative/PiRPCClient.swift&line=1), [PiConversationModel.swift](http://127.0.0.1:43117/open?path=PiNative/PiConversationModel.swift&line=1) |
| Change transcript/composer/model picker | [PiConversationView.swift](http://127.0.0.1:43117/open?path=PiNative/PiConversationView.swift&line=1) |
| Change attachments | [AttachmentSupport.swift](http://127.0.0.1:43117/open?path=PiNative/AttachmentSupport.swift&line=1) |
| Change promotion safety/handoff | [PromoteToProject.swift](http://127.0.0.1:43117/open?path=PiNative/PromoteToProject.swift&line=1), [AppModel.swift](http://127.0.0.1:43117/open?path=PiNative/AppModel.swift&line=1) |
| Change Git/browser/plugins/archive panes | [RightPaneView.swift](http://127.0.0.1:43117/open?path=PiNative/RightPaneView.swift&line=1), [DiffPaneView.swift](http://127.0.0.1:43117/open?path=PiNative/DiffPaneView.swift&line=1), [BrowserPaneView.swift](http://127.0.0.1:43117/open?path=PiNative/BrowserPaneView.swift&line=1) |

## Architectural guardrails

- Route asynchronous callbacks by `ConversationKey`; never assume the selected chat owns incoming work.
- Keep Pi as the execution/runtime boundary—do not scrape terminal output.
- Keep ephemeral expansion/hover/navigation presentation state out of persisted transcript models.
- Do not erase cached transcript while attempting live hydration or recovery.
- Treat Stop as server-side cancellation plus stale-event fencing, scoped to one runtime.
- Keep filesystem promotion writes derived, contained, non-overwriting, and retry-safe.
- Preserve deliberate native polish: mounted pane state, immediate hover response, focused composer behavior, and hand-tuned AppKit bridges.
