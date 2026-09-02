# Transcript & Composer

## Transcript representation

[PiConversationModel.swift](http://127.0.0.1:43117/open?path=PiNative/PiConversationModel.swift&line=1) publishes four `TranscriptItem` cases:

- `user(UserMessagePayload)` — text plus display attachments.
- `assistantText` — streamed text accumulated by stable item ID.
- `activity(ActivityGroup)` — one or more correlated tool calls.
- `notice` — loading, failure, compaction, Stop, and extension feedback.

## Live and historical reconstruction

- Live `text_delta` events append to the current assistant buffer.
- Tool events are correlated by `toolCallId`; a group remains open across interleaved assistant text until `agent_end` or the next user message.
- Historical hydration first indexes top-level tool results, then reduces assistant tool calls and text in order.
- Stale hydration and stale-process events are rejected before mutating the transcript.

## Native rendering

- [PiConversationView.swift](http://127.0.0.1:43117/open?path=PiNative/PiConversationView.swift&line=1) renders user bubbles, bubble-free assistant prose, fenced code, plain-language activity summaries, notices, and the animated end mark.
- Activity expansion and picker presentation remain view-local so UI-only changes do not mutate/persist the transcript or trigger unwanted auto-scroll.
- The composer uses an AppKit-backed text view for reliable focus, Enter submission, paste interception, and drag/drop.
- An empty composer can recall that chat's transcript user messages with Up. While browsing, Up/Down move through only that chat's history; Down after the newest prompt returns to an empty composer. Existing text or attachments prevent recall from starting.
- Recalled prompts copy both text and ordered attachments into the draft. A user edit ends history browsing, and changing the selected chat resets the browsing position so navigation state cannot cross chat boundaries.
- Model and effort are loaded and changed with real Pi RPC commands.
- The composer remains editable while session hydration is pending; only catastrophic Pi startup/session failure disables it.
