# REQ-005: Chat Readiness

## Overview

PiNative must make a selected chat immediately usable. Opening the app to a chat or navigating between chats must not wait for Pi RPC startup, session switching, model refresh, or transcript hydration before presenting an interactive composer and model controls.

## Requirements

### REQ-005.1: Immediate chat UI readiness

1. When PiNative displays a selected chat, the chat composer MUST be focusable and ready for text entry before Pi RPC session loading completes. [manual]
2. When PiNative displays a selected chat, the model selector MUST remain enabled before Pi RPC session loading completes. [manual]
3. When PiNative displays a selected chat, the effort selector MUST remain enabled before Pi RPC session loading completes. [manual]

### REQ-005.2: Non-blocking RPC feedback

1. When Pi RPC catastrophically fails for a displayed chat, PiNative MUST show visible red feedback describing that state and disable the chat composer.
2. When Pi RPC requests interactive attention before a session is ready, PiNative MUST show visible feedback for that request instead of silently dropping it.

## Manual acceptance criteria

- App launch into an existing chat should show cached transcript content immediately.
- Switching chats should preserve an immediately usable composer and model controls.
- If RPC startup fails catastrophically, the user should see a compact red status in the transcript area and the composer should be disabled.
- The end-of-chat PiNative mark should not disappear merely because RPC is loading or failed.
- Sending while RPC is unavailable may queue or show a clear retry/status message, but typing and selector interaction should not be blocked.

## Non-goals

- This spec does not require completing a turn while Pi RPC is unavailable.
- This spec does not require implementing every interactive Pi extension prompt UI.
