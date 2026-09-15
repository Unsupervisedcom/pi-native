# REQ-014: Chat Message Formatting

## Overview

PiNative presents assistant responses as readable rich text while preserving code and progress feedback as distinct transcript content. Formatting should remain legible as assistant text streams and activity summaries accumulate. An activity group is one transcript row containing the user-facing summaries of related tool work.

## Requirements

### REQ-014.1: Assistant Markdown

1. Assistant messages containing common Markdown prose structures—headings, paragraphs, emphasis, strong emphasis, links, lists, block quotes, inline code, and fenced code—MUST display those structures as formatted content rather than visible Markdown delimiters.
2. Incomplete or malformed Markdown received while an assistant message is streaming MUST remain visible as readable text instead of causing the message to disappear.

### REQ-014.2: Activity summary separation

1. Consecutive activity summaries within one activity group MUST have visually distinct paragraph spacing rather than appearing as adjacent lines of one paragraph.

## Non-goals

- Markdown tables, remote images, or arbitrary HTML embedded in assistant Markdown.
- Syntax highlighting inside fenced code blocks.
- Changing user-message formatting.
- Exposing raw tool arguments or output in the default transcript.
