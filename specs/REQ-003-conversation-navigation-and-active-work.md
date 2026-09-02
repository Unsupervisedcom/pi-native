# REQ-003: Conversation Navigation and Active Work

## Overview

PiNative conversation navigation must feel stable and native even while Pi work is active. Users should be able to move between projects and chats predictably, return to existing transcripts without blank states or unexpected scroll resets, and interrupt active work when needed.

This spec captures the next testing focus for the shell and conversation lifecycle. It intentionally states observable outcomes rather than prescribing whether the implementation uses one conversation model, per-chat models, process isolation, cached transcripts, or another mechanism.

## Requirements

### REQ-003.1: Conversation display restoration

1. A selected chat MUST display its available transcript after app activation, window focus changes, and same-session resynchronization. [manual]
2. Returning to a previously displayed chat MUST restore the transcript near the most recent content instead of resetting to the top.
3. A redundant same-session synchronization MUST NOT replace a displayed transcript with an empty transcript when cached transcript data is unavailable.
4. Updating the selected chat transcript MUST reveal the bottom of the chat transcript.

### REQ-003.2: Sidebar selection targets

1. A project row MUST select its project chat when the user clicks anywhere in the row except an explicitly visible trailing control.
2. A chat row MUST select its chat when the user clicks anywhere in the row except an explicitly visible trailing control.
3. Invisible hover-only controls MUST NOT block project or chat row selection.

### REQ-003.3: Project chat selection

1. Selecting a project row MUST open the most recently updated visible unpinned chat in that project.
2. Archived chats MUST NOT be selected by clicking a project row.
3. Pinned chats MUST NOT be selected by clicking a project row.

### REQ-003.4: Active work navigation

1. In-flight work in one chat MUST NOT prevent selecting another chat.
2. In-flight work in one chat MUST NOT prevent opening another project chat.
3. Switching away from a working chat MUST leave that chat visibly marked as working in the sidebar. [manual]
4. When work completes, the sidebar working indicator MUST stop for that chat. [manual]
5. Output produced by in-flight work in one chat MUST append only to that chat's transcript, even when another chat is selected.
6. Starting work in a second chat while a first chat is running MUST leave both chats independently visible as running until each turn finishes or is stopped. [manual]
7. Pending startup or queued prompt work in one chat MUST NOT prevent selecting another chat.
8. In-flight work in one chat MUST NOT prevent opening the new-chat surface or creating a new chat.

### REQ-003.5: Stop behavior

1. Pressing Stop for the selected chat's active turn MUST replace its visible Stop control with the Send control within one second.
2. Pressing Stop during an active turn MUST prevent later output from that stopped turn from appending to the transcript.
3. Pressing Stop during an active turn MUST leave the composer usable for a later prompt.
4. Pressing Stop in the selected chat MUST NOT stop in-flight work in another chat.

### REQ-003.6: Quick Chat creation and navigation

1. Opening the global New Chat action with no project selected MUST display a projectless Quick Chat composer. [manual]
2. Submitting the first prompt from a projectless Quick Chat composer MUST create a Quick Chat row in the Quick Chats section. [manual]
3. A Quick Chat row MUST remain selectable after switching to a project chat and back. [manual]
4. Quick Chat draft text MUST NOT leak into project chats or other Quick Chats.
5. In-flight work in a Quick Chat MUST NOT prevent selecting or starting work in a project chat.
6. Output produced by in-flight work in a Quick Chat MUST append only to that Quick Chat's transcript.

## Manual acceptance criteria

- The selected chat row should use the send-button accent color while remaining readable.
- Running chat rows should show a right-edge working indicator without an animated row-background gradient.
- Project and chat row hover controls should not create dead click zones when hidden.
- Diff pills and project action icons should align visually.
- Nested project chat guide lines should align with project folder icons and leave horizontal breathing room before chat rows.

## Implementation notes

- Tests for row hit targets should click representative left, center, and trailing non-control points.
- Tests for hidden controls should verify the hidden archive, diff, and new-chat affordances do not intercept row selection.
- Tests for active work navigation should start work in one chat, switch to another chat, then verify both the target chat selection and the original chat working indicator.
- Tests for Stop should cover late output suppression after the stop action, not only immediate local state changes.

## Non-goals

- This spec does not require exact sidebar colors, opacity values, line offsets, or animation durations.
- This spec does not require a particular RPC process architecture.
- This spec does not require exhaustive keyboard-navigation coverage for all sidebar rows.
