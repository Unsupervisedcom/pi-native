# Features

## Core product surface

- **Projects and chats:** bookmarked folders contain project chats; projectless Quick Chats support planning before code work. See [ProjectSidebarView.swift](http://127.0.0.1:43117/open?path=PiNative/ProjectSidebarView.swift&line=1).
- **Parallel conversations:** each opened chat retains an independent model/process runtime, draft, transcript, loading state, and Stop behavior. See [AppModel.swift](http://127.0.0.1:43117/open?path=PiNative/AppModel.swift&line=1).
- **Native chat UI:** streaming assistant text, user bubbles, activity summaries, code blocks, model/effort selection, attachments, and scoped Stop. See [PiConversationView.swift](http://127.0.0.1:43117/open?path=PiNative/PiConversationView.swift&line=1).
- **Durable session UX:** Pi session discovery is merged with PiNative's cached transcript and sidebar metadata so chats survive relaunches.
- **Promote to Project:** turns a Quick Chat into a guarded project folder, creates context/provenance, archives the source, and starts a project-scoped handoff chat. See [PromoteToProject.swift](http://127.0.0.1:43117/open?path=PiNative/PromoteToProject.swift&line=1).
- **Supporting panes:** Git-change summary, embedded browser, plugin/skill catalog, and archived-chat restoration. See [RightPaneView.swift](http://127.0.0.1:43117/open?path=PiNative/RightPaneView.swift&line=1).

## Deliberate current boundaries

- Pi is an external prerequisite; PiNative does not embed the runtime or provider credentials.
- Quick Chats run Pi with `--no-tools` and add a planning-only instruction.
- Interactive extension prompts are surfaced and cancelled, not completed natively yet.
- Pending Changes is a status summary, not hunk-level review/apply.
- Browser is a single user-driven `WKWebView`; agent-opened artifacts are planned work.
- A terminal pane is not in the current product scope.
- Official signed/notarized distribution is still in progress; only the internal unsigned DMG path exists today.
