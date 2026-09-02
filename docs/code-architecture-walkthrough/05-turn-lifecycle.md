# Chat Message Lifecycle

## The critical boundary

PiNative does **not** call an LLM provider directly. It starts `pi --mode rpc`, sends Pi newline-delimited JSON commands through stdin, and interprets Pi's newline-delimited responses/events from stdout. Pi owns the provider request, model authentication, agent loop, tool execution, retries, compaction, and canonical session write.

- Native input/rendering: [PiConversationView.swift](http://127.0.0.1:43117/open?path=PiNative/PiConversationView.swift&line=1)
- Turn state/event interpretation: [PiConversationModel.swift](http://127.0.0.1:43117/open?path=PiNative/PiConversationModel.swift&line=1)
- Process/JSONL transport: [PiRPCClient.swift](http://127.0.0.1:43117/open?path=PiNative/PiRPCClient.swift&line=1)
- Owning-chat persistence: [AppModel.swift](http://127.0.0.1:43117/open?path=PiNative/AppModel.swift&line=1)

## End-to-end: user presses Enter

```text
┌──────────────┐
│ User presses │
│    Enter     │
└──────┬───────┘
       │ keyDown → onSubmit
       ▼
┌─────────────────────────────── PiNative process ───────────────────────────────┐
│ PasteAwareTextView / AttachmentComposerShell                                  │
│       │                                                                       │
│       ▼                                                                       │
│ PiConversationModel.sendDraft()                                               │
│       │                                                                       │
│       ├─ PromptAttachmentAssembler.prepare()                                  │
│       │    ├─ text + file paths → message                                     │
│       │    └─ image bytes → RPC image payloads                                │
│       │                                                                       │
│       ├─ append .user TranscriptItem                                          │
│       ├─ AppModel callback persists title + cached transcript                 │
│       ├─ set isRunning = true                                                 │
│       │                                                                       │
│       ▼                                                                       │
│ PiRPCClient.prompt() actor                                                    │
│       │ writes one JSON object + newline to child-process stdin               │
└───────┼───────────────────────────────────────────────────────────────────────┘
        │ {"id":42,"type":"prompt","message":"…","images":[…]}\n
        ▼
┌────────────────────────────── pi --mode rpc ──────────────────────────────────┐
│ RPC command router → Pi AgentSession                                          │
│       │                                                                       │
│       ├─ immediately returns response #42: prompt accepted                    │
│       │                                                                       │
│       ▼                                                                       │
│ Agent loop → selected provider/model                                          │
│       │             │                                                         │
│       │             └── authenticated provider request ──► LLM                │
│       │                                                   │                   │
│       │             ◄── streamed text / reasoning / tool calls ───────────────┘
│       │                                                                       │
│       ├─ executes requested tools when enabled                                │
│       ├─ may call the LLM again with tool results                             │
│       ├─ writes canonical Pi session JSONL                                    │
│       └─ emits agent/message/tool lifecycle events to stdout                  │
└───────┼───────────────────────────────────────────────────────────────────────┘
        │ agent_start
        │ message_update { assistantMessageEvent: { type:"text_delta", … } }
        │ tool_execution_start / update / end   (zero or more)
        │ message_update …                      (zero or more)
        │ agent_end
        ▼
┌─────────────────────────────── PiNative process ───────────────────────────────┐
│ PiRPCClient                                                                   │
│       ├─ buffers stdout until newline                                          │
│       ├─ decodes RPCEnvelope                                                   │
│       ├─ resolves matching response IDs                                        │
│       └─ forwards non-response envelopes through onEvent                       │
│                       │                                                        │
│                       ▼ @MainActor                                              │
│ PiConversationModel.handle(event)                                              │
│       ├─ agent_start/end → running state                                       │
│       ├─ text_delta → append/update .assistantText                             │
│       ├─ tool events → correlate ActivityGroup by toolCallId                   │
│       └─ items didSet → keyed AppModel persistence callback                    │
│                       │                                                        │
│                       ▼ @Published                                              │
│ PiConversationView re-renders transcript and scrolls to the new bottom         │
└────────────────────────────────────────────────────────────────────────────────┘
```

## Command acknowledgement vs generated answer

These are separate channels and must not be conflated:

```text
stdin command #42 ─────► Pi
                       ├─► stdout response #42  = “accepted”
                       └─► stdout async events  = actual turn lifecycle/content
```

- `PiRPCClient.prompt()` completes when response `id: 42` arrives; it does **not** wait for the LLM answer.
- `PiConversationModel.isRunning` is driven by `agent_start` and `agent_end`, not by the prompt method returning.
- Streaming text arrives through `message_update` events and mutates one stable assistant transcript item incrementally.
- Tools can interleave with text and trigger additional provider turns before the final `agent_end`.

## First message and restored-chat variations

- **Brand-new chat:** `AppModel` creates a local `Session` with `pendingInitialPrompt`; the model starts Pi, sends `new_session`, asks `get_state` for the resolved session file, then flushes the prompt.
- **Existing chat:** the model sends `switch_session`, calls `get_messages`, hydrates history, and then accepts/flushes queued input.
- **Cached transcript:** visible immediately while either path completes; live hydration replaces it only when the response belongs to the current session generation.
- **Quick Chat:** the same flow launches Pi with `--no-tools` and wraps the message in a planning-only instruction.

## Failure, recovery, and Stop

- Request IDs are correlated inside the actor; each command races a timeout and all pending continuations fail if Pi exits.
- Process-exited/not-running failures get one client restart plus session rehydrate attempt.
- Catastrophic startup/session failure becomes visible chat status and disables the composer; transient notices are not persisted.
- Stop clears selected-chat UI state immediately, sends Pi's real `abort` command, suppresses late events from that turn, and restarts the client after a short abort window.
- Because every chat has its own model/client/process, stopping one chat does not interrupt another.
