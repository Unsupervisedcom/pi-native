# Chat Architecture

## Runtime topology

```text
AppModel.conversationRuntimes
  ConversationKey A → PiConversationModel A → PiRPCClient A → pi process A
  ConversationKey B → PiConversationModel B → PiRPCClient B → pi process B
```

- [AppModel.swift](http://127.0.0.1:43117/open?path=PiNative/AppModel.swift&line=1) lazily creates one `ConversationRuntime` per selected or pending chat.
- `activeConversationModel` is only the center view's pointer to the selected runtime; it is not the sole live conversation.
- Combine subscriptions mirror each model's running/loading/error state into `conversationRuntimeStates` for sidebar indicators.
- Keyed callbacks persist session path, title summary, and transcript to the owning chat even after the user navigates away.
- Switching chats does not stop the old runtime; archive/promotion cleanup and app termination do.

## One conversation model

[PiConversationModel.swift](http://127.0.0.1:43117/open?path=PiNative/PiConversationModel.swift&line=1) owns:

- Draft and attachment state.
- Cached/live transcript items.
- Session readiness, loading, failure, and running state.
- Current model and thinking level.
- Pending initial prompt and current Pi session path.
- One `PiRPCClient`, scoped to a working directory and planning mode.

## Project chat vs Quick Chat

- Project chat working directory is the project folder and tools are enabled.
- Quick Chat working directory is the user's home folder, Pi launches with `--no-tools`, and prompts receive an explicit planning-only preamble.
- Promotion creates a new project chat/runtime; it does not retarget the Quick Chat's process.
