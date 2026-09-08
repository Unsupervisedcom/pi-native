# REQ-003: Conversation Navigation and Active Work

## Overview

PiNative conversation navigation must feel stable and native even while Pi work is active. Users should be able to move between projects and chats predictably, return to existing transcripts without blank states or unexpected scroll resets, steer active work without losing messages, and interrupt active work when needed.

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

### REQ-003.7: Steering active work

1. When the selected chat has an active turn, submitting composer content that would be valid for a new turn MUST create a pending steering message for that chat.
2. Submitting a pending steering message MUST leave the current turn active.
3. A pending steering message MUST appear inline after the latest delivered conversation item. [manual]
4. A pending steering message MUST be visually distinguishable from a delivered user message. [manual]
5. A pending steering message MUST display the prepared user text without further modification. [manual]
6. A pending steering message with attachments MUST display the same attachment metadata shown for newly submitted user input. [manual]
7. An attachment-only composer submission during an active turn MUST create a pending steering message.
8. Empty composer content without attachments MUST NOT create a pending steering message.
9. Accepted steering messages for the same active turn MUST appear in the originating conversation history in user-submission order.
10. After Pi accepts a steering message into conversation history as user input, that message MUST leave the pending presentation.
11. Each accepted steering submission MUST produce exactly one delivered user-message entry in its originating conversation history.
12. When Pi rejects a steering request, PiNative MUST restore its text to the originating chat's composer.
13. When Pi rejects a steering request, PiNative MUST restore its attachments to the originating chat's composer.
14. Restoring a rejected steering request MUST preserve content entered in the composer after that request was submitted.
15. Pressing Stop while steering messages are pending MUST abort the active turn.
16. After that stop completes, accepted but undelivered steering messages MUST appear as new user input in a subsequent turn.
17. Steering messages resubmitted after Stop MUST retain their original user-submission order.
18. If Stop is pressed before a steering request is acknowledged, its pending presentation MUST remain until the message is delivered, resubmitted, or retained for retry.
19. A late steering acknowledgement after Stop MUST NOT cause duplicate submission or delivery.
20. A pending steering message MUST be displayed only in its originating chat.
21. Steering delivery events for one chat MUST NOT modify another chat's transcript or pending steering state.
22. If post-stop delivery fails, the complete undelivered steering entry MUST remain visible in its originating chat for retry. [manual]
23. Returning to a chat after navigation MUST display that chat's currently undelivered steering messages in their original order. [manual]

## Manual acceptance criteria

- The selected chat row should use the send-button accent color while remaining readable.
- Running chat rows should show a right-edge working indicator without an animated row-background gradient.
- Project and chat row hover controls should not create dead click zones when hidden.
- Diff pills and project action icons should align visually.
- Nested project chat guide lines should align with project folder icons and leave horizontal breathing room before chat rows.
- Pending steering should follow Pi's presentation: subdued gray inline `Steering:` rows at the bottom of chat history, without a delivered-user bubble.

## Implementation notes

- Tests for row hit targets should click representative left, center, and trailing non-control points.
- Tests for hidden controls should verify the hidden archive, diff, and new-chat affordances do not intercept row selection.
- Tests for active work navigation should start work in one chat, switch to another chat, then verify both the target chat selection and the original chat working indicator.
- Tests for Stop should cover late output suppression after the stop action, not only immediate local state changes.
- Tests for steering should cover multiple queued messages, attachment payloads, RPC rejection, delivery events, Stop races, runtime replacement, and cross-chat isolation.

## Non-goals

- This spec does not require exact sidebar colors, opacity values, line offsets, or animation durations.
- This spec does not require a particular RPC process architecture.
- This spec does not require exhaustive keyboard-navigation coverage for all sidebar rows.
