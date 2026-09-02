# REQ-009: Composer Prompt History

## Overview

PiNative users should be able to recall prompts from the current conversation with
the keyboard, edit them, and submit them again. History recall begins only from an
empty composer and never crosses chat boundaries.

## Requirements

### REQ-009.1: History navigation

1. Pressing Up while the focused composer has no text or attachments MUST replace the composer contents with the most recent transcript user message from the focused chat.
2. Repeated Up presses while browsing prompt history MUST move from newer transcript user messages to older transcript user messages.
3. Pressing Up while the oldest transcript user message is recalled MUST leave the recalled prompt unchanged.
4. Pressing Down while browsing prompt history MUST move from older transcript user messages toward newer transcript user messages.
5. After history browsing reaches the newest recalled prompt, pressing Down MUST restore the composer to its empty state.
6. Recalling a prompt MUST restore its text exactly.
7. Recalling a prompt MUST restore its attachment set in its original order.

### REQ-009.2: Editing and isolation

1. Pressing Up outside active history browsing while the focused composer contains text or attachments MUST preserve the composer contents.
2. Prompt history navigation MUST use only transcript user messages from the focused chat.
3. Editing a recalled prompt MUST NOT modify the corresponding transcript message.
4. A user-originated change to recalled text or attachments MUST end active history browsing.
5. Submitting a recalled prompt MUST append a new user turn to the focused chat.
6. Submitting a recalled prompt MUST leave the previously recalled transcript message unchanged.
7. Pressing Up when the focused chat contains no transcript user messages MUST leave the composer empty.
8. Moving the insertion point or selection within an otherwise unchanged recalled prompt MUST NOT end active history browsing.

### REQ-009.3: Chat switching

1. Switching the focused chat MUST end active history browsing.
2. Switching the focused chat MUST display that chat's own composer contents without displaying recalled content from another chat.
3. Starting history browsing after switching chats MUST begin with the newly focused chat's most recent transcript user message.

## Manual acceptance criteria

- Recall several prompts, move backward and forward, edit one, and resubmit it.
- Begin with a non-empty unsent draft and confirm Up leaves it unchanged.
- Begin with an attachment-only draft and confirm Up leaves it unchanged.
- Confirm switching chats exposes only the selected chat's prompt history.

## Non-goals

- Persisting a separate global prompt-history database across unrelated conversations.
- Adding visible history controls or a history picker to the composer chrome.
- Defining a maximum retained history beyond the transcript retention behavior.
