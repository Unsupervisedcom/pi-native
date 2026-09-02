# REQ-008: First-Response Chat Titles

## Overview

A chat created in PiNative should get a useful sidebar name without becoming a
moving target. New chats first show a deterministic fallback from the first user
prompt. After the first agent response is fully settled, PiNative may replace
that fallback with one concise semantic title. That automatic title work is
single-use: no retries, no later-turn retitling, and no surprise retitling of old
chats.

For this specification:

- A *new chat* is a chat created through PiNative after this behavior ships.
- An *accepted user prompt* contains nonempty text; attachment-only submission is outside this feature's current input path.
- The *first exchange* begins with the first accepted user prompt and ends when
  the resulting agent run is fully settled, including tool use, retries, and
  continuations that are part of that run.
- A *fallback title* is a deterministic label derived from the first user
  prompt while semantic title generation is pending or unavailable.
- A *semantic title* is an automatically generated phrase describing the first
  exchange's primary topic or task.
- An *automatic title* is either a fallback title or a semantic title.
- A *normalized prompt* has whitespace collapsed to single spaces and is compared case-insensitively.

## Requirements

### REQ-008.1: One-shot first-response naming

1. On acceptance of a new chat's first user prompt, PiNative MUST assign a nonempty deterministic fallback title and keep it until semantic title generation succeeds or becomes unavailable.
2. PiNative MUST attempt automatic semantic title generation at most once over a new chat's lifetime, only after the first exchange is fully settled.
3. After a chat's lifetime automatic title attempt is consumed, later exchanges, duplicate lifecycle events, restoration, and failed generation MUST NOT launch another attempt or replace its title automatically.
4. A persisted chat without explicit first-response title eligibility MUST NOT be automatically retitled merely because it is opened or selected.

### REQ-008.2: Title quality and authority

1. An automatic title MUST be a single-line sidebar-sized phrase no longer than 48 user-perceived Swift `Character` values.
2. A semantic title-generation request MUST contain only the first exchange and exclude later exchanges.
3. If a chat's fallback title is replaced while automatic title generation is pending, the late automatic result MUST NOT overwrite the replacement title.
4. When PiNative reconstructs a chat from persisted state, it MUST restore the accepted semantic title.
5. A semantic title MUST NOT equal the normalized first user prompt verbatim.

### REQ-008.3: Isolated responsive background work

1. Automatic title generation MUST leave the chat's visible and cached conversation transcripts unchanged.
2. No title-generation helper process MUST remain running after success, failure, or timeout.
3. While automatic title generation is pending, the composer and conversation navigation MUST remain usable. [manual]

## Acceptance fixtures

- `I am interested in learning about robots` followed by a completed response
  about robotics may settle as `Robotics Learning Guide`.
- The fallback may appear immediately after send, but the semantic title does
  not appear while assistant text is still streaming.
- Sending a second prompt after `Robotics Learning Guide` is accepted leaves
  that title unchanged.
- Reopening an older chat that has no first-response eligibility marker leaves
  its existing title unchanged.

## Non-goals

- Manual Rename Chat UI.
- Automatic title changes after later topic pivots.
- Bulk retitling existing chats.
- A title model selector or title-generation preference.
- Two-line sidebar rows or additional row metadata.
