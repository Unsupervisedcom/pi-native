# REQ-013: Archived Chat Restoration

## Overview

Archiving removes a chat from the active sidebar without discarding its local
recovery data. PiNative provides an Archived Chats surface where users can find
archived project chats and Quick Chats and return a chat to its normal sidebar
location.

Promotion-specific archival remains governed by `REQ-002`; this specification
covers general archive discovery and restoration.

## Requirements

### REQ-013.1: Archived chat discovery

1. When archived chats exist, opening Archived Chats MUST list archived project chats and archived Quick Chats together in most-recently-updated order, identifying each with its title, source, and message count.
2. When no archived chats exist, opening Archived Chats MUST show an empty state.
3. Opening Archived Chats MUST NOT change the selected conversation.

### REQ-013.2: Restoration

1. Restoring an archived chat MUST remove it from Archived Chats and return it to the normal sidebar section determined by its project association and pinned state.
2. Restoring an archived chat MUST NOT change the selected conversation.

### REQ-013.3: Recovery data

1. Archiving or restoring a chat MUST preserve its identity, project or Quick Chat association, session-file reference, cached transcript, and pinned state.
2. Archived and restored state MUST persist across app relaunch.

## Non-goals

- Deleting archived chats, retention periods, search, filtering, bulk restore, or archive export.
- Changing archive eligibility for active or queued work.
- Selecting a chat automatically after restoration.
- Transcript navigation after selecting a restored chat, which remains governed by conversation-navigation requirements.
- Exact visual styling, layout, animation, or iconography.
