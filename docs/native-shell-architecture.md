# Native Shell Architecture

How the app's shell (layout, navigation, panes) is structured after the shipped
native-shell milestone. This document describes the current implementation.

## Layout

`MainWindowView` is a manual 3-region `HStack`, not `NavigationSplitView`:

- **Left sidebar** (`ProjectSidebarView`) — New Chat and Archived Chats actions
  plus the project/session list.
- **Center** — `ChatPaneView`, kept mounted so the conversation model and the
  view's local state (scroll position and expanded activity groups) remain
  stable while side panes open, close, or switch modes.
- **Right pane** (`RightPaneView`) — also always mounted, width animates to 0
  when closed rather than being conditionally removed, so state under it
  (e.g. `BrowserModel`'s navigation history) survives a collapse.

Both pane boundaries use `ResizableDividerView` (`Components/`): live drag
writes directly to the bound width with no animation; double-click and the
toolbar's collapse button go through `withAnimation` — two different code
paths, because animating the live-drag path makes dragging visibly lag the
cursor.

## `AppModel` shell state

```swift
@Published var isLeftPaneVisible: Bool       // persisted
@Published var leftPaneWidth: CGFloat        // persisted
@Published var isRightPaneOpen: Bool         // NOT persisted — always starts closed
@Published var rightPaneMode: RightPaneMode? // NOT persisted — nil = picker showing
@Published var rightPaneWidth: CGFloat       // persisted
```

`isRightPaneOpen` + `rightPaneMode` is a deliberate two-flag design: a single
nullable `rightPaneMode` can't distinguish "pane closed" from "pane open,
showing the picker, no mode chosen yet" — both would be `nil`.

## Conversation runtime lifecycle

`AppModel` owns a per-conversation runtime registry rather than a single
retargeted Pi runtime. `ConversationKey(projectID:sessionID:)` is the stable
app-local identity for a chat, and `conversationRuntimes` maps each key to a
`PiConversationModel` wrapped by lightweight runtime metadata.

Selection updates `selectedProjectID` / `selectedSessionID`, derives
`selectedConversationKey`, ensures a runtime for that key, and then assigns the
selected runtime's model to `activeConversationModel` for the center pane. The
old selected runtime is not stopped just because the user navigates away. This
is what lets a turn continue in Chat A while the user opens Chat B, starts a
Quick Chat, or creates another project-scoped chat.

Runtime callbacks capture their `ConversationKey`, not ambient selection. Session
path resolution, fallback/semantic-title state, transcript persistence, and
running/loading/error state updates are routed back to the owning chat even when
a different chat is selected. Sidebar running indicators read
`conversationRuntimeStates[key]` through `isConversationRunning(sessionID:projectID:)`,
so multiple rows can independently show active work.

`PiConversationModel.stop()` and the Stop button are scoped to the currently
selected runtime. Stopping the visible chat must not abort unrelated active
runtimes. Non-running runtime cleanup happens when chats are archived/deleted or
when a promoted Quick Chat source is archived; cleanup cancels subscriptions,
stops the idle model, and removes its runtime state. App termination calls
`stopAllRuntimes()` so every live `pi --mode rpc` subprocess is asked to shut
down before the app exits.

`activeConversationModel` remains as the selected-view binding for SwiftUI, but
it is no longer the app's only live conversation. Code that needs to mutate or
query a specific chat should use `ConversationKey`/`runtime(for:)` rather than
assuming the selected model owns all live work.

## First-response chat titles

Only chats newly created by PiNative are eligible for automatic naming. Their
first accepted prompt immediately supplies a deterministic sidebar fallback.
The owning runtime waits for Pi's ordered `agent_settled` event, captures an
immutable snapshot of the first user prompt and finalized assistant text, and
enqueues the chat's sole lifetime semantic-title attempt. Duplicate settlement
events, later turns, failures, cancellation, runtime recreation, and app
restoration cannot enqueue another attempt; unsuccessful or interrupted work
keeps the fallback and permanently consumes eligibility.

`PiChatTitleService` serializes title jobs through an isolated Pi RPC helper
launched with `--no-session` and project resources disabled. One deadline covers
startup, prompt acknowledgement, settlement, and final-text retrieval. Success,
failure, timeout, and cancellation all close pipes and reap the helper through
the process termination signal, escalating to `SIGKILL` only after the graceful
exit deadline. Title traffic never enters the visible conversation transcript.

Accepted titles are normalized to one line and at most 48 Swift `Character`
values, persisted with provenance, and mirrored through `set_session_name` as a
best effort. A user-authored or externally authored Pi session name is checked
before and after generation and remains authoritative over any late automatic
result.

`BrowserModel` (in `AppModel.browserModelInstance()`) follows a lazily-created,
kept-alive-for-the-app's-lifetime pattern, so browser navigation state survives
switching right-pane modes away and back.

## Transcript grouping

`PiConversationModel.items: [TranscriptItem]` — `.user`, `.assistantText`,
`.activity(ActivityGroup)`, `.notice`.

```swift
struct ActivityGroup: Identifiable, Hashable {
    var id: UUID
    var tools: [ToolTranscriptItem]
    var isRunning: Bool
    var startedAt: Date
    var finishedAt: Date?
}
```

**Grouping boundary rule:** a new `ActivityGroup` opens on the first
`tool_execution_start` of a turn and stays open across interleaved assistant
text within that same turn — only `agent_end` (turn boundary) or the next
user message closes it (`closeCurrentActivityGroup()`). This means a single
turn with "text → tool → text → tool → text" produces **one** activity row,
not several. `assistantBufferID` (the in-progress text-delta accumulator) is
reset whenever a new group opens, so text that comes after a tool call starts
a fresh `.assistantText` item instead of merging into whatever text preceded
the tool call.

**Historical hydration** (`buildTranscript(from:)`) is a stateful reduce over
the full message list, not a per-message `flatMap`: saved sessions store a
`toolCall`'s arguments inside the assistant message's `content` array, but
the matching `toolResult` (output only) is a separate, later top-level
message, reconciled by `callID` via a first pass that indexes all
`toolResult`s before the main pass walks messages in order.

**Expansion state** (`expandedGroupIDs`) is `@State` inside `PiConversationView`,
not part of the published model — putting it in `items` would fire the
transcript's scroll-to-bottom `onChange` whenever an old group is expanded.

**Visual weight:** the collapsed activity row is deliberately low-emphasis
(inline text, no card background/border) to match the reference layout's
"Worked for 1m 19s ›" treatment; only the *expanded* per-tool detail
(`ToolCallCard`) uses card styling, since that's real content, not a summary.

## RPC abort

`PiRPCClient.abort()` calls the real `abort` RPC command (`session.abort()`
server-side in pi's RPC mode — confirmed by reading `rpc-mode.js`), not a
client-side give-up. The composer's stop button (visible while the selected
runtime `isRunning`) is wired to the selected conversation model only. `prompt()`'s
own response is a preflight ack, not "turn fully finished" — runtime running
state is driven by the `agent_start`/`agent_end` event stream and mirrored into
`conversationRuntimeStates`, never by `prompt()`'s call completing.
